#!/usr/bin/bash
# Step 4b: prove the freshly built sp11-surface-support RPM actually applies the boot policy from sp11.conf,
# on both paths it reaches a machine by:
#   update — `rpm -U` over the version the live root carries with its scriptlets running, as `dnf upgrade`
#            does on the installed system; after step 50 that is the RPM under test itself, and the install is
#            then a reinstall (--replacepkgs), which runs the same %posttrans and triggers. This is the path that
#            silently did nothing until the %posttrans learned to run sp11-grub-defaults: bumping a policy value
#            in sp11.conf rebuilt grub.cfg from the *previous* /etc/default/grub, so the new policy never reached
#            the machine. SUPPORT_PREVIOUS_RPM=<rpm> installs that version (with scriptlets) first, for a real
#            upgrade from the last handed-over build.
#   live   — `rpm -U --noscripts` plus the explicit helper runs, what 50-build-iso.sh does (plus sp11-grub-modules,
#            which step 50 leaves to the installed system's Windows generator).
# Both run in an overlay of the extracted live root, so the cached root is never modified. grub2 tooling
# needs a real filesystem at /boot (an ext4 loop; mkfs.ext4 comes from the root, the host has no e2fsprogs)
# and a grub2-probe/grub2-mkrelpath stub for the overlay root, which the real ones cannot canonicalise.
. "$(dirname "$0")/lib.sh"
require_cmd rpm losetup findmnt
load_hardware

SRPM=$(rpm_of sp11-surface-support)
[ -n "$SRPM" ] || die "no sp11-surface-support RPM in $RPM_DIR (run scripts/30-build-support-rpm.sh)"
BASE="$WORK_DIR/iso/rootfs"
as_root test -d "$BASE/usr/lib/modules" \
  || die "no extracted live root at $BASE (run scripts/50-build-iso.sh first, then rerun this step)"
as_root rpm --root "$BASE" -q sp11-surface-support >/dev/null 2>&1 \
  || die "$BASE carries no sp11-surface-support to upgrade from"

T="$WORK_DIR/verify-support"; M="$T/merged"; LOOP=""
fail=0
check() { if "$@" >/dev/null 2>&1; then log "  ok: $*"; else warn "  FAIL: $*"; fail=1; fi; }

teardown() {
  for m in dev proc sys; do as_root umount -R "$M/$m" 2>/dev/null || true; done
  as_root umount "$M/boot" 2>/dev/null || true
  [ -n "$LOOP" ] && as_root losetup -d "$LOOP" 2>/dev/null; LOOP=""
  as_root umount "$M" 2>/dev/null || true
  # Never rm through a mount that refused to go away.
  if [ -z "$(mounts_under "$T")" ]; then as_root rm -rf --one-file-system "$T"; else
    warn "mounts left under $T: $(mounts_under "$T" | tr '\n' ' ')"; fi
}
trap teardown EXIT

setup() {  # fresh overlay of the live root with a real ext4 /boot and the grub2 stubs
  teardown; trap teardown EXIT
  as_root mkdir -p "$T"/upper "$T"/work "$M"
  as_root mount -t overlay overlay -o "lowerdir=$BASE,upperdir=$T/upper,workdir=$T/work" "$M"
  for m in dev proc sys; do as_root mount --rbind "/$m" "$M/$m"; as_root mount --make-rslave "$M/$m"; done
  as_root truncate -s 200M "$M/boot.img"
  as_root chroot "$M" /usr/sbin/mkfs.ext4 -q -F /boot.img || die "mkfs.ext4 in the chroot failed"
  as_root cp -a "$M/boot" "$M/boot.orig"
  LOOP=$(as_root losetup -f --show "$T/upper/boot.img") || die "losetup failed"
  as_root mount "$LOOP" "$M/boot"
  as_root cp -a "$M/boot.orig/." "$M/boot/"
  # The real grub2-probe serves the ext4 /boot (that is the path GRUB_FONT names); only the overlay root,
  # which it cannot canonicalise, falls through to canned answers.
  for b in grub2-probe grub2-mkrelpath; do as_root mv "$M/usr/bin/$b" "$M/usr/bin/$b.real"; done
  as_root tee "$M/usr/bin/grub2-probe" >/dev/null <<'STUB'
#!/usr/bin/bash
out=$(/usr/bin/grub2-probe.real "$@" 2>/dev/null) && { printf '%s\n' "$out"; exit 0; }
t=""; for a in "$@"; do case "$a" in --target=*) t=${a#--target=} ;; esac; done
case "$t" in
  device) echo /dev/sda3 ;; fs) echo ext2 ;; partmap) echo gpt ;;
  fs_uuid) echo 11111111-2222-3333-4444-555555555555 ;;
  drive|compatibility_hint) echo '(hd0,gpt3)' ;; *) : ;;
