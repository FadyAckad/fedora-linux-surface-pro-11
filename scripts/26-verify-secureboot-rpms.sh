#!/usr/bin/bash
# Step 2c: prove the Secure Boot add-on of step 25 and the support RPM's sp11-secureboot work together on an
# installed system (docs/secure-boot.md), before either reaches the device: the support RPM, then the kernel
# packages and the add-on in one transaction, as `dnf install` does (the kernel-install plugin copies the signed
# image and the initramfs to the ESP and writes the entries and the menu); a changed initramfs carried over by
# the next sync; the add-on erased and installed on its own; the kernel's removal.
# Runs in an overlay of the extracted live root with a real ext4 /boot, as step 36 does, and a real FAT
# filesystem on /boot/efi (the tool acts only on a mounted ESP). The live root must carry another kernel than
# the one under test. Without an add-on for KERNEL_ABI (no signing key, or step 25 not run) there is nothing
# to verify, and the step says so.
. "$(dirname "$0")/lib.sh"
load_hardware

NAME="sp11-kernel-secureboot-$KERNEL_ABI"
ADDON=$(ls -t "$RPM_DIR/$NAME"-[0-9]*."$FEDORA_ARCH".rpm 2>/dev/null | head -1 || true)
if [ -z "$ADDON" ]; then
  log "no Secure Boot add-on for $KERNEL_ABI in $RPM_DIR (no signing key, or step 25 not run): nothing to verify"
  exit 0
fi
require_cmd rpm losetup findmnt mkfs.vfat blkid sha256sum

KRPMS=()
for n in $KERNEL_PKGS; do
  r=$(rpm_of "$n")
  [ -n "$r" ] && [ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$r")" = "$KERNEL_ABI" ] \
    || die "no $n RPM for $KERNEL_ABI in $RPM_DIR (run scripts/20-build-kernel.sh)"
  KRPMS+=("$r")
done
SRPM=$(rpm_of sp11-surface-support)
[ -n "$SRPM" ] || die "no sp11-surface-support RPM in $RPM_DIR (run scripts/30-build-support-rpm.sh)"
rpm -qpl "$SRPM" | grep -qx /usr/libexec/sp11/sp11-secureboot \
  || die "$(basename "$SRPM") carries no sp11-secureboot (the tool comes with support 3.12)"
BASE="$WORK_DIR/iso/rootfs"
as_root test -d "$BASE/usr/lib/modules" \
  || die "no extracted live root at $BASE (run scripts/50-build-iso.sh first, then rerun this step)"
PREV_NVR=$(as_root rpm --root "$BASE" -q --whatprovides kernel-core-uname-r 2>/dev/null | head -1 || true)
[ -n "$PREV_NVR" ] || die "$BASE carries no kernel to coexist with"
PREV_ABI=$(as_root rpm --root "$BASE" -ql "$PREV_NVR" | sed -n 's|^/usr/lib/modules/\([^/]*\)/vmlinuz$|\1|p; s|^/lib/modules/\([^/]*\)/vmlinuz$|\1|p' | head -1 || true)
[ -n "$PREV_ABI" ] && [ "$PREV_ABI" != "$KERNEL_ABI" ] \
  || die "the live root already carries kernel $KERNEL_ABI; this step needs a previous kernel to coexist with"
NEW_NVRS=(); for r in "${KRPMS[@]}"; do NEW_NVRS+=("$(basename "$r" .rpm)"); done
ADDON_NVR=$(basename "$ADDON" .rpm)
MID=0123456789abcdef0123456789abcdef
ID="k$(printf '%s' "$KERNEL_ABI" | sha256sum | cut -c1-7)"          # the tool's 8.3 name for this kernel's copies
SUB=$SECUREBOOT_ESP_DIR

T="$WORK_DIR/verify-secureboot"; M="$T/merged"; LOOP=""; ELOOP=""
fail=0
check() { if "$@" >/dev/null 2>&1; then log "  ok: $*"; else warn "  FAIL: $*"; fail=1; fi; }
in_root() { as_root chroot "$M" "$@"; }

