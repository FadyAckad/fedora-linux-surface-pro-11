#!/usr/bin/bash
# Step 4c (standalone, for a kernel RPM handed to an installed system): prove the freshly built kernel-sp11
# RPM installs the way `dnf install ./kernel-sp11-*.rpm` does on a running Fedora — next to the kernel that is
# already there (install-only package, so `rpm -i` with scriptlets) — and that the system ends up set to boot it:
#   %posttrans runs depmod and `kernel-install add`; the SP11 plugin and Fedora's 20-grub.install write the BLS
#   entry with the Denali DTB and the SP11 arguments and make it the saved default; dracut builds the initramfs;
#   the support RPM's %posttrans (installed next, as one dnf transaction would; skipped when the live root already
#   carries that version, as dnf leaves an installed package out; SUPPORT_PREVIOUS_RPM=<rpm> installs that version
#   first) regenerates the menu.
# Then the way back: `rpm -e` of the new kernel removes its entry and leaves the previous kernel in place.
# Runs in an overlay of the extracted live root with a real ext4 /boot (grub2-editenv cannot work on an overlay
# root) and the grub2 stubs of 35-verify-support-rpm.sh. The live root must carry a *different* kernel-sp11 than
# the RPM under test, so after a full pipeline run (step 50 installs the new kernel there) this step does not
# apply; it is for a kernel built for an existing installation. The first boot itself — the SELinux relabel and
# reboot on a system that ran the AppArmor kernels — needs the hardware; the units and policy it depends on are
# asserted instead.
. "$(dirname "$0")/lib.sh"
require_cmd rpm losetup findmnt lsinitrd grub2-editenv

KRPM=$(rpm_of kernel-sp11)
[ -n "$KRPM" ] || die "no kernel-sp11 RPM in $RPM_DIR (run scripts/20-build-kernel.sh)"
rpm -qpl "$KRPM" | grep -x "/boot/vmlinuz-$KERNEL_ABI" >/dev/null \
  || die "$(basename "$KRPM") is not kernel $KERNEL_ABI (sp11.conf and the RPM disagree)"
SRPM=$(rpm_of sp11-surface-support)
[ -n "$SRPM" ] || die "no sp11-surface-support RPM in $RPM_DIR (run scripts/30-build-support-rpm.sh)"
BASE="$WORK_DIR/iso/rootfs"
as_root test -d "$BASE/usr/lib/modules" \
  || die "no extracted live root at $BASE (run scripts/50-build-iso.sh first, then rerun this step)"
PREV_NVR=$(as_root rpm --root "$BASE" -q kernel-sp11 2>/dev/null | head -1 || true)
[ -n "$PREV_NVR" ] || die "$BASE carries no kernel-sp11 to coexist with"
PREV_ABI=$(as_root rpm --root "$BASE" -ql "$PREV_NVR" | sed -n 's|^/boot/vmlinuz-||p' | head -1 || true)
[ -n "$PREV_ABI" ] && [ "$PREV_ABI" != "$KERNEL_ABI" ] \
  || die "the live root already carries kernel $KERNEL_ABI; this step needs a previous kernel to coexist with"
NEW_NVR=$(basename "$KRPM" .rpm)
MID=0123456789abcdef0123456789abcdef

T="$WORK_DIR/verify-kernel"; M="$T/merged"; LOOP=""
fail=0
check() { if "$@" >/dev/null 2>&1; then log "  ok: $*"; else warn "  FAIL: $*"; fail=1; fi; }
in_root() { as_root chroot "$M" "$@"; }

teardown() {
  for m in dev proc sys; do as_root umount -R "$M/$m" 2>/dev/null || true; done
  as_root umount "$M/boot" 2>/dev/null || true
  [ -n "$LOOP" ] && as_root losetup -d "$LOOP" 2>/dev/null; LOOP=""
  as_root umount "$M" 2>/dev/null || true
  if [ -z "$(mounts_under "$T")" ]; then as_root rm -rf --one-file-system "$T"; else
    warn "mounts left under $T: $(mounts_under "$T" | tr '\n' ' ')"; fi
}
trap teardown EXIT
teardown; trap teardown EXIT

