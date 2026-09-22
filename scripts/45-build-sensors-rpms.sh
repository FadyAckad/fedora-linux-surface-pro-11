#!/usr/bin/bash
# Step 4d: build the sensors stack, which step 50 installs into the live root for the installed system (inert on the
# live media, which runs without the ADSP). The accelerometer, gyroscope, magnetometer and light sensor of the
# Surface Pro 11 sit behind the ADSP's Snapdragon Sensor Core, so nothing here touches the kernel. Four RPMs:
#   hexagonrpc        hexagonrpcd from the project's fork (HEXAGONRPC_REPO): serves the DSP's sensor framework its
#                     configuration and registry over FastRPC
#   libssc (+devel)   upstream QMI client library and ssccli
#   iio-sensor-proxy  Fedora's own source RPM of the target release, rebuilt with -Dssc-support=enabled
#   sp11-sensors      this unit's payload (Windows sensor configuration, the registry exported by scripts/75, platform
#                     identity) plus the udev, systemd, SELinux and dnf integration from files/sensors/
# The first three are chain-built in a mock buildroot of the target release (iio-sensor-proxy needs libssc-devel,
# which exists nowhere else); sp11-sensors is files only and built on the host. Idempotent: the chain is skipped
# while the three RPMs match sp11.conf, sp11-sensors is rebuilt when its inputs are newer; FORCE=1 rebuilds all.
. "$(dirname "$0")/lib.sh"
require_cmd git rpmbuild mock createrepo_c rpm2cpio cpio rpm cmp
load_hardware

DEPS_DIR="$CACHE_DIR/rpm-deps/f$FEDORA_RELEASE"
ISP_SRPM=$(ls -t "$DEPS_DIR"/iio-sensor-proxy-[0-9]*.src.rpm 2>/dev/null | head -1 || true)
[ -n "$ISP_SRPM" ] || die "no iio-sensor-proxy source RPM under $DEPS_DIR (run scripts/10-fetch-sources.sh)"
ISP_VERSION=$(rpm -qp --qf '%{VERSION}' "$ISP_SRPM"); ISP_FEDREL=$(rpm -qp --qf '%{RELEASE}' "$ISP_SRPM")
ISP_BASEREL=${ISP_FEDREL%%.fc*}                                   # 3.fc45 -> 3
[ "$ISP_BASEREL" != "$ISP_FEDREL" ] || die "unexpected release '$ISP_FEDREL' in $(basename "$ISP_SRPM")"
# The template is Fedora's spec at the time of writing; a source RPM with patches needs it refreshed first.
[ -z "$(rpm -qp --qf '[%{PATCH}\n]' "$ISP_SRPM" 2>/dev/null)" ] \
  || die "$(basename "$ISP_SRPM") carries patches: refresh rpm/iio-sensor-proxy.spec.in from its spec first"

EXPECT_HEX="$HEXAGONRPC_VERSION-$HEXAGONRPC_RPM_RELEASE.fc$FEDORA_RELEASE"
EXPECT_SSC="$LIBSSC_VERSION-$LIBSSC_RPM_RELEASE.fc$FEDORA_RELEASE"
EXPECT_ISP="$ISP_VERSION-$ISP_BASEREL.$IIO_SENSOR_PROXY_RPM_SUFFIX.fc$FEDORA_RELEASE"
EXPECT_SEN="$SENSORS_VERSION-1.fc$FEDORA_RELEASE"
have() { local r; r=$(rpm_of "$1"); [ -n "$r" ] && [ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$r" 2>/dev/null)" = "$2" ]; }
chain_current() { have hexagonrpc "$EXPECT_HEX" && have libssc "$EXPECT_SSC" && have libssc-devel "$EXPECT_SSC" && have iio-sensor-proxy "$EXPECT_ISP"; }