teardown() {
  for m in dev proc sys; do as_root umount -R "$M/$m" 2>/dev/null || true; done
  as_root umount "$M/boot/efi" 2>/dev/null || true
  [ -n "$ELOOP" ] && as_root losetup -d "$ELOOP" 2>/dev/null; ELOOP=""
  as_root umount "$M/boot" 2>/dev/null || true
  [ -n "$LOOP" ] && as_root losetup -d "$LOOP" 2>/dev/null; LOOP=""
  as_root umount "$M" 2>/dev/null || true
  if [ -z "$(mounts_under "$T")" ]; then as_root rm -rf --one-file-system "$T"; else
    warn "mounts left under $T: $(mounts_under "$T" | tr '\n' ' ')"; fi
}
trap teardown EXIT
teardown; trap teardown EXIT

log "--- overlay of the live root ($PREV_NVR installed) with a real ext4 /boot and a FAT /boot/efi"
mkdir -p "$T"
as_root mkdir -p "$T"/upper "$T"/work "$M"
as_root mount -t overlay overlay -o "lowerdir=$BASE,upperdir=$T/upper,workdir=$T/work" "$M"
for m in dev proc sys; do as_root mount --rbind "/$m" "$M/$m"; as_root mount --make-rslave "$M/$m"; done
as_root truncate -s 768M "$M/boot.img"
in_root /usr/sbin/mkfs.ext4 -q -F /boot.img || die "mkfs.ext4 in the chroot failed"
as_root cp -a "$M/boot" "$M/boot.orig"
LOOP=$(as_root losetup -f --show "$T/upper/boot.img") || die "losetup failed"
as_root mount "$LOOP" "$M/boot"
as_root cp -a "$M/boot.orig/." "$M/boot/"
# The ESP: 384 MiB hold the image and two initramfs sizes with the tool's margin; mounted as Fedora mounts it.
truncate -s 384M "$T/esp.img"
mkfs.vfat -F 32 -n SP11ESP "$T/esp.img" >/dev/null || die "mkfs.vfat failed"
ELOOP=$(as_root losetup -f --show "$T/esp.img") || die "losetup failed for the ESP"
as_root mkdir -p "$M/boot/efi"
as_root mount -o umask=0077,shortname=winnt "$ELOOP" "$M/boot/efi" || die "cannot mount the FAT image on /boot/efi"
as_root mkdir -p "$M/boot/efi/EFI/fedora"
ESP_UUID=$(as_root blkid -s UUID -o value "$ELOOP")
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
as_root cp "${KRPMS[@]}" "$SRPM" "$ADDON" "$M/tmp/"

## 1. An installed system before the update, as in step 36: a machine id, Anaconda's /etc/kernel/cmdline, the
##    previous kernel's boot entry; then the support RPM under test, which brings the tool and the plugin.
echo "$MID" | as_root tee "$M/etc/machine-id" >/dev/null
printf 'root=UUID=0000-test ro rd.luks.uuid=luks-0000-test rhgb quiet clk_ignore_unused pd_ignore_unused\n' \
  | as_root tee "$M/etc/kernel/cmdline" >/dev/null
as_root sed -i '/^GRUB_CMDLINE_LINUX=/d' "$M/etc/default/grub"
echo 'GRUB_CMDLINE_LINUX="rhgb quiet"' | as_root tee -a "$M/etc/default/grub" >/dev/null
as_root mkdir -p "$M/boot/loader/entries" "$M/boot/grub2"
as_root tee "$M/etc/kernel/install.conf" >/dev/null <<<"initrd_generator=none"
in_root /usr/bin/kernel-install add "$PREV_ABI" "/usr/lib/modules/$PREV_ABI/vmlinuz" >"$T/kernel-install-prev.log" 2>&1 \
  || warn "kernel-install add returned non-zero for the previous kernel (log: $T/kernel-install-prev.log)"
as_root rm -f "$M/etc/kernel/install.conf"
as_root test -s "$M/boot/loader/entries/$MID-$PREV_ABI.conf" \
  || { cat "$T/kernel-install-prev.log" >&2; die "no boot entry for the previous kernel"; }
