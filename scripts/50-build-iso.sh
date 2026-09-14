#!/usr/bin/bash
# Step 6: remaster the Fedora Workstation Live ISO for the Surface Pro 11.
#   - extract the LZMA EROFS live root, install the kernel-sp11 / sp11-surface-support / sp11-iptsd RPMs
#   - hide the stock kernel from Anaconda, generate a dracut-live initramfs for the SP11 kernel
#   - repack the root as LZMA EROFS with SELinux labels, write a GRUB menu that loads the Denali OLED DTB
#   - replay the source ISO's hybrid GPT/El Torito boot layout with xorriso
# Needs sudo (ownership/xattrs in the extracted root, chroot for dracut).
. "$(dirname "$0")/lib.sh"
require_cmd xorriso fsck.erofs mkfs.erofs dump.erofs blkid rpm depmod lsinitrd fdtget sha256sum
load_hardware

ISO="$CACHE_DIR/$FEDORA_ISO_NAME"; [ -s "$ISO" ] || die "missing $ISO (run scripts/10-fetch-sources.sh)"
KRPM=$(rpm_of kernel-sp11);          [ -n "$KRPM" ] || die "kernel-sp11 RPM missing (run scripts/20-build-kernel.sh)"
SRPM=$(rpm_of sp11-surface-support); [ -n "$SRPM" ] || die "sp11-surface-support RPM missing (run scripts/30-build-support-rpm.sh)"
IRPM=$(rpm_of sp11-iptsd);           [ -n "$IRPM" ] || die "sp11-iptsd RPM missing (run scripts/40-build-iptsd-rpm.sh)"
[ "$SP11_DTB_SELECTED" = "$SP11_DTB" ] || die "hardware.env selects DTB $SP11_DTB_SELECTED, config expects $SP11_DTB"

W="$WORK_DIR/iso"; ROOTFS="$W/rootfs"; OUT="$OUT_DIR/$OUTPUT_ISO_NAME"
mkdir -p "$W"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date -u +%s)}"

## 1. Inspect the source media (paths are read from the ISO, not assumed)
VOLID=$(xorriso -indev "$ISO" -pvd_info 2>/dev/null | sed -n 's/^Volume Id *: *//p' | head -1)
[ -n "$VOLID" ] || die "cannot read the ISO volume id"
xorriso -osirrox on -indev "$ISO" -extract /EFI/BOOT/grub.cfg "$W/esp-grub.cfg" -extract /boot/grub2/grub.cfg "$W/src-grub.cfg" >/dev/null 2>&1 \
  || die "source ISO lacks /EFI/BOOT/grub.cfg or /boot/grub2/grub.cfg"
MARKER=$(sed -n 's/^search --file --set=root \([^ ]*\).*/\1/p' "$W/esp-grub.cfg" | head -1)
KERNEL_ISO=$(grep -m1 -oE 'linux \(\$root\)[^ ]+' "$W/src-grub.cfg" | sed 's/linux (\$root)//')
INITRD_ISO=$(grep -m1 -oE 'initrd \(\$root\)[^ ]+' "$W/src-grub.cfg" | sed 's/initrd (\$root)//')
LIVEOS_ISO=$(xorriso -indev "$ISO" -find /LiveOS -type f 2>/dev/null | grep -v '^xorriso' | tr -d "'" | head -1)
FONT_ISO=$(xorriso -indev "$ISO" -find / -name unicode.pf2 2>/dev/null | grep -v '^xorriso' | tr -d "'" | head -1)
grep -q "root=live:CDLABEL=$VOLID" "$W/src-grub.cfg" || die "source grub.cfg does not use CDLABEL=$VOLID"
[ -n "$MARKER" ] && [ -n "$KERNEL_ISO" ] && [ -n "$INITRD_ISO" ] && [ -n "$LIVEOS_ISO" ] || die "could not parse the source ISO layout"
log "source: volid=$VOLID marker=$MARKER kernel=$KERNEL_ISO initrd=$INITRD_ISO liveos=$LIVEOS_ISO font=${FONT_ISO:-none}"
LOADER_DIR=$(dirname "$KERNEL_ISO")
DTB_ISO="$LOADER_DIR/dtb/$SP11_DTB"

if [ ! -s "$W/live.erofs" ] || [ "${FORCE:-0}" = 1 ]; then
  log "extracting the live root image from the ISO"
  rm -f "$W/live.erofs"
  xorriso -osirrox on -indev "$ISO" -extract "$LIVEOS_ISO" "$W/live.erofs" >/dev/null 2>&1 || die "xorriso extraction failed"
