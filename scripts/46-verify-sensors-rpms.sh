#!/usr/bin/bash
# Step 4e: prove the sensors RPMs (scripts/45) install into the live root the way `dnf install` does on the installed
# system and hold together: dependencies, linkage against the target release's libraries, the units, udev rules,
# the SELinux module, the fastrpc user, the merged dnf exclusions and the payload. Runs in an overlay of the
# extracted live root (which carries the stack itself since step 50 installs it), so the cached root is never
# modified. What only the device can show (the DSP accepting the
# registry, sensor data, orientation) is not covered: see sp11-sensors-check on the installed system.
. "$(dirname "$0")/lib.sh"
require_cmd rpm findmnt

BASE="$WORK_DIR/iso/rootfs"
as_root test -d "$BASE/usr/lib/modules" || die "no extracted live root at $BASE (run scripts/50-build-iso.sh first)"
declare -a RPMS=()
for n in hexagonrpc libssc iio-sensor-proxy sp11-sensors; do
  r=$(rpm_of "$n"); [ -n "$r" ] || die "no $n RPM in $RPM_DIR (run scripts/45-build-sensors-rpms.sh)"; RPMS+=("$r")
done
# Runtime dependencies the live image may lack (downloaded by scripts/10 for exactly this); only the missing ones.
# By capability, not name: Fedora 45 ships protobuf-c's library as protobuf3-c, which obsoletes and provides it.
DEPS_DIR="$CACHE_DIR/rpm-deps/f$FEDORA_RELEASE"
declare -a DEPS=()
for pkg in $SENSORS_DEPS_PKGS; do
  as_root rpm --root "$BASE" -q --whatprovides "$pkg" >/dev/null 2>&1 && continue
  f=$(ls -t "$DEPS_DIR/$pkg"-[0-9]*.rpm 2>/dev/null | head -1 || true)
  [ -n "$f" ] || die "the live root lacks $pkg and $DEPS_DIR has no RPM for it (run scripts/10-fetch-sources.sh)"
  DEPS+=("$f")
done

T="$WORK_DIR/verify-sensors"; M="$T/merged"
fail=0
check() { if "$@" >/dev/null 2>&1; then log "  ok: $*"; else warn "  FAIL: $*"; fail=1; fi; }
inroot() { as_root chroot "$M" "$@"; }
teardown() {
  # A cgroup submount under the bound /sys can refuse a recursive unmount; detach lazily rather than leave it.
  for m in dev proc sys; do as_root umount -R "$M/$m" 2>/dev/null || as_root umount -lR "$M/$m" 2>/dev/null || true; done
  as_root umount "$M" 2>/dev/null || as_root umount -l "$M" 2>/dev/null || true
  if [ -z "$(mounts_under "$T")" ]; then as_root rm -rf --one-file-system "$T"; else
    warn "mounts left under $T: $(mounts_under "$T" | tr '\n' ' ')"; fi
}
setup_overlay() {
  teardown
  as_root mkdir -p "$T"/upper "$T"/work "$M"
  as_root mount -t overlay overlay -o "lowerdir=$BASE,upperdir=$T/upper,workdir=$T/work" "$M"
  for m in dev proc sys; do as_root mount --rbind "/$m" "$M/$m"; as_root mount --make-rslave "$M/$m"; done
  as_root install -d "$M/tmp/sensors"
}
# Copies RPMs into the chroot; prints their chroot-side paths.
stage_rpms() { local f; for f in "$@"; do as_root cp "$f" "$M/tmp/sensors/"; echo "/tmp/sensors/$(basename "$f")"; done; }
trap teardown EXIT
setup_overlay
declare -a IN=(); mapfile -t IN < <(stage_rpms "${DEPS[@]}" "${RPMS[@]}")

## 1. Install as dnf would: dependency check, then the real transaction with scriptlets (sysusers, semodule).
##    Step 50 installs the same set into the live root, so after an ISO build this is a reinstall (--replacepkgs,
##    which runs the same scriptlets); on a root without the stack it is the plain install.
log "--- install into an overlay of the live root: ${#DEPS[@]} dependency RPM(s) + ${#RPMS[@]} sensors RPMs"
inroot /usr/bin/rpm -U --test --replacepkgs --define '_pkgverify_level none' "${IN[@]}" \
  || die "the sensors RPMs have unmet dependencies in the live root (see above)"