SDIR="$BUILD_DIR/sensors"; REG="$SDIR/registry"; OVR="$SDIR/config-overrides"; SRC="$SDIR/SOURCES"
FR="$WINDOWS_ROOT/Windows/System32/DriverStore/FileRepository"
[ -d "$FR" ] || die "Windows DriverStore not found at $FR"
SNSCFG=$(find "$FR" -maxdepth 1 -type d -name "$SENSORS_SNSCFG_GLOB" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
[ -n "$SNSCFG" ] || die "no $SENSORS_SNSCFG_GLOB package under $FR (the Windows sensor configuration)"
# What the sp11-sensors payload is built from: its files under files/sensors/ (hexagonrpc's two files and the
# unpackaged probe aside), the spec, this unit's registry export and the DriverStore package. Recorded in the RPM's
# description; a same-version rebuild from other inputs is refused, because dnf would not install it.
sensors_inputs() {
  local -a in=("$SPEC_DIR/sp11-sensors.spec.in" "$REG" "$SNSCFG")
  [ -d "$OVR" ] && in+=("$OVR")
  printf '%s\n' "SENSORS_PAYLOAD_DIR=$SENSORS_PAYLOAD_DIR" "SNSCFG=$(basename "$SNSCFG")" \
    | inputs_sha256 "${in[@]}" $(find "$FILES_DIR/sensors" -maxdepth 1 -type f \
        ! -name hexagonrpc.sysusers.conf ! -name 60-hexagonrpc-fastrpc.rules ! -name sp11-sam-posture | sort)
}
INPUTS=""; [ -s "$REG/sns_reg_config" ] && INPUTS=$(sensors_inputs)
recorded_inputs() { rpm -qp --qf '%{DESCRIPTION}' "$1" 2>/dev/null | sed -n 's/^Inputs: //p' | head -1 || true; }
sensors_guard() {  # dies when the cached RPM of this version was built from other inputs, FORCE=1 or not
  local r rec; r=$(rpm_of sp11-sensors); have sp11-sensors "$EXPECT_SEN" || return 0
  rec=$(recorded_inputs "$r")
  [ -z "$rec" ] || [ -z "$INPUTS" ] || [ "$rec" = "$INPUTS" ] \
    || die "the sp11-sensors payload changed since $(basename "$r") was built, but SENSORS_VERSION is still $SENSORS_VERSION: bump it in sp11.conf (dnf ignores a same-version rebuild)"
}
sensors_current() {
  local r; r=$(rpm_of sp11-sensors); have sp11-sensors "$EXPECT_SEN" || return 1
  [ -n "$INPUTS" ] || return 1
  [ -z "$(recorded_inputs "$r")" ] || return 0   # same inputs: sensors_guard compared them
  warn "cached $(basename "$r") was built before the inputs guard; deciding by modification times"
  [ -z "$(find "$REG" "$FILES_DIR/sensors" "$SPEC_DIR/sp11-sensors.spec.in" "$SP11_ROOT/sp11.conf" -newer "$r" 2>/dev/null | head -1)" ]
}
sensors_guard
if [ "${FORCE:-0}" != 1 ] && chain_current && sensors_current; then
  log "sensors RPMs already built for Fedora $FEDORA_RELEASE (FORCE=1 to rebuild)"; exit 0
fi

## 1. Sources: pinned checkouts (git archive; hexagonrpc from the project's fork) plus this repo's packaging
##    additions, and Fedora's iio-sensor-proxy sources out of its source RPM.
rm -rf "$SRC"; mkdir -p "$SRC"
[ "$(git -C "$CACHE_DIR/hexagonrpc" rev-parse HEAD 2>/dev/null)" = "$HEXAGONRPC_COMMIT" ] || die "hexagonrpc checkout is not at $HEXAGONRPC_COMMIT (run scripts/10-fetch-sources.sh)"
[ "$(git -C "$CACHE_DIR/libssc" rev-parse HEAD 2>/dev/null)" = "$LIBSSC_COMMIT" ] || die "libssc checkout is not at $LIBSSC_COMMIT (run scripts/10-fetch-sources.sh)"
git -C "$CACHE_DIR/hexagonrpc" archive --format=tar.gz --prefix="hexagonrpc-$HEXAGONRPC_COMMIT/" -o "$SRC/hexagonrpc-$HEXAGONRPC_COMMIT.tar.gz" HEAD
git -C "$CACHE_DIR/libssc" archive --format=tar.gz --prefix="libssc-$LIBSSC_COMMIT/" -o "$SRC/libssc-$LIBSSC_COMMIT.tar.gz" HEAD
install -m 0644 "$FILES_DIR/sensors/hexagonrpc.sysusers.conf" "$FILES_DIR/sensors/60-hexagonrpc-fastrpc.rules" "$SRC/"
( cd "$SRC" && rpm2cpio "$ISP_SRPM" | cpio -idm --quiet ) || die "cannot unpack $(basename "$ISP_SRPM")"
[ -s "$SRC/iio-sensor-proxy-$ISP_VERSION.tar.bz2" ] || die "$(basename "$ISP_SRPM") does not carry iio-sensor-proxy-$ISP_VERSION.tar.bz2"
# The template is Fedora's spec plus the SSC option and the release suffix: a spec Fedora changed (a build
# requirement, a file, a scriptlet) must be merged into the template, not built around from the frozen copy.
[ "$(sha256_of "$SRC/iio-sensor-proxy.spec")" = "$IIO_SENSOR_PROXY_BASE_SPEC_SHA256" ] \
  || die "Fedora's iio-sensor-proxy.spec in $(basename "$ISP_SRPM") differs from the one rpm/iio-sensor-proxy.spec.in was derived from: diff $SRC/iio-sensor-proxy.spec against the template, refresh it, then set IIO_SENSOR_PROXY_BASE_SPEC_SHA256=$(sha256_of "$SRC/iio-sensor-proxy.spec") in sp11.conf"
rm -f "$SRC/iio-sensor-proxy.spec"

## 2. hexagonrpc, libssc and iio-sensor-proxy, chained in the target release's buildroot
if [ "${FORCE:-0}" = 1 ] || ! chain_current; then
  SRPM_SSC=$(build_srpm "$SPEC_DIR/libssc.spec.in" libssc "$SRC" COMMIT="$LIBSSC_COMMIT" VERSION="$LIBSSC_VERSION" RPMREL="$LIBSSC_RPM_RELEASE")
  SRPM_HEX=$(build_srpm "$SPEC_DIR/hexagonrpc.spec.in" hexagonrpc "$SRC" COMMIT="$HEXAGONRPC_COMMIT" VERSION="$HEXAGONRPC_VERSION" RPMREL="$HEXAGONRPC_RPM_RELEASE")
  SRPM_ISP=$(build_srpm "$SPEC_DIR/iio-sensor-proxy.spec.in" iio-sensor-proxy "$SRC" VERSION="$ISP_VERSION" BASEREL="$ISP_BASEREL" SUFFIX="$IIO_SENSOR_PROXY_RPM_SUFFIX")
  mock_chain "$SRPM_SSC" "$SRPM_HEX" "$SRPM_ISP" >/dev/null
  chain_current || die "the chain build did not produce hexagonrpc $EXPECT_HEX, libssc $EXPECT_SSC and iio-sensor-proxy $EXPECT_ISP"
else
  log "hexagonrpc, libssc and iio-sensor-proxy RPMs are current; skipping the mock chain"
fi
RPM_HEX=$(rpm_of hexagonrpc); RPM_SSC=$(rpm_of libssc); RPM_ISP=$(rpm_of iio-sensor-proxy)
rpm -qpl "$RPM_HEX" | grep -x /usr/bin/hexagonrpcd >/dev/null || die "hexagonrpc RPM lacks /usr/bin/hexagonrpcd"
rpm -qpl "$RPM_HEX" | grep -x /usr/lib/systemd/system/hexagonrpcd-adsp-sensorspd.service >/dev/null || die "hexagonrpc RPM lacks the sensorspd unit under /usr/lib/systemd/system"
rpm -qpl "$RPM_HEX" | grep -x /usr/lib/sysusers.d/hexagonrpc.conf >/dev/null || die "hexagonrpc RPM lacks the fastrpc sysusers entry"
rpm -qpl "$RPM_SSC" | grep -x /usr/bin/ssccli >/dev/null || die "libssc RPM lacks ssccli"
# The point of the rebuild: the proxy must link libssc.
rpm -qp --requires "$RPM_ISP" | grep -E '^libssc\.so\.' >/dev/null || die "iio-sensor-proxy was built without libssc (requires: $(rpm -qp --requires "$RPM_ISP" | tr '\n' ' '))"
rpm -qpl "$RPM_ISP" | grep -x /usr/lib/udev/rules.d/80-iio-sensor-proxy.rules >/dev/null || die "iio-sensor-proxy RPM lacks its udev rule"
log "chain RPMs: $(basename "$RPM_HEX") $(basename "$RPM_SSC") $(basename "$RPM_ISP")"

## 3. sp11-sensors payload. The JSON configuration and the registry are shipped as Windows has them. The three
##    kinds of control file the framework parses for *paths and values* (sns_reg_config, json.lst, the platform
##    files) are converted to LF: Windows' copies carry CRLF, and the DSP kept the CR in the values it parsed, so
##    it asked hexagonrpcd for ".../registry\r/sns_secure_database.bin" and never found its registry (seen on the
##    tested unit, 2026-09-19; Windows' own file service evidently tolerated it, hexagonfs walks the name literally).
[ -s "$REG/sns_reg_config" ] && [ -s "$REG/sns_secure_database.bin" ] \
  || die "no exported sensor registry under $REG (run scripts/75-export-sensor-registry.sh, one UAC prompt); the chain RPMs above are kept"
STAGE="$SDIR/stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
P="$STAGE$SENSORS_PAYLOAD_DIR"
install -d "$P/sensors/config" "$P/sensors/registry" "$P/socinfo"
# Every JSON of the package (the framework reads the ones json.lst names; Windows' list is not exact: on this unit
# it names one file twice and omits sns_cal.json, so the package's full set is the safe superset), and json.lst
# with its CRLF converted to LF. Each listed file has to exist.
# Modification times are kept (-p, and the spec keeps rpm's clamping off): the framework records the mtime of
# every file it parsed in its registry (sns_reg_config, one stamp per JSON, seen matching Windows' file times to
# the second); with none matching it discarded the registry and re-parsed everything (a partial mismatch has not
# been seen).
n_json=0
for f in "$SNSCFG"/*.json; do install -p -m 0644 "$f" "$P/sensors/config/$(basename "$f")"; n_json=$((n_json + 1)); done
[ "$n_json" -gt 0 ] || die "$(basename "$SNSCFG") holds no JSON sensor configuration"
n_listed=0
while IFS= read -r j; do
  [ -n "$j" ] || continue
  [ -f "$SNSCFG/$j" ] || die "json.lst names $j, which $(basename "$SNSCFG") does not contain"
  n_listed=$((n_listed + 1))
done < <(tr -d '\r' < "$SNSCFG/json.lst" | sort -u)
unlisted=$(comm -23 <(cd "$SNSCFG" && ls ./*.json | sed 's|^\./||' | sort) <(tr -d '\r' < "$SNSCFG/json.lst" | sort -u) | tr '\n' ' ')
tr -d '\r' < "$SNSCFG/json.lst" > "$P/sensors/config/json.lst"; chmod 0644 "$P/sensors/config/json.lst"
touch -r "$SNSCFG/json.lst" "$P/sensors/config/json.lst"
cmp -s <(tr -d '\r' < "$SNSCFG/json.lst") "$P/sensors/config/json.lst" || die "json.lst differs from the Windows copy beyond line endings"
[ -f "$SNSCFG/golden_color_calibration.bin" ] && install -p -m 0644 "$SNSCFG/golden_color_calibration.bin" "$P/sensors/config/golden_color_calibration.bin"
tr -d '\r' < "$SNSCFG/sns_reg_config" > "$P/sensors/sns_reg.conf"; chmod 0644 "$P/sensors/sns_reg.conf"
cmp -s <(tr -d '\r' < "$SNSCFG/sns_reg_config") "$P/sensors/sns_reg.conf" || die "sns_reg.conf differs from the Windows sns_reg_config beyond line endings"
for key in input=json.lst output=/persist/sensors/registry/registry config=/vendor/etc/sensors/config; do
  grep -q "file=$key" "$P/sensors/sns_reg.conf" || die "sns_reg_config lacks file=$key; hexagonrpcd's layout assumes it"
done
for f in hw_platform soc_id revision platform_version platform_subtype platform_subtype_id; do
  [ -s "$SNSCFG/$f" ] || die "$(basename "$SNSCFG") lacks the platform file $f"
  tr -d '\r' < "$SNSCFG/$f" > "$P/socinfo/$f"; chmod 0644 "$P/socinfo/$f"
done
[ "$(tr -d '\n' < "$P/socinfo/hw_platform")" = CRD ] || die "hw_platform is not CRD: $(cat "$P/socinfo/hw_platform")"
for f in "$P/sensors/sns_reg.conf" "$P/sensors/config/json.lst" "$P"/socinfo/*; do
  ! grep -q $'\r' "$f" || die "carriage return left in ${f#"$P/"}"
done
log "sensor configuration: $n_json JSON files ($n_listed listed in json.lst${unlisted:+; unlisted: $unlisted}), sns_reg_config, platform $(tr -d '\r\n' < "$P/socinfo/hw_platform")/soc_id $(tr -d '\r\n' < "$P/socinfo/soc_id") <- ${SNSCFG#"$FR"/}"
# This unit's registry (scripts/75) and Surface's calibration overrides, which take precedence over the package's JSONs.
cp -a "$REG"/. "$P/sensors/registry/"
# Windows keeps sns_reg_version and parsed_file_list.csv in the registry's parent directory (persist\sensors\registry\),
# not among the entries; step 75 copies them into the export, and the DSP deleted them from the entries directory as
# stale entries when they were served there (round 4), then tried to create sns_reg_version. They go to
# registry-parent/, from where tmpfiles places them next to the registry copy. Both are the DSP's own files and stay
# byte for byte (the csv is CRLF: the DSP's own convention, unlike the DriverStore files converted above).
install -d "$P/sensors/registry-parent"
for f in sns_reg_version parsed_file_list.csv; do
  [ -f "$P/sensors/registry/$f" ] && mv "$P/sensors/registry/$f" "$P/sensors/registry-parent/$f"
done
[ -s "$P/sensors/registry-parent/sns_reg_version" ] || warn "the export has no sns_reg_version; the DSP will create it through hexagonrpcd"
if [ -d "$OVR" ]; then
  for f in "$OVR"/*; do
    [ -f "$f" ] || continue
    [ -e "$P/sensors/config/$(basename "$f")" ] && log "calibration override replaces $(basename "$f")"
    cp -a "$f" "$P/sensors/config/$(basename "$f")"
  done
fi
find "$P" -type d -exec chmod 0755 {} + ; find "$P" -type f -exec chmod 0644 {} +
log "registry: $(find "$P/sensors/registry" -type f | wc -l) files; overrides: $(find "$OVR" -type f 2>/dev/null | wc -l)"

## 4. Integration (files/sensors/), rendered with the payload path
SD="$FILES_DIR/sensors"
install -D -m 0644 "$SD/81-sp11-sensors.rules" "$STAGE/usr/lib/udev/rules.d/81-sp11-sensors.rules"
install -d "$STAGE/usr/lib/systemd/system/hexagonrpcd-adsp-sensorspd.service.d"
install -m 0644 "$SD/hexagonrpcd-sensorspd-sp11.conf" "$STAGE/usr/lib/systemd/system/hexagonrpcd-adsp-sensorspd.service.d/10-sp11.conf"
install -D -m 0644 "$SD/sp11-sensors-online.service" "$STAGE/usr/lib/systemd/system/sp11-sensors-online.service"
install -D -m 0644 "$SD/sp11-sensors-resume.service" "$STAGE/usr/lib/systemd/system/sp11-sensors-resume.service"
for t in suspend.target suspend-then-hibernate.target; do
  install -d "$STAGE/usr/lib/systemd/system/$t.wants"
  ln -sf ../sp11-sensors-resume.service "$STAGE/usr/lib/systemd/system/$t.wants/sp11-sensors-resume.service"
done
install -d "$STAGE/usr/libexec/sp11"
for s in sp11-sensors-wait sp11-sensors-check; do
  render "$SD/$s" "$STAGE/usr/libexec/sp11/$s" PAYLOAD_DIR="$SENSORS_PAYLOAD_DIR"; chmod 0755 "$STAGE/usr/libexec/sp11/$s"
  bash -n "$STAGE/usr/libexec/sp11/$s" || die "shell syntax error in $s"
done
install -D -m 0644 "$SD/sp11-sensors.cil" "$STAGE/usr/share/selinux/packages/sp11-sensors.cil"
# The directory the daemon serves: links into the package plus a writable copy of the registry (tmpfiles).
install -d "$STAGE/usr/lib/tmpfiles.d"
render "$SD/sp11-sensors.tmpfiles.conf" "$STAGE/usr/lib/tmpfiles.d/sp11-sensors.conf" PAYLOAD_DIR="$SENSORS_PAYLOAD_DIR"
for s in sp11-sensors-guard sp11-sensors-reset; do
  install -m 0755 "$SD/$s" "$STAGE/usr/libexec/sp11/$s"; bash -n "$STAGE/usr/libexec/sp11/$s" || die "shell syntax error in $s"
done
install -D -m 0644 "$SD/91-sp11-sensors-dnf.conf" "$STAGE/etc/dnf/libdnf5.conf.d/91-sp11-sensors.conf"
grep -q "hexagonrpcd -R /var/lib/sp11/hexagonrpc " "$STAGE/usr/lib/systemd/system/hexagonrpcd-adsp-sensorspd.service.d/10-sp11.conf" || die "drop-in does not point hexagonrpcd at the working directory"
grep -q "^C /var/lib/sp11/hexagonrpc/sensors/persist/registry .* $SENSORS_PAYLOAD_DIR/sensors/registry\$" "$STAGE/usr/lib/tmpfiles.d/sp11-sensors.conf" || die "tmpfiles does not copy the registry from $SENSORS_PAYLOAD_DIR into sensors/persist"
grep -q "^d /var/lib/sp11/hexagonrpc/sensors/persist 0755 fastrpc fastrpc" "$STAGE/usr/lib/tmpfiles.d/sp11-sensors.conf" || die "tmpfiles does not give the fastrpc user the persist directory hexagonrpcd maps to /persist/sensors/registry"
for f in sns_reg_version parsed_file_list.csv; do
  grep -q "^C /var/lib/sp11/hexagonrpc/sensors/persist/$f .* $SENSORS_PAYLOAD_DIR/sensors/registry-parent/$f\$" "$STAGE/usr/lib/tmpfiles.d/sp11-sensors.conf" || die "tmpfiles does not place $f beside the registry copy"
done
# Nothing in the stage may reach into the DSP's lifecycle: the sensors keep running on the ADSP, and stopping it
# resets the SoC. Only the check script reads remoteproc state.
if grep -rn -E '> */sys/class/remoteproc|remoteproc[^ ]*/state' "$STAGE/usr/libexec/sp11" "$STAGE/usr/lib" | grep -v -E 'cat "\$r/state"|never touches the remoteproc' >/dev/null; then
  die "a shipped script writes to the remoteproc state"
fi

## 5. RPM
log "building sp11-sensors RPM"
RPM=$(build_rpm "$SPEC_DIR/sp11-sensors.spec.in" sp11-sensors "$SDIR" \
  STAGE="$STAGE" VERSION="$SENSORS_VERSION" SKU="$SP11_SKU" SNSCFG="$(basename "$SNSCFG")" PAYLOAD_DIR="$SENSORS_PAYLOAD_DIR" \
  INPUTS="$INPUTS")
rpm -qpl "$RPM" | grep -x "$SENSORS_PAYLOAD_DIR/sensors/registry/sns_reg_config" >/dev/null || die "sp11-sensors RPM lacks the registry"
rpm -qpl "$RPM" | grep -x "$SENSORS_PAYLOAD_DIR/sensors/registry-parent/sns_reg_version" >/dev/null || die "sp11-sensors RPM lacks sns_reg_version beside the registry"
! rpm -qpl "$RPM" | grep -x "$SENSORS_PAYLOAD_DIR/sensors/registry/sns_reg_version" >/dev/null || die "sp11-sensors RPM still carries sns_reg_version among the registry entries"
rpm -qpl "$RPM" | grep -x "$SENSORS_PAYLOAD_DIR/socinfo/hw_platform" >/dev/null || die "sp11-sensors RPM lacks the platform identity"
log "sensors RPMs: $(basename "$RPM_HEX") $(basename "$RPM_SSC") $(basename "$RPM_ISP") $(basename "$RPM") ($(du -ch "$RPM_HEX" "$RPM_SSC" "$RPM_ISP" "$RPM" | tail -1 | cut -f1))"

## 6. Prove the four install into the live root and behave (dependencies, linkage, units, rules, policy module).
if as_root test -d "$WORK_DIR/iso/rootfs/usr/lib/modules"; then
  "$(dirname "$0")/46-verify-sensors-rpms.sh" || die "46-verify-sensors-rpms.sh failed"
else
  warn "no extracted live root, so the RPMs were not verified; run scripts/46-verify-sensors-rpms.sh after scripts/50-build-iso.sh"
fi