fi
[ "$(as_root blkid -p -s TYPE -o value "$W/live.erofs")" = erofs ] || die "$LIVEOS_ISO is not an EROFS image"
GRUBEFI="$W/grubaa64.efi"
xorriso -osirrox on -indev "$ISO" -extract /EFI/BOOT/grubaa64.efi "$GRUBEFI" >/dev/null 2>&1 || die "cannot extract /EFI/BOOT/grubaa64.efi"
strings "$GRUBEFI" | grep -x devicetree >/dev/null || die "the ISO's GRUB lacks the devicetree command"
strings "$GRUBEFI" | grep -x gfxterm >/dev/null || warn "the ISO's GRUB lacks gfxterm; low-resolution menu unavailable"

## 2. Extract the live root (always fresh: the result must depend only on the inputs)
log "extracting EROFS live root to $ROOTFS (this takes a few minutes)"
as_root rm -rf "$ROOTFS"
as_root fsck.erofs --extract="$ROOTFS" --xattrs --preserve "$W/live.erofs" >"$W/fsck-erofs.log" 2>&1 || { tail -5 "$W/fsck-erofs.log" >&2; die "fsck.erofs extraction failed"; }
[ -d "$ROOTFS/usr/lib/modules" ] || die "extracted root looks wrong"
STOCK_KVER=$(ls "$ROOTFS/usr/lib/modules" | head -1)
log "stock kernel in live root: $STOCK_KVER"

## 3. Install runtime dependencies Workstation Live lacks, then the SP11 RPMs. Dependencies are checked
##    (no --nodeps): a missing library would leave e.g. iptsd unable to start on the installed system.
##    Scriptlets are skipped; their effects are applied explicitly below.
DEP_RPMS=()
for pkg in $LIVE_EXTRA_PKGS; do
  if as_root rpm --root "$ROOTFS" -q "$pkg" >/dev/null 2>&1; then continue; fi
  f=$(ls -t "$CACHE_DIR/rpm-deps/$pkg"-[0-9]*.rpm 2>/dev/null | head -1 || true)
  [ -n "$f" ] || die "missing dependency RPM for $pkg (run scripts/10-fetch-sources.sh)"
  DEP_RPMS+=("$f")