log "--- overlay of the live root ($PREV_NVR installed) with a real ext4 /boot"
mkdir -p "$T"   # owned by the user: the logs below are written by this shell, not by root
as_root mkdir -p "$T"/upper "$T"/work "$M"
as_root mount -t overlay overlay -o "lowerdir=$BASE,upperdir=$T/upper,workdir=$T/work" "$M"
for m in dev proc sys; do as_root mount --rbind "/$m" "$M/$m"; as_root mount --make-rslave "$M/$m"; done
# Two kernels, two initramfs images and the DTB copies: 200M as in step 35 is too small here.
as_root truncate -s 768M "$M/boot.img"
in_root /usr/sbin/mkfs.ext4 -q -F /boot.img || die "mkfs.ext4 in the chroot failed"
as_root cp -a "$M/boot" "$M/boot.orig"
LOOP=$(as_root losetup -f --show "$T/upper/boot.img") || die "losetup failed"
as_root mount "$LOOP" "$M/boot"
as_root cp -a "$M/boot.orig/." "$M/boot/"
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
as_root cp "$KRPM" "$SRPM" "$M/tmp/"

# The state of an installed system before the update: a machine id, Anaconda's /etc/kernel/cmdline (the SP11
# arguments are what the plugin has to add), and a boot entry for the kernel already installed. That entry is
# written with initrd_generator=none: its initramfs is not under test and dracut takes minutes. The cmdline,
# GRUB_CMDLINE_LINUX and /etc/selinux/config carry what an installer that ran without SELinux leaves behind
# (selinux=0, SELINUX=disabled); the plugin's sp11-selinux-restore has to undo that.
echo "$MID" | as_root tee "$M/etc/machine-id" >/dev/null
printf 'root=UUID=0000-test ro rd.luks.uuid=luks-0000-test rhgb quiet selinux=0 clk_ignore_unused pd_ignore_unused\n' \
  | as_root tee "$M/etc/kernel/cmdline" >/dev/null
as_root sed -i '/^GRUB_CMDLINE_LINUX=/d' "$M/etc/default/grub"
echo 'GRUB_CMDLINE_LINUX="rhgb quiet selinux=0"' | as_root tee -a "$M/etc/default/grub" >/dev/null
as_root sed -i 's/^SELINUX=.*/SELINUX=disabled/' "$M/etc/selinux/config"
as_root rm -f "$M/.autorelabel"
as_root mkdir -p "$M/boot/loader/entries" "$M/boot/grub2"
as_root tee "$M/etc/kernel/install.conf" >/dev/null <<<"initrd_generator=none"
# kernel-install exits non-zero in a chroot (95-set-boot-entry.install wants the entry's initramfs, which this
# entry is written without, see docs/pipeline.md) although 20-grub.install has written the entry; the RPM's
# %posttrans ignores the status the same way.
in_root /usr/bin/kernel-install add "$PREV_ABI" "/usr/lib/modules/$PREV_ABI/vmlinuz" >"$T/kernel-install-prev.log" 2>&1 \
  || warn "kernel-install add returned non-zero for the previous kernel (log: $T/kernel-install-prev.log)"
as_root rm -f "$M/etc/kernel/install.conf"
as_root test -s "$M/boot/loader/entries/$MID-$PREV_ABI.conf" \
  || { cat "$T/kernel-install-prev.log" >&2; die "no boot entry for the previous kernel"; }
as_root grep -qw selinux=0 "$M/boot/loader/entries/$MID-$PREV_ABI.conf" || die "the installer's selinux=0 was not staged"

if [ -n "${SUPPORT_PREVIOUS_RPM:-}" ]; then
  # The support version the system runs when the new kernel arrives (the live root carries the one step 50
  # installed), put in place after the previous kernel's entry, as on a system that got it later: a 2.5 or newer
  # %posttrans undoes the installer's SELinux marks at this point, so the kernel's plugin finds nothing to undo.
  [ -f "$SUPPORT_PREVIOUS_RPM" ] || die "no such RPM: $SUPPORT_PREVIOUS_RPM"
  as_root cp "$SUPPORT_PREVIOUS_RPM" "$M/tmp/"
  in_root /usr/bin/rpm -U --oldpackage --replacepkgs --define '_pkgverify_level none' "/tmp/${SUPPORT_PREVIOUS_RPM##*/}" >"$T/rpm-support-prev.log" 2>&1 \
    || { cat "$T/rpm-support-prev.log" >&2; die "rpm -U of ${SUPPORT_PREVIOUS_RPM##*/} failed in the chroot"; }
  log "support RPM installed beforehand: $(in_root /usr/bin/rpm -q sp11-surface-support)"