inroot /usr/bin/rpm -U --replacepkgs --define '_pkgverify_level none' "${IN[@]}" || die "rpm -U of the sensors RPMs failed in the chroot"
for n in hexagonrpc libssc iio-sensor-proxy sp11-sensors; do check inroot /usr/bin/rpm -q "$n"; done
check inroot /usr/bin/rpm -q --whatprovides 'libssc.so.2()(64bit)'

## 2. Binaries link against the root's libraries and run.
log "--- binaries"
for b in /usr/bin/hexagonrpcd /usr/bin/ssccli /usr/libexec/iio-sensor-proxy /usr/bin/monitor-sensor /usr/bin/qrtr-lookup /usr/bin/sscregistrygen; do
  check as_root test -x "$M$b"
  check as_root sh -c "chroot '$M' /usr/bin/ldd '$b' | grep -v 'not found' >/dev/null && ! chroot '$M' /usr/bin/ldd '$b' | grep -q 'not found'"
done
check as_root sh -c "chroot '$M' /usr/bin/hexagonrpcd 2>&1 | grep -q 'Usage:'"
check as_root sh -c "chroot '$M' /usr/bin/ssccli --help 2>&1 | grep -q -- '--sensor'"
# The proxy's linkage is the whole point of the rebuild.
check as_root sh -c "chroot '$M' /usr/bin/ldd /usr/libexec/iio-sensor-proxy | grep -q libssc.so.2"
check as_root sh -c "chroot '$M' /usr/bin/ldd /usr/bin/ssccli | grep -q libqmi-glib.so"

## 3. Users, units, rules, policy, dnf.
log "--- integration"
check as_root sh -c "chroot '$M' /usr/bin/getent passwd fastrpc >/dev/null"
check as_root sh -c "chroot '$M' /usr/bin/getent group fastrpc >/dev/null"
check as_root test -f "$M/usr/lib/systemd/system/hexagonrpcd-adsp-sensorspd.service"
check as_root grep -q '^Conflicts=suspend.target' "$M/usr/lib/systemd/system/hexagonrpcd-adsp-sensorspd.service"
check as_root test -L "$M/usr/lib/systemd/system/suspend.target.wants/sp11-sensors-resume.service"
if as_root chroot "$M" /usr/bin/udevadm verify --help >/dev/null 2>&1; then
  for r in 60-hexagonrpc-fastrpc.rules 81-sp11-sensors.rules 80-iio-sensor-proxy.rules; do
    check inroot /usr/bin/udevadm verify "/usr/lib/udev/rules.d/$r"
  done
else
  warn "  udevadm verify unavailable in this root; rules not syntax-checked"
fi
for u in sp11-sensors-online.service sp11-sensors-resume.service hexagonrpcd-adsp-sensorspd.service iio-sensor-proxy.service; do
  check inroot /usr/bin/systemd-analyze verify --man=no "/usr/lib/systemd/system/$u"
done
check as_root grep -q 'ssc-accel' "$M/usr/lib/udev/rules.d/81-sp11-sensors.rules"
check as_root grep -q 'ssc-light ssc-compass' "$M/usr/lib/udev/rules.d/80-iio-sensor-proxy.rules"
check as_root grep -q 'RestrictAddressFamilies=.*AF_QIPCRTR' "$M/usr/lib/systemd/system/iio-sensor-proxy.service"
# %post loaded the CIL module into the root's policy store (no policy is active in the chroot, so it only compiles).
check as_root sh -c "chroot '$M' /usr/sbin/semodule -l | grep -qx sp11-sensors"
# Both dnf drop-ins have to stay in force: the kernel exclusion and the proxy exclusion.
check as_root sh -c "chroot '$M' /usr/bin/dnf --dump-main-config 2>/dev/null | grep -E '^excludepkgs' | grep -q 'kernel-uki-'"
check as_root sh -c "chroot '$M' /usr/bin/dnf --dump-main-config 2>/dev/null | grep -E '^excludepkgs' | grep -q 'iio-sensor-proxy'"
for s in sp11-sensors-wait sp11-sensors-check; do check inroot /usr/bin/bash -n "/usr/libexec/sp11/$s"; done
# The helper hands late sensors to the running proxy through a udev "add" event and never restarts it: the CDSP
# firmware asserted while the proxy tore its sensor streams down (1.8, and 1.4 before it).
check as_root grep -q 'udevadm trigger --action=add' "$M/usr/libexec/sp11/sp11-sensors-wait"
check as_root sh -c "! grep -qE 'systemctl .*(restart|stop)' '$M/usr/libexec/sp11/sp11-sensors-wait'"