in_root /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 || die "grub2-mkconfig failed while staging the installed system"
log "--- rpm -U $(basename "$SRPM" .rpm) with scriptlets"
if [ "$(in_root /usr/bin/rpm -q sp11-surface-support)" = "$(basename "$SRPM" .rpm)" ]; then
  in_root /usr/bin/rpm -U --replacepkgs --define '_pkgverify_level none' "/tmp/${SRPM##*/}" >"$T/rpm-support.log" 2>&1 \
    || { cat "$T/rpm-support.log" >&2; die "rpm -U --replacepkgs of ${SRPM##*/} failed in the chroot"; }
else
  in_root /usr/bin/rpm -U --define '_pkgverify_level none' "/tmp/${SRPM##*/}" >"$T/rpm-support.log" 2>&1 \
    || { cat "$T/rpm-support.log" >&2; die "rpm -U of ${SRPM##*/} failed in the chroot"; }
fi
log "without a signed boot image: the menu reads the block, the tool has nothing to do"
check as_root grep -qxF 'if [ "${lockdown}" = "y" -a -f ${config_directory}/sp11-secureboot.cfg ]; then' "$M/boot/grub2/grub.cfg"
check as_root test ! -e "$M/boot/grub2/sp11-secureboot.cfg"
check as_root test ! -e "$M/boot/efi/$SUB"

## 2. The kernel and its add-on in one transaction: kernel-core's %posttrans runs kernel-install, whose plugins
##    end with 96-sp11-secureboot.install.
log "--- rpm -i ${NEW_NVRS[*]} $ADDON_NVR with scriptlets, one transaction"
in_root /usr/bin/rpm -i --define '_pkgverify_level none' "${KRPMS[@]/#*\///tmp/}" "/tmp/${ADDON##*/}" >"$T/rpm-kernel.log" 2>&1 \
  || { cat "$T/rpm-kernel.log" >&2; die "rpm -i of the kernel packages and the add-on failed in the chroot"; }