fi
log "--- rpm -i $NEW_NVR with scriptlets (what dnf install does for an install-only package)"
in_root /usr/bin/rpm -i --define '_pkgverify_level none' "/tmp/${KRPM##*/}" >"$T/rpm-kernel.log" 2>&1 \
  || { cat "$T/rpm-kernel.log" >&2; die "rpm -i of ${KRPM##*/} failed in the chroot"; }
SUPPORT_NVR=$(basename "$SRPM" .rpm)
if [ "$(in_root /usr/bin/rpm -q sp11-surface-support)" = "$SUPPORT_NVR" ]; then
  # rpm refuses a plain -U of an installed NVR, and dnf leaves an installed package out of the transaction.
  log "--- $SUPPORT_NVR is already installed in the live root: skipped, as dnf install ./kernel.rpm ./support.rpm does"
  : >"$T/rpm-support.log"
else
  log "--- rpm -U $SUPPORT_NVR with scriptlets (the support RPM of the same transaction)"
  in_root /usr/bin/rpm -U --define '_pkgverify_level none' "/tmp/${SRPM##*/}" >"$T/rpm-support.log" 2>&1 \
    || { cat "$T/rpm-support.log" >&2; die "rpm -U of ${SRPM##*/} failed in the chroot"; }
fi
sed 's/^/    /' "$T/rpm-kernel.log" "$T/rpm-support.log" >&2

ENTRY="$M/boot/loader/entries/$MID-$KERNEL_ABI.conf"
log "installed set"
check test "$(in_root /usr/bin/rpm -q kernel-sp11 | sort | tr '\n' ' ')" = "$(printf '%s\n' "$PREV_NVR" "$NEW_NVR" | sort | tr '\n' ' ')"
check as_root test -s "$M/boot/vmlinuz-$KERNEL_ABI"
check as_root test -s "$M/boot/System.map-$KERNEL_ABI"
check as_root test -s "$M/boot/config-$KERNEL_ABI"
check as_root test -s "$M/usr/lib/modules/$KERNEL_ABI/modules.dep"
check config_fragment_holds "$FILES_DIR/$KERNEL_CONFIG_FRAGMENT" "$M/usr/lib/modules/$KERNEL_ABI/config"
check test -z "$(find "$M/usr/lib/modules/$KERNEL_ABI/kernel" -path '*/kernel/ubuntu/*' -name '*.ko*')"
log "boot entry for $KERNEL_ABI"
[ -e "$ENTRY" ] && as_root cat "$ENTRY" | sed 's/^/    /' >&2
check as_root test -s "$ENTRY"
check as_root grep -q "^linux /vmlinuz-$KERNEL_ABI" "$ENTRY"
check as_root grep -q "^initrd /initramfs-$KERNEL_ABI.img" "$ENTRY"
check as_root grep -q "^devicetree /dtb-$KERNEL_ABI/$SP11_DTB" "$ENTRY"
check as_root test -s "$M/boot/dtb-$KERNEL_ABI/$SP11_DTB"
for a in $SP11_ARGS_INSTALLED; do check as_root grep -q "^options .*\b$a\b" "$ENTRY"; done
for a in $SP11_ARGS_LIVE_ONLY; do check as_root sh -c "! grep -q '^options .*$a' '$ENTRY'"; done
check as_root grep -q "^saved_entry=$MID-$KERNEL_ABI$" "$M/boot/grub2/grubenv"
check as_root test -s "$M/boot/loader/entries/$MID-$PREV_ABI.conf"
check as_root test -s "$M/boot/vmlinuz-$PREV_ABI"
log "initramfs built by dracut through kernel-install"
check as_root test -s "$M/boot/initramfs-$KERNEL_ABI.img"
if as_root test -s "$M/boot/initramfs-$KERNEL_ABI.img"; then
  as_root lsinitrd "$M/boot/initramfs-$KERNEL_ABI.img" >"$T/lsinitrd.txt" 2>&1 || true
  check grep -q "usr/lib/modules/$KERNEL_ABI/" "$T/lsinitrd.txt"
  check grep -q 'qcom/gen70500_sqe.fw' "$T/lsinitrd.txt"
  # dracut's selinux module is not asserted: its check() returns 255 (included only as a dependency or when
  # added explicitly), the live media's initramfs does not carry it either, and the policy is loaded by systemd
  # in the real root. The module list is logged for the record.
  log "  dracut modules: $(sed -n '/^dracut modules:/,/^====/{/^dracut modules:/d;/^====/d;p}' "$T/lsinitrd.txt" | tr '\n' ' ')"