esac
exit 0
STUB
  as_root tee "$M/usr/bin/grub2-mkrelpath" >/dev/null <<'STUB'
#!/usr/bin/bash
out=$(/usr/bin/grub2-mkrelpath.real "$@" 2>/dev/null) && { printf '%s\n' "$out"; exit 0; }
p=${1:-/}; printf '%s\n' "${p#/boot}"
STUB
  as_root chmod 0755 "$M/usr/bin/grub2-probe" "$M/usr/bin/grub2-mkrelpath"
  as_root cp "$SRPM" "$M/tmp/"
}

# The GRUB policy values (device tree, mode, terminal, timeout, font) have to arrive in /etc/default/grub and, on
# the update path, through grub2-mkconfig in the generated menu (the live root has no menu; the installer writes
# it). Asserting both ends is what catches a policy change that installs but never applies.
assert_policy() {
  local what=$1 cfg="$M/etc/default/grub" menu="$M/boot/grub2/grub.cfg"
  log "$what: /etc/default/grub and the generated menu"
  check as_root grep -qx "GRUB_DEVICETREE=\"$SP11_DTB\"" "$cfg"
  check as_root grep -qx "GRUB_GFXMODE=$GRUB_GFXMODE_VALUE" "$cfg"
  check as_root grep -qx 'GRUB_TERMINAL_OUTPUT="gfxterm"' "$cfg"
  check as_root grep -qx "GRUB_TIMEOUT=$GRUB_TIMEOUT_VALUE" "$cfg"
  check as_root grep -qx "GRUB_FONT=\"/boot/grub2/fonts/$GRUB_FONT_FILE\"" "$cfg"
  check as_root test -s "$M/boot/grub2/fonts/$GRUB_FONT_FILE"
  if [ "$what" = update ]; then
    check as_root grep -qx "  set gfxmode=$GRUB_GFXMODE_VALUE" "$menu"
    check as_root grep -qx "if loadfont /grub2/fonts/$GRUB_FONT_FILE ; then" "$menu"
    check as_root grep -qx "  set timeout=$GRUB_TIMEOUT_VALUE" "$menu"
  fi
}

## 1. Update path: an installed system running the previous support RPM, with a deliberately wrong policy in
##    /etc/default/grub. `rpm -U` with scriptlets must put every value back and rebuild the menu from it.
setup
if [ -n "${SUPPORT_PREVIOUS_RPM:-}" ]; then
  [ -f "$SUPPORT_PREVIOUS_RPM" ] || die "no such RPM: $SUPPORT_PREVIOUS_RPM"
  as_root cp "$SUPPORT_PREVIOUS_RPM" "$M/tmp/"
  as_root chroot "$M" /usr/bin/rpm -U --oldpackage --replacepkgs --define '_pkgverify_level none' "/tmp/${SUPPORT_PREVIOUS_RPM##*/}" \
    || die "rpm -U of ${SUPPORT_PREVIOUS_RPM##*/} failed in the chroot"
fi
FROM_NVR=$(as_root chroot "$M" /usr/bin/rpm -q sp11-surface-support)
NVR=$(basename "$SRPM" .rpm)
log "--- update path: rpm -U over $FROM_NVR with scriptlets"
as_root chroot "$M" /usr/libexec/sp11/sp11-grub-defaults || die "the installed helper failed in the chroot"
as_root install -d "$M/var/lib/sp11"; echo stale | as_root tee "$M/var/lib/sp11/first-boot.done" >/dev/null
as_root sed -i -e 's|^GRUB_GFXMODE=.*|GRUB_GFXMODE=640x480|' -e 's|^GRUB_FONT=.*|GRUB_FONT=|' \
               -e 's|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=99|' "$M/etc/default/grub"
as_root rm -f "$M/boot/grub2/fonts/$GRUB_FONT_FILE"
# Also what an installer that ran without SELinux leaves behind (selinux=0 and SELINUX=disabled); the
# %posttrans has to undo it through sp11-selinux-restore.
printf 'root=UUID=0000-test ro rhgb quiet selinux=0 clk_ignore_unused pd_ignore_unused\n' \
  | as_root tee "$M/etc/kernel/cmdline" >/dev/null