sed 's/^/    /' "$T/rpm-kernel.log" >&2
ENTRY="$M/boot/loader/entries/$MID-$KERNEL_ABI.conf"
CFG="$M/boot/grub2/sp11-secureboot.cfg"
MENU="$M/boot/grub2/sp11-secureboot-menu.cfg"
THEME="$M/boot/grub2/themes/sp11-secureboot"
E="$M/boot/efi/$SUB"
IMAGE="$M/usr/lib/modules/$KERNEL_ABI/sp11-secureboot.efi"
assert_ready() {  # the copies, the entries, the menu and its theme of the kernel under test
  local what=$1 opts
  log "$what: the copies on the ESP, the entries and the menu"
  check as_root cmp -s "$IMAGE" "$E/$ID.efi"
  check as_root cmp -s "$M/boot/initramfs-$KERNEL_ABI.img" "$E/$ID.img"
  check as_root sh -c "[ \"\$(ls '$E' | tr '\n' ' ')\" = '$ID.efi $ID.img ' ]"
  opts=$(as_root sed -n 's/^options[[:space:]]\+//p' "$ENTRY" | head -n 1)
  check as_root grep -qx "  search --no-floppy --fs-uuid --set=sp11esp $ESP_UUID" "$CFG"
  check as_root grep -qxF "  chainloader (\$sp11esp)/$SUB/$ID.efi $opts sp11_initrd=/$SUB/$ID.img" "$CFG"
  check as_root grep -qxF 'set blsdir="/grub2/fonts"' "$CFG"
  check as_root test -d "$M/boot/grub2/fonts"
  # The root has no Windows: the menu holds the signed entry and the firmware entry, each with its image.
  check as_root grep -qF -- "--class sp11-menu-1 --class fedora --class gnu-linux --class gnu --class os --unrestricted --id 'sp11-sb-$KERNEL_ABI' {" "$MENU"
  check as_root grep -qF -- "menuentry 'UEFI Firmware Settings' --class sp11-menu-2 " "$MENU"
  check as_root sh -c "[ \"\$(ls '$THEME/icons' | tr '\n' ' ')\" = 'sp11-menu-1.png sp11-menu-2.png ' ]"
  check in_root /usr/bin/grub2-script-check /boot/grub2/sp11-secureboot.cfg
  check in_root /usr/bin/grub2-script-check /boot/grub2/sp11-secureboot-menu.cfg
  check as_root sh -c "chroot '$M' /usr/libexec/sp11/sp11-secureboot status | grep -qxF 'kernel:         $KERNEL_ABI: ready ($ID.efi, $ID.img)'"
  check as_root sh -c "chroot '$M' /usr/libexec/sp11/sp11-secureboot status | grep -qxF 'menu:           graphical while Secure Boot is on'"
}
assert_gone() {
  local what=$1
  log "$what: no copies, no entries file"
  check as_root test ! -e "$CFG"
  check as_root test ! -e "$MENU"
  check as_root test ! -e "$THEME"
  check as_root test ! -e "$E"
  check as_root test -d "$M/boot/efi/EFI/fedora"
}
for n in "${NEW_NVRS[@]}" "$ADDON_NVR"; do check in_root /usr/bin/rpm -q "$n"; done
[ -e "$ENTRY" ] && as_root cat "$ENTRY" | sed 's/^/    /' >&2
assert_ready "after the install"
as_root cat "$CFG" | sed 's/^/    /' >&2
for a in $SP11_ARGS_INSTALLED; do check as_root grep -q "^  chainloader .*\b$a\b" "$CFG"; done
log "  ESP use of $KERNEL_ABI: $(as_root sh -c "du -csh '$E'/* | tail -1 | cut -f1")"

## 3. What changes without kernel-install, such as a rebuilt initramfs: the unit's next sync carries it over.
log "--- a changed initramfs"
printf 'rebuilt' | as_root tee -a "$M/boot/initramfs-$KERNEL_ABI.img" >/dev/null
check as_root sh -c "chroot '$M' /usr/libexec/sp11/sp11-secureboot status | grep -qF 'NOT current (run sync)'"
check in_root /usr/libexec/sp11/sp11-secureboot sync
assert_ready "after the sync"

## 4. The add-on on its own: erased, its copies and the entry go; installed for a kernel that is already there,
##    its scriptlet brings them back.
log "--- rpm -e $ADDON_NVR, then rpm -i of it alone"
in_root /usr/bin/rpm -e "$ADDON_NVR" >"$T/rpm-addon-erase.log" 2>&1 || { cat "$T/rpm-addon-erase.log" >&2; die "rpm -e of the add-on failed"; }
assert_gone "after the add-on's removal"
check as_root test -s "$ENTRY"
in_root /usr/bin/rpm -i --define '_pkgverify_level none' "/tmp/${ADDON##*/}" >"$T/rpm-addon.log" 2>&1 \
  || { cat "$T/rpm-addon.log" >&2; die "rpm -i of the add-on failed in the chroot"; }
assert_ready "after the add-on's own install"

## 5. The way back: the kernel and its add-on erased together leave nothing behind
log "--- rpm -e ${NEW_NVRS[*]} $ADDON_NVR"
in_root /usr/bin/rpm -e "${NEW_NVRS[@]}" "$ADDON_NVR" >"$T/rpm-erase.log" 2>&1 || { cat "$T/rpm-erase.log" >&2; die "rpm -e of the kernel packages and the add-on failed"; }
assert_gone "after the kernel's removal"
check as_root test ! -e "$ENTRY"
check as_root test ! -e "$M/usr/lib/modules/$KERNEL_ABI"
check as_root test -s "$M/boot/loader/entries/$MID-$PREV_ABI.conf"
check in_root /usr/bin/rpm -q "$PREV_NVR"

teardown; trap - EXIT
[ "$fail" -eq 0 ] || die "Secure Boot add-on verification failed (see the FAIL lines above)"
log "Secure Boot add-on verified with $(basename "$SRPM" .rpm) on an installed system: $ADDON_NVR"