## 3b. The working directory the daemon serves (created by %posttrans through tmpfiles): links into the package, a
##     registry copy the daemon's user can write, and the guard that keeps a DSP crash from becoming a loop.
log "--- working directory and guard"
W="$M/var/lib/sp11/hexagonrpc"
# The links carry absolute targets and the owner is a chroot-only user: resolve both inside the chroot.
check as_root test -L "$W/sensors/config"
check inroot /usr/bin/test -f /var/lib/sp11/hexagonrpc/sensors/config/json.lst
check inroot /usr/bin/test -f /var/lib/sp11/hexagonrpc/sensors/sns_reg.conf
check inroot /usr/bin/test -f /var/lib/sp11/hexagonrpc/socinfo/hw_platform
# sensors/persist is what hexagonrpcd maps to the DSP's /persist/sensors/registry (the framework writes a temporary
# file there and renames it into the registry); persist/registry is the copy of the registry. Both belong to the
# daemon's user; the 1.3/1.4 copy at sensors/registry must be gone.
check as_root test -d "$W/sensors/persist/registry"
check as_root test ! -e "$W/sensors/registry"
check as_root test -s "$W/sensors/persist/registry/sns_reg_config"
check test "$(as_root chroot "$M" /usr/bin/stat -c %U /var/lib/sp11/hexagonrpc/sensors/persist)" = fastrpc
check test "$(as_root chroot "$M" /usr/bin/stat -c %U /var/lib/sp11/hexagonrpc/sensors/persist/registry)" = fastrpc
check test "$(as_root chroot "$M" /usr/bin/stat -c %U /var/lib/sp11/hexagonrpc/sensors/persist/registry/sns_reg_config)" = fastrpc
# The framework's own sequence, as the fastrpc user: create the temporary file next to the registry, rename it into
# the registry, remove it. (Not named DIR: the registry exported from Windows contains the framework's own marker
# file of that name.)
check as_root sh -c "chroot '$M' /usr/bin/runuser -u fastrpc -- /usr/bin/sh -c 'cd /var/lib/sp11/hexagonrpc/sensors/persist && echo x > fstempfile && mv fstempfile registry/sp11-write-test && rm registry/sp11-write-test'"
check as_root test ! -e "$W/sensors/persist/fstempfile"
check as_root test ! -e "$W/sensors/persist/registry/sp11-write-test"
# The two files Windows keeps beside the registry directory sit beside the copy, not inside it (1.6).
check as_root sh -c "grep -q '^version=' '$W/sensors/persist/sns_reg_version'"
check as_root test -s "$W/sensors/persist/parsed_file_list.csv"
check as_root test ! -e "$W/sensors/persist/registry/sns_reg_version"
check test "$(as_root chroot "$M" /usr/bin/stat -c %U /var/lib/sp11/hexagonrpc/sensors/persist/sns_reg_version)" = fastrpc
# The copy must hold exactly the payload's files (compared by name; a bare count once differed transiently), with
# the payload's modification times (tmpfiles' C keeps them; the framework compares them with its registry).
# ($T is root-owned; the listings go next to it, written as the build user.)
LST="$WORK_DIR/verify-sensors-lists"; rm -rf "$LST"; mkdir -p "$LST"
as_root sh -c "cd '$M$SENSORS_PAYLOAD_DIR/sensors/registry' && find . -type f | sort" > "$LST/payload.lst"
as_root sh -c "cd '$W/sensors/persist/registry' && find . -type f | sort" > "$LST/copy.lst"
check test "$(as_root stat -c %Y "$W/sensors/persist/registry/tdm_uid.bin")" = "$(as_root stat -c %Y "$M$SENSORS_PAYLOAD_DIR/sensors/registry/tdm_uid.bin")"
check cmp -s "$LST/payload.lst" "$LST/copy.lst"
cmp -s "$LST/payload.lst" "$LST/copy.lst" \
  || warn "  registry copy differs from the payload: $(comm -3 "$LST/payload.lst" "$LST/copy.lst" | tr -s '\t\n' '  ')"