as_root sed -i '/^GRUB_CMDLINE_LINUX=/d' "$M/etc/default/grub"
echo 'GRUB_CMDLINE_LINUX="rhgb quiet selinux=0"' | as_root tee -a "$M/etc/default/grub" >/dev/null
as_root sed -i 's/^SELINUX=.*/SELINUX=disabled/' "$M/etc/selinux/config"
as_root rm -f "$M/.autorelabel"
as_root chroot "$M" /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 \
  || die "grub2-mkconfig failed while staging the pre-upgrade state"
as_root grep -qx 'GRUB_GFXMODE=640x480' "$M/etc/default/grub" || die "pre-upgrade state not staged"
if [ "$FROM_NVR" = "$NVR" ]; then
  # The live root carries the RPM under test (step 50 installed it): rpm refuses a plain -U of an installed NVR.
  log "$NVR is already installed: reinstalling with --replacepkgs (same %posttrans and triggers)"
  as_root chroot "$M" /usr/bin/rpm -U --replacepkgs --define '_pkgverify_level none' "/tmp/${SRPM##*/}" \
    || die "rpm -U --replacepkgs of ${SRPM##*/} failed in the chroot"
else
  as_root chroot "$M" /usr/bin/rpm -U --define '_pkgverify_level none' "/tmp/${SRPM##*/}" \
    || die "rpm -U of ${SRPM##*/} failed in the chroot"
fi
[ "$(as_root chroot "$M" /usr/bin/rpm -q sp11-surface-support)" = "$NVR" ] \
  || die "the chroot ended up with a different package than $NVR"
assert_policy update
log "update: the installer's SELinux disable is undone"
check as_root sh -c "! grep -qw selinux=0 '$M/etc/kernel/cmdline'"
check as_root sh -c "! grep -qw selinux=0 '$M/etc/default/grub'"
check as_root grep -qx 'SELINUX=enforcing' "$M/etc/selinux/config"
check as_root test -e "$M/.autorelabel"
# Negative control: a system disabled by hand carries the config line alone and must stay untouched.
as_root sed -i 's/^SELINUX=.*/SELINUX=disabled/' "$M/etc/selinux/config"; as_root rm -f "$M/.autorelabel"
as_root chroot "$M" /usr/libexec/sp11/sp11-selinux-restore || die "sp11-selinux-restore failed on the negative control"
check as_root grep -qx 'SELINUX=disabled' "$M/etc/selinux/config"
check as_root test ! -e "$M/.autorelabel"

## 2. Live path: what 50-build-iso.sh does to the live root — install without scriptlets, then run the
##    helpers explicitly (sp11-grub-modules as well, which step 50 leaves to the installed system). Catches a
##    payload whose helpers do not run in a root that has never booted.
log "--- live path: rpm -U --noscripts plus the explicit helper runs"
setup
as_root chroot "$M" /usr/bin/rpm -U --noscripts --replacefiles --replacepkgs --define '_pkgverify_level none' \
  "/tmp/${SRPM##*/}" || die "rpm -U --noscripts of ${SRPM##*/} failed in the chroot"
as_root chroot "$M" /usr/libexec/sp11/sp11-ucm-apply || die "sp11-ucm-apply failed in the live root"
as_root chroot "$M" /usr/libexec/sp11/sp11-grub-defaults || die "sp11-grub-defaults failed in the live root"
as_root chroot "$M" /usr/libexec/sp11/sp11-grub-modules || die "sp11-grub-modules failed in the live root"
assert_policy live
log "live path: shipped helpers"
for h in sp11-first-boot sp11-grub-defaults sp11-grub-modules sp11-selinux-restore sp11-bt-apply sp11-ucm-apply \
         sp11-bt-import-pairings sp11-diag; do
  check as_root chroot "$M" /usr/bin/bash -n "/usr/libexec/sp11/$h"
done
check as_root chroot "$M" /usr/bin/bash -n /usr/lib/kernel/install.d/15-sp11-surface.install
check as_root chroot "$M" /usr/bin/sh -n /etc/grub.d/29_sp11_windows
check as_root test -x "$M/usr/libexec/sp11/sp11-bt-set-addr"
check as_root test -f "$M/boot/grub2/arm64-efi/chain.mod"

teardown; trap - EXIT
[ "$fail" -eq 0 ] || die "support RPM verification failed (see the FAIL lines above)"
log "support RPM verified on both paths: ${SRPM##*/}"