done
if [ ${#DEP_RPMS[@]} -gt 0 ]; then
  log "installing runtime dependencies into the live root: $(printf '%s ' "${DEP_RPMS[@]##*/}")"
  as_root rpm --root "$ROOTFS" -Uvh --noscripts --replacepkgs "${DEP_RPMS[@]}" >"$W/rpm-deps.log" 2>&1 \
    || { cat "$W/rpm-deps.log" >&2; die "dependency RPM install into live root failed"; }
fi
log "installing SP11 RPMs into the live root"
as_root rpm --root "$ROOTFS" -U --test --replacepkgs "$KRPM" "$SRPM" "$IRPM" >"$W/rpm-test.log" 2>&1 \
  || { cat "$W/rpm-test.log" >&2; die "SP11 RPMs have unmet dependencies in the live root (add the package to LIVE_EXTRA_PKGS)"; }
as_root rpm --root "$ROOTFS" -Uvh --noscripts --replacefiles --replacepkgs "$KRPM" "$SRPM" "$IRPM" >"$W/rpm-install.log" 2>&1 \
  || { cat "$W/rpm-install.log" >&2; die "rpm install into live root failed"; }
as_root rpm --root "$ROOTFS" -q kernel-sp11 sp11-surface-support sp11-iptsd >/dev/null || die "RPMs not registered in the live root database"
as_root chroot "$ROOTFS" /usr/libexec/sp11/sp11-ucm-apply || die "UCM matcher install failed"
for bin in /usr/libexec/sp11-iptsd /usr/libexec/sp11-iptsd-check-device; do
  as_root chroot "$ROOTFS" "$bin" --help >/dev/null 2>&1 || die "$bin cannot run in the live root (missing shared library?)"
done
as_root depmod -b "$ROOTFS" "$KERNEL_ABI" || die "depmod in live root failed"
[ -s "$ROOTFS/boot/vmlinuz-$KERNEL_ABI" ] || die "kernel image missing from live root"
[ -s "$ROOTFS/usr/lib/modules/$KERNEL_ABI/dtb/$SP11_DTB" ] || die "DTB missing from live root"

## 4. Boot policy inside the root: only the SP11 kernel is visible to Anaconda; no stale BLS/rescue state
as_root find "$ROOTFS/boot" -maxdepth 1 \( -name 'vmlinuz-*' -o -name 'initramfs-*' -o -name 'System.map-*' -o -name 'config-*' -o -name 'symvers-*' -o -name '.vmlinuz-*.hmac' \) \
  ! -name "vmlinuz-$KERNEL_ABI" ! -name "System.map-$KERNEL_ABI" ! -name "config-$KERNEL_ABI" -exec rm -f {} +
as_root rm -rf "$ROOTFS/boot/dtb" "$ROOTFS"/boot/dtb-* "$ROOTFS"/boot/loader/entries/*.conf
[ "$(as_root find "$ROOTFS/boot" -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n')" = "vmlinuz-$KERNEL_ABI" ] || die "unexpected kernels left in /boot"
as_root rm -f "$ROOTFS/etc/modprobe.d/anaconda-denylist.conf"
[ -e "$ROOTFS/etc/system-fips" ] && die "live root has /etc/system-fips"
as_root tee "$ROOTFS/etc/default/grub" >/dev/null <<GRUB
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_DISABLE_RECOVERY=true
GRUB_CMDLINE_LINUX_DEFAULT="quiet rhgb $SP11_ARGS_INSTALLED"
GRUB_ENABLE_BLSCFG=true
GRUB_DEVICETREE="$SP11_DTB"
GRUB_GFXMODE=$GRUB_GFXMODE_VALUE
GRUB_TERMINAL_INPUT="console"
GRUB_TERMINAL_OUTPUT="gfxterm"
GRUB_TIMEOUT=$GRUB_TIMEOUT_VALUE
GRUB_TIMEOUT_STYLE=menu
GRUB

## 5. dracut-live initramfs for the SP11 kernel, generated inside the live root (same arguments Fedora uses)
cleanup_mounts() { for m in run sys proc dev; do as_root umount -R "$ROOTFS/$m" 2>/dev/null || true; done; }
trap cleanup_mounts EXIT
for m in dev proc sys run; do as_root mount --rbind "/$m" "$ROOTFS/$m"; as_root mount --make-rslave "$ROOTFS/$m"; done
PROFILE_OPT=""; [ -f "$ROOTFS/.profile" ] && PROFILE_OPT="--install /.profile"
log "generating live initramfs for $KERNEL_ABI (dracut in chroot)"
as_root rm -f "$ROOTFS/boot/initramfs-$KERNEL_ABI.img"
as_root chroot "$ROOTFS" /usr/bin/dracut --force --reproducible --no-hostonly --no-hostonly-cmdline $PROFILE_OPT \
  --add "dmsquash-live livenet pollcdrom" --omit "multipath fips fips-crypto-policies" \
  --kver "$KERNEL_ABI" "/boot/initramfs-$KERNEL_ABI.img" >"$W/dracut.log" 2>&1 || { tail -30 "$W/dracut.log" >&2; die "dracut failed"; }
as_root test -s "$ROOTFS/boot/initramfs-$KERNEL_ABI.img" || die "initramfs not produced"
as_root install -m 0644 -o "$(id -u)" -g "$(id -g)" "$ROOTFS/boot/initramfs-$KERNEL_ABI.img" "$W/initrd"
lsinitrd -m "$W/initrd" | grep -x dmsquash-live >/dev/null || die "initramfs lacks dmsquash-live"
lsinitrd "$W/initrd" | grep "usr/lib/modules/$KERNEL_ABI/kernel/fs/erofs/erofs.ko" >/dev/null || die "initramfs lacks the erofs module for $KERNEL_ABI"
lsinitrd -m "$W/initrd" | grep -x fips >/dev/null && die "initramfs contains the fips module"
as_root rm -f "$ROOTFS/boot/initramfs-$KERNEL_ABI.img"
cleanup_mounts; trap - EXIT
as_root install -m 0644 -o "$(id -u)" -g "$(id -g)" "$ROOTFS/boot/vmlinuz-$KERNEL_ABI" "$W/vmlinuz"
as_root rm -rf "$W/dtb"; as_root install -D -m 0644 -o "$(id -u)" -g "$(id -g)" "$ROOTFS/usr/lib/modules/$KERNEL_ABI/dtb/$SP11_DTB" "$W/dtb/$SP11_DTB"
[[ $(fdtget -t s "$W/dtb/$SP11_DTB" / compatible) == *microsoft,denali-oled* ]] || die "DTB compatible check failed"
log "live initramfs: $(du -h "$W/initrd" | cut -f1), kernel: $(du -h "$W/vmlinuz" | cut -f1)"

## 6. Repack the live root as LZMA EROFS with SELinux labels from the root's own file_contexts.
##    Fedora's image also uses dedupe, but erofs-utils compresses single-threaded with -Ededupe (hours here);
##    fragments + big pclusters with all cores keeps the image within a few percent of the original size.
CONTEXTS="$ROOTFS/etc/selinux/targeted/contexts/files/file_contexts"; [ -s "$CONTEXTS" ] || die "missing $CONTEXTS"
log "repacking live root as LZMA EROFS (workers: $(nproc))"
rm -f "$W/remastered.erofs"
as_root mkfs.erofs -zlzma,level=6 -C1048576 -Efragments --workers="$(nproc)" -T "$SOURCE_DATE_EPOCH" \
  --file-contexts="$CONTEXTS" "$W/remastered.erofs" "$ROOTFS" >"$W/mkfs-erofs.log" 2>&1 || { tail -10 "$W/mkfs-erofs.log" >&2; die "mkfs.erofs failed"; }
as_root chown "$(id -u):$(id -g)" "$W/remastered.erofs"
dump.erofs -s "$W/remastered.erofs" | grep 'compr_algs: *lzma' >/dev/null || die "remastered image is not LZMA-compressed"
log "remastered root: $(du -h "$W/remastered.erofs" | cut -f1)"

## 7. GRUB menu and /sp11 payload
if [ -n "$FONT_ISO" ]; then FONT_LINE="$FONT_ISO"; else FONT_LINE="/nonexistent-font.pf2"; fi
render "$FILES_DIR/grub-live.cfg.in" "$W/grub.cfg" RELEASE="$FEDORA_RELEASE" ABI="$KERNEL_ABI" TIMEOUT="$GRUB_TIMEOUT_VALUE" \
  MARKER="$MARKER" FONT="$FONT_LINE" GFXMODE="$GRUB_GFXMODE_VALUE" VOLID="$VOLID" ARGS_INSTALLED="$SP11_ARGS_INSTALLED" \
  ARGS_LIVE="$SP11_ARGS_LIVE_ONLY" DTB="$DTB_ISO" KERNEL="$KERNEL_ISO" INITRD="$INITRD_ISO"
grep -q 'fips=1' "$W/grub.cfg" && die "grub.cfg enables FIPS"
rm -rf "$W/sp11"; mkdir -p "$W/sp11/rpms"; cp "$KRPM" "$SRPM" "$IRPM" "$W/sp11/rpms/"
render "$FILES_DIR/README-iso.txt.in" "$W/sp11/README.txt" RELEASE="$FEDORA_RELEASE" ABI="$KERNEL_ABI" COMMIT="${KERNEL_SOURCE_COMMIT:0:12}" \
  MODE="$KERNEL_MODE" DTB="$SP11_DTB" DATE="$(date -u +%FT%TZ)" SKU="$SP11_SKU"

## 8. Assemble the ISO by replaying the source boot layout (GPT, El Torito, appended ESP)
log "writing $OUT"
rm -f "$OUT" "$OUT.sha256"
xorriso -indev "$ISO" -outdev "$OUT" -boot_image any replay -volid "$VOLID" \
  -map "$W/remastered.erofs" "$LIVEOS_ISO" \
  -map "$W/vmlinuz" "$KERNEL_ISO" -map "$W/initrd" "$INITRD_ISO" \
  -map "$W/dtb" "$LOADER_DIR/dtb" -map "$W/grub.cfg" /boot/grub2/grub.cfg -map "$W/sp11" /sp11 \
  -commit >"$W/xorriso.log" 2>&1 || { tail -20 "$W/xorriso.log" >&2; die "xorriso failed"; }

## 9. Validate the result
[ "$(xorriso -indev "$OUT" -pvd_info 2>/dev/null | sed -n 's/^Volume Id *: *//p' | head -1)" = "$VOLID" ] || die "output volume id changed"
REPORT=$(xorriso -indev "$OUT" -report_el_torito plain -report_system_area plain 2>/dev/null)
grep -Eq 'El Torito boot img +: +1 +UEFI' <<<"$REPORT" || die "output has no UEFI El Torito boot image"
grep -Eq 'GPT type GUID +: +2 +28732ac11ff8d211ba4b00a0c93ec93b' <<<"$REPORT" || die "output lacks the appended EFI system partition"
xorriso -osirrox on -indev "$OUT" -extract /boot/grub2/grub.cfg "$W/out-grub.cfg" -extract "$DTB_ISO" "$W/out.dtb" >/dev/null 2>&1 || die "output lacks grub.cfg or the DTB"
cmp -s "$W/grub.cfg" "$W/out-grub.cfg" || die "grub.cfg in output differs"
cmp -s "$W/dtb/$SP11_DTB" "$W/out.dtb" || die "DTB in output differs"
( cd "$OUT_DIR" && sha256sum "$OUTPUT_ISO_NAME" > "$OUTPUT_ISO_NAME.sha256" )
log "ISO ready: $OUT ($(du -h "$OUT" | cut -f1))"
log "sha256: $(cut -d' ' -f1 "$OUT.sha256")"