log "  registry copy: $(grep -c . "$LST/copy.lst") files, payload $(grep -c . "$LST/payload.lst")"
rm -rf "$LST"
check as_root grep -q '^ExecStart=/usr/bin/stdbuf -oL /usr/bin/hexagonrpcd -R /var/lib/sp11/hexagonrpc -f /dev/fastrpc-adsp -d adsp -s$' \
  "$M/usr/lib/systemd/system/hexagonrpcd-adsp-sensorspd.service.d/10-sp11.conf"
check as_root grep -q '^ExecCondition=+/usr/libexec/sp11/sp11-sensors-guard$' "$M/usr/lib/systemd/system/hexagonrpcd-adsp-sensorspd.service.d/10-sp11.conf"
# The guard must be a condition, not a pre-start command: RestartPreventExitStatus= covers the main process only,
# and an ExecStartPre exit 3 was restarted until the start limit (systemd 259), which would re-run the guard
# instead of ending the unit. Neither setting may come back.
check as_root sh -c "! grep -qE '^(ExecStartPre|RestartPreventExitStatus)=' '$M/usr/lib/systemd/system/hexagonrpcd-adsp-sensorspd.service.d/10-sp11.conf'"
# No crash in this (non-)boot: the guard lets the attach through and counts it.
check inroot /usr/libexec/sp11/sp11-sensors-guard
check as_root test -s "$M/run/sp11-sensors/attaches"
check inroot /usr/bin/bash -n /usr/libexec/sp11/sp11-sensors-reset
# The initramfs is regenerated only when a 1.1/1.2 package (the initramfs hook) is upgraded away, by a trigger; the
# unconditional dracut run of 1.3-1.9's %posttrans must not come back.
check as_root sh -c "! chroot '$M' /usr/bin/rpm -q --scripts sp11-sensors | grep -q 'dracut -f'"
check as_root sh -c "chroot '$M' /usr/bin/rpm -q --triggers sp11-sensors | grep -q 'dracut -f'"
# The daemon in the RPM carries the fork's registry writes (a message only its apps_std prints).
check as_root sh -c "grep -q 'Could not remove' '$M/usr/bin/hexagonrpcd'"
check as_root sh -c "grep -q 'Could not write file' '$M/usr/bin/hexagonrpcd'"
# ... and release 3's listener (large input buffers) and builder (persist parent): messages only they print.
check as_root sh -c "grep -q 'Could not fetch large input buffers' '$M/usr/bin/hexagonrpcd'"
check as_root sh -c "! grep -q \"Large (>256B) input buffers aren't implemented\" '$M/usr/bin/hexagonrpcd'"
check as_root sh -c "grep -q '/sensors/persist/' '$M/usr/bin/hexagonrpcd'"
# Release 6 probes the registry itself, not just its parent: a persist directory without one would otherwise
# hide the packaged registry behind a directory nothing can create at runtime.
check as_root sh -c "grep -q '/sensors/persist/registry' '$M/usr/bin/hexagonrpcd'"
check as_root test ! -e "$M/usr/lib/dracut/modules.d/95sp11-sensors"

## 4. Payload: what the DSP will read, readable by the fastrpc user.
log "--- payload under $SENSORS_PAYLOAD_DIR"
P="$M$SENSORS_PAYLOAD_DIR"
# json.lst is Windows' list as shipped (it may name a file twice); the unique set is what has to exist.
n_lst=$(as_root sh -c "tr -d '\r' < '$P/sensors/config/json.lst' | grep . | sort -u | wc -l"); n_json=$(as_root find "$P/sensors/config" -name '*.json' | wc -l)
check test "$n_lst" -gt 0
# With no configuration file's mtime matching the stamp its registry recorded (registry/sns_reg_config, one entry
# per JSON) the framework discarded the registry and re-parsed everything (a partial mismatch has not been seen):
# the served files must carry Windows' modification times through the stage, the RPM (no clamping) and the install.
for j in 8380_crd_lsm6dsv_display.json 8380_crd_tcs3430_0.json; do
  stamp=$(as_root sh -c "grep -o '\"$j\":{[^}]*}' '$P/sensors/registry/sns_reg_config'" | sed -n 's/.*"data":"\([0-9]*\)".*/\1/p')
  check test -n "$stamp"
  check test "$(as_root stat -c %Y "$P/sensors/config/$j")" = "$stamp"