fi
log "menu regenerated (the support RPM's %posttrans, or 20-grub's sync of /etc/default/grub when it was skipped)"
check as_root grep -q 'blscfg' "$M/boot/grub2/grub.cfg"
check as_root grep -qx "  set gfxmode=$GRUB_GFXMODE_VALUE" "$M/boot/grub2/grub.cfg"
check as_root grep -qx "GRUB_DEVICETREE=\"$SP11_DTB\"" "$M/etc/default/grub"
log "sysctl file on a kernel without the AppArmor key (this host's)"
check in_root /usr/lib/systemd/systemd-sysctl /usr/lib/sysctl.d/90-sp11.conf
check as_root grep -qx -- '-kernel.apparmor_restrict_unprivileged_userns = 0' "$M/usr/lib/sysctl.d/90-sp11.conf"
log "installer's SELinux disable undone by the plugin (selinux=0 and SELINUX=disabled were seeded)"
check as_root sh -c "! grep -qw selinux=0 '$ENTRY'"
check as_root sh -c "! grep -qw selinux=0 '$M/boot/loader/entries/$MID-$PREV_ABI.conf'"
check as_root sh -c "! grep -qw selinux=0 '$M/etc/kernel/cmdline'"
check as_root sh -c "! grep -qw selinux=0 '$M/etc/default/grub'"
check as_root test -e "$M/.autorelabel"
log "what the first SELinux boot depends on"
check as_root grep -qx 'SELINUX=enforcing' "$M/etc/selinux/config"
check as_root grep -qx 'SELINUXTYPE=targeted' "$M/etc/selinux/config"
check as_root sh -c "ls '$M'/etc/selinux/targeted/policy/policy.* >/dev/null"
check as_root test -L "$M/etc/systemd/system/sysinit.target.wants/selinux-autorelabel-mark.service"
check as_root grep -q '^ConditionSecurity=!selinux' "$M/usr/lib/systemd/system/selinux-autorelabel-mark.service"
check as_root test -x "$M/usr/lib/systemd/system-generators/selinux-autorelabel-generator.sh"
check as_root test -x "$M/usr/libexec/selinux/selinux-autorelabel"

log "--- rpm -e $NEW_NVR: the way back to the previous kernel"
in_root /usr/bin/rpm -e "$NEW_NVR" >"$T/rpm-erase.log" 2>&1 || { cat "$T/rpm-erase.log" >&2; die "rpm -e of $NEW_NVR failed"; }
check test "$(in_root /usr/bin/rpm -q kernel-sp11)" = "$PREV_NVR"
check as_root test ! -e "$ENTRY"
check as_root test ! -e "$M/boot/vmlinuz-$KERNEL_ABI"
check as_root test ! -e "$M/boot/dtb-$KERNEL_ABI"
check as_root test ! -e "$M/boot/initramfs-$KERNEL_ABI.img"
check as_root test ! -e "$M/usr/lib/modules/$KERNEL_ABI"
check as_root test -s "$M/boot/loader/entries/$MID-$PREV_ABI.conf"
check as_root test -s "$M/boot/vmlinuz-$PREV_ABI"

teardown; trap - EXIT
[ "$fail" -eq 0 ] || die "kernel install verification failed (see the FAIL lines above)"
log "kernel RPM verified on an installed system next to $PREV_NVR: $NEW_NVR"