done
check test "$n_json" -ge "$n_lst"
check as_root sh -c "tr -d '\r' < '$P/sensors/config/json.lst' | while read -r j; do [ -z \"\$j\" ] || [ -f '$P/sensors/config/'\"\$j\" ] || exit 1; done"
check as_root grep -q 'file=input=json.lst' "$P/sensors/sns_reg.conf"
# The DSP keeps a CR from a CRLF value in the paths it builds; the control files it parses must be LF.
check as_root sh -c "! grep -q \$'\\r' '$P/sensors/sns_reg.conf' '$P/sensors/config/json.lst' '$P'/socinfo/*"
check test "$(as_root find "$P/sensors/registry" -type f | wc -l)" -ge 100
check as_root test -s "$P/sensors/registry/sns_reg_config"
check as_root test -s "$P/sensors/registry/sns_secure_database.bin"
# Windows keeps these two beside the registry directory, not among the entries (the DSP deletes them there as stale
# entries and then tries to create sns_reg_version); the payload carries them in registry-parent.
check as_root sh -c "grep -q '^version=' '$P/sensors/registry-parent/sns_reg_version'"
check as_root test -s "$P/sensors/registry-parent/parsed_file_list.csv"
check as_root test ! -e "$P/sensors/registry/sns_reg_version"
check as_root test ! -e "$P/sensors/registry/parsed_file_list.csv"
for f in hw_platform soc_id revision platform_version platform_subtype platform_subtype_id; do check as_root test -s "$P/socinfo/$f"; done
check test "$(as_root sh -c "tr -d '\r\n' < '$P/socinfo/hw_platform'")" = CRD
check test -z "$(as_root find "$P" -type f ! -perm 0644 | head -1)"
check test -z "$(as_root find "$P" -type d ! -perm 0755 | head -1)"
check as_root sh -c "chroot '$M' /usr/bin/runuser -u fastrpc -- /usr/bin/cat '$SENSORS_PAYLOAD_DIR/sensors/registry/sns_reg_config' >/dev/null"
log "  payload: $n_json JSON configs ($n_lst listed), $(as_root find "$P/sensors/registry" -type f | wc -l) registry files"

## 5. Erase leaves nothing behind (the payload directory, the drop-in, the policy module).
log "--- erase"
inroot /usr/bin/rpm -e sp11-sensors || die "rpm -e sp11-sensors failed"
check as_root test ! -e "$P"
check as_root test ! -e "$M/usr/lib/systemd/system/hexagonrpcd-adsp-sensorspd.service.d"
check as_root test ! -e "$M/etc/dnf/libdnf5.conf.d/91-sp11-sensors.conf"
check as_root test ! -e "$M/var/lib/sp11/hexagonrpc"
check as_root sh -c "! chroot '$M' /usr/sbin/semodule -l | grep -qx sp11-sensors"

## 6. Upgrade from a previously handed-over release, which is what the device does between rounds.
##    SENSORS_PREVIOUS_RPMS names the earlier RPMs (space-separated paths, e.g. the previous hexagonrpc and
##    sp11-sensors): they go into a fresh overlay first, together with the current RPMs of the other names; the unit
##    is masked the way the owner stops a crash loop; then the current builds of the same names go on top with
##    rpm -U and scriptlets, as `dnf install ./a.rpm ./b.rpm` does on the installed system.
if [ -n "${SENSORS_PREVIOUS_RPMS:-}" ]; then
  log "--- upgrade from: $SENSORS_PREVIOUS_RPMS"
  declare -a PREV=() KEEP=() NEW=(); prev_names=""
  for f in $SENSORS_PREVIOUS_RPMS; do
    [ -f "$f" ] || die "no such RPM: $f"
    PREV+=("$f"); prev_names="$prev_names $(rpm -qp --qf '%{NAME}' "$f")"
  done
  for f in "${RPMS[@]}"; do
    n=$(rpm -qp --qf '%{NAME}' "$f")
    case " $prev_names " in *" $n "*) NEW+=("$f");; *) KEEP+=("$f");; esac
  done
  [ "${#NEW[@]}" -gt 0 ] || die "SENSORS_PREVIOUS_RPMS names no package of the current set"
  setup_overlay
  declare -a OLD_IN=(); mapfile -t OLD_IN < <(stage_rpms "${DEPS[@]}" "${KEEP[@]}" "${PREV[@]}")
  # --oldpackage: the previous release is older than what the live root carries since step 50.
  inroot /usr/bin/rpm -U --oldpackage --replacepkgs --define '_pkgverify_level none' "${OLD_IN[@]}" || die "rpm -U of the previous release failed in the chroot"
  for f in "${PREV[@]}"; do check inroot /usr/bin/rpm -q "$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}' "$f")"; done
  as_root test -e "$M/usr/lib/dracut/modules.d/95sp11-sensors" && log "  the previous release carries the initramfs hook; the upgrade must take it out"
  # The owner's state after a crash loop: the unit masked. An admin's symlink in /etc, which rpm must leave alone.
  inroot /usr/bin/ln -sf /dev/null /etc/systemd/system/hexagonrpcd-adsp-sensorspd.service
  declare -a NEW_IN=(); mapfile -t NEW_IN < <(stage_rpms "${NEW[@]}")
  inroot /usr/bin/rpm -U --test --define '_pkgverify_level none' "${NEW_IN[@]}" || die "the upgrade has unmet dependencies in the live root (see above)"
  inroot /usr/bin/rpm -U --define '_pkgverify_level none' "${NEW_IN[@]}" || die "rpm -U of the upgrade failed in the chroot"
  for f in "${NEW[@]}"; do check inroot /usr/bin/rpm -q "$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}' "$f")"; done
  for f in "${PREV[@]}"; do check as_root sh -c "! chroot '$M' /usr/bin/rpm -q '$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}' "$f")'"; done
  check as_root test ! -e "$M/usr/lib/dracut/modules.d/95sp11-sensors"
  check as_root test -L "$M/etc/systemd/system/hexagonrpcd-adsp-sensorspd.service"
  check as_root test -f "$M/usr/lib/systemd/system/hexagonrpcd-adsp-sensorspd.service"
  check as_root grep -q '^ExecCondition=+/usr/libexec/sp11/sp11-sensors-guard$' "$M/usr/lib/systemd/system/hexagonrpcd-adsp-sensorspd.service.d/10-sp11.conf"
  check as_root sh -c "! grep -qE '^(ExecStartPre|RestartPreventExitStatus)=' '$M/usr/lib/systemd/system/hexagonrpcd-adsp-sensorspd.service.d/10-sp11.conf'"
  check as_root test -f "$M/usr/lib/tmpfiles.d/sp11-sensors.conf"
  check inroot /usr/bin/test -f /var/lib/sp11/hexagonrpc/sensors/config/json.lst
  # The working copy moved from sensors/registry (1.3, 1.4) to sensors/persist/registry; %posttrans removes the old one.
  check as_root test -s "$W/sensors/persist/registry/sns_reg_config"
  check as_root test ! -e "$W/sensors/registry"
  check as_root sh -c "grep -q '^version=' '$W/sensors/persist/sns_reg_version'"
  check as_root test ! -e "$W/sensors/persist/registry/sns_reg_version"
  check test "$(as_root chroot "$M" /usr/bin/stat -c %U /var/lib/sp11/hexagonrpc/sensors/persist)" = fastrpc
  check test "$(as_root chroot "$M" /usr/bin/stat -c %U /var/lib/sp11/hexagonrpc/sensors/persist/registry)" = fastrpc
  check as_root sh -c "chroot '$M' /usr/sbin/semodule -l | grep -qx sp11-sensors"
  check as_root sh -c "grep -q 'Could not remove' '$M/usr/bin/hexagonrpcd'"
  check as_root sh -c "grep -q 'Could not fetch large input buffers' '$M/usr/bin/hexagonrpcd'"
  check as_root sh -c "grep -q '/sensors/persist/registry' '$M/usr/bin/hexagonrpcd'"
  check as_root test -x "$M/usr/libexec/sp11/sp11-sensors-guard"
  check as_root test -x "$M/usr/libexec/sp11/sp11-sensors-reset"
  check as_root sh -c "chroot '$M' /usr/bin/rpm -qf /usr/lib/systemd/system/hexagonrpcd-adsp-sensorspd.service.d/10-sp11.conf | grep -q '^sp11-sensors-'"
  log "  upgraded: $(for f in "${NEW[@]}"; do basename "$f"; done | tr '\n' ' ')"
else
  log "--- upgrade from a previous release: skipped (SENSORS_PREVIOUS_RPMS=\"<previous hexagonrpc rpm> <previous sp11-sensors rpm>\" runs it)"
fi

teardown; trap - EXIT
[ "$fail" -eq 0 ] || die "sensors RPM verification failed (see the FAIL lines above)"
log "sensors RPMs verified in the live root: $(for f in "${RPMS[@]}"; do basename "$f"; done | tr '\n' ' ')"
