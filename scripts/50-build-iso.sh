#!/usr/bin/bash
# Step 6: remaster the Fedora live ISO (FEDORA_EDITION: Workstation or a spin) for the Surface Pro 11.
#   - extract the LZMA EROFS live root, replace Fedora's stock kernel packages with the SP11 build of the same packages
#     (scripts/20), install sp11-surface-support, sp11-iptsd and the sensors stack (hexagonrpc, libssc,
#     iio-sensor-proxy, sp11-sensors; inert on the live media, see below)
#   - generate a dracut-live initramfs for the SP11 kernel
#   - repack the root as LZMA EROFS with SELinux labels; Fedora's own live GRUB menu gains the Denali OLED DTB, the
#     kernel arguments and the large console font
#   - replay the source ISO's hybrid GPT/El Torito boot layout with xorriso and implant the media-check checksum
# Needs sudo (ownership/xattrs in the extracted root, chroot for dracut).
. "$(dirname "$0")/lib.sh"
require_cmd xorriso fsck.erofs mkfs.erofs dump.erofs blkid rpm depmod lsinitrd fdtget sha256sum implantisomd5 checkisomd5
load_hardware

ISO="$CACHE_DIR/$FEDORA_ISO_NAME"; [ -s "$ISO" ] || die "missing $ISO (run scripts/10-fetch-sources.sh)"
KERNEL_RPMS=()
for n in $KERNEL_PKGS; do
  r=$(rpm_of "$n")
  [ -n "$r" ] && [ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$r")" = "$KERNEL_ABI" ] \
    || die "$n RPM for $KERNEL_ABI missing (run scripts/20-build-kernel.sh)"
  KERNEL_RPMS+=("$r")
done
SRPM=$(rpm_of sp11-surface-support); [ -n "$SRPM" ] || die "sp11-surface-support RPM missing (run scripts/30-build-support-rpm.sh)"
IRPM=$(rpm_of sp11-iptsd);           [ -n "$IRPM" ] || die "sp11-iptsd RPM missing (run scripts/40-build-iptsd-rpm.sh)"
# The sensors stack (scripts/45): inert on the live media, where the ADSP is blacklisted and its FastRPC node never
# appears (nothing starts hexagonrpcd or the online unit, and iio-sensor-proxy without sensors behaves as the stock
# build); active on the installed system from its first boot.
SENSOR_RPMS=()
for n in hexagonrpc libssc iio-sensor-proxy sp11-sensors; do
  r=$(rpm_of "$n"); [ -n "$r" ] || die "$n RPM missing (run scripts/75-export-sensor-registry.sh once, then scripts/45-build-sensors-rpms.sh)"
  SENSOR_RPMS+=("$r")
done
[ "$SP11_DTB_SELECTED" = "$SP11_DTB" ] || die "hardware.env selects DTB $SP11_DTB_SELECTED, config expects $SP11_DTB"

W="$WORK_DIR/iso"; ROOTFS="$W/rootfs"; OUT="$OUT_DIR/$OUTPUT_ISO_NAME"
# User-visible name of the base media ("Xfce 44", "Workstation 45 Beta"): pre-release composes carry an
# underscore (45_Beta) that reads badly in a boot menu, and the ISO's README says plainly when the media is
# not a supported Fedora release.
MEDIA_LABEL="$FEDORA_EDITION ${FEDORA_MEDIA_VERSION/_/ }"
case "$FEDORA_TARGET" in
  ga) MEDIA_NOTE="Fedora $MEDIA_LABEL, compose $FEDORA_COMPOSE" ;;
  *)  MEDIA_NOTE="Fedora $MEDIA_LABEL, compose $FEDORA_COMPOSE - PRE-RELEASE media, not a supported Fedora release" ;;
esac
# The hardware notes in the ISO's README were verified with the Workstation image; a spin shares the kernel,
# firmware and RPMs but not that test history, and its README says so.
case "$FEDORA_EDITION" in
  Workstation) EDITION_NOTE="Fedora Workstation (GNOME)" ;;
  *)           EDITION_NOTE="Fedora $FEDORA_EDITION spin; the hardware notes below were verified with the Workstation image" ;;
esac
mkdir -p "$W"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date -u +%s)}"

## 1. Inspect the source media (paths are read from the ISO, not assumed)
# Every substitution below ends in `|| true` so that, under pipefail, a non-matching grep reaches the
# diagnostic `die` lines.
VOLID=$(xorriso -indev "$ISO" -pvd_info 2>/dev/null | sed -n 's/^Volume Id *: *//p' | head -1 || true)
[ -n "$VOLID" ] || die "cannot read the ISO volume id"
xorriso -osirrox on -indev "$ISO" -extract /EFI/BOOT/grub.cfg "$W/esp-grub.cfg" -extract /boot/grub2/grub.cfg "$W/src-grub.cfg" >/dev/null 2>&1 \
  || die "source ISO lacks /EFI/BOOT/grub.cfg or /boot/grub2/grub.cfg"
MARKER=$(sed -n 's/^search --file --set=root \([^ ]*\).*/\1/p' "$W/esp-grub.cfg" | head -1)
KERNEL_ISO=$(grep -m1 -oE 'linux \(\$root\)[^ ]+' "$W/src-grub.cfg" | sed 's/linux (\$root)//' || true)
INITRD_ISO=$(grep -m1 -oE 'initrd \(\$root\)[^ ]+' "$W/src-grub.cfg" | sed 's/initrd (\$root)//' || true)
LIVEOS_ISO=$(xorriso -indev "$ISO" -find /LiveOS -type f 2>/dev/null | grep -v '^xorriso' | tr -d "'" | head -1 || true)
FONT_ISO=$(xorriso -indev "$ISO" -find / -name unicode.pf2 2>/dev/null | grep -v '^xorriso' | tr -d "'" | head -1 || true)
grep -q "root=live:CDLABEL=$VOLID" "$W/src-grub.cfg" || die "source grub.cfg does not use CDLABEL=$VOLID"
[ -n "$MARKER" ] && [ -n "$KERNEL_ISO" ] && [ -n "$INITRD_ISO" ] && [ -n "$LIVEOS_ISO" ] || die "could not parse the source ISO layout"
log "source: volid=$VOLID marker=$MARKER kernel=$KERNEL_ISO initrd=$INITRD_ISO liveos=$LIVEOS_ISO font=${FONT_ISO:-none}"
LOADER_DIR=$(dirname "$KERNEL_ISO")
DTB_ISO="$LOADER_DIR/dtb/$SP11_DTB"
FONT_SP11_ISO="$LOADER_DIR/grub2/fonts/$GRUB_FONT_FILE"

# The extracted live image is cached between runs, so the cache has to be keyed to the ISO it came from:
# on a release or compose change an unkeyed cache silently remasters the *previous* media. The stamp
# records which ISO produced the file.
LIVE_STAMP="$W/live.erofs.source"
if [ ! -s "$W/live.erofs" ] || [ "${FORCE:-0}" = 1 ] || [ "$(cat "$LIVE_STAMP" 2>/dev/null || true)" != "$FEDORA_ISO_NAME" ]; then
  log "extracting the live root image from $FEDORA_ISO_NAME"
  rm -f "$W/live.erofs" "$LIVE_STAMP"
  xorriso -osirrox on -indev "$ISO" -extract "$LIVEOS_ISO" "$W/live.erofs" >/dev/null 2>&1 || die "xorriso extraction failed"
  printf '%s\n' "$FEDORA_ISO_NAME" > "$LIVE_STAMP"
fi
[ "$(as_root blkid -p -s TYPE -o value "$W/live.erofs")" = erofs ] || die "$LIVEOS_ISO is not an EROFS image"
GRUBEFI="$W/grubaa64.efi"
xorriso -osirrox on -indev "$ISO" -extract /EFI/BOOT/grubaa64.efi "$GRUBEFI" >/dev/null 2>&1 || die "cannot extract /EFI/BOOT/grubaa64.efi"
strings "$GRUBEFI" | grep -x devicetree >/dev/null || die "the ISO's GRUB lacks the devicetree command"
strings "$GRUBEFI" | grep -x gfxterm >/dev/null || warn "the ISO's GRUB lacks gfxterm; the graphical menu and its console font are unavailable"

## 2. Extract the live root (always fresh: the result must depend only on the inputs)
log "extracting EROFS live root to $ROOTFS (this takes a few minutes)"
# An interrupted run can leave /dev, /proc, /sys, /run rbind-mounted below the root; never rm through them.
[ -z "$(mounts_under "$ROOTFS")" ] || die "mounts left under $ROOTFS from an earlier run; unmount them first: $(mounts_under "$ROOTFS" | tr '\n' ' ')"
as_root rm -rf --one-file-system "$ROOTFS"
as_root fsck.erofs --extract="$ROOTFS" --xattrs --preserve "$W/live.erofs" >"$W/fsck-erofs.log" 2>&1 || { tail -5 "$W/fsck-erofs.log" >&2; die "fsck.erofs extraction failed"; }
[ -d "$ROOTFS/usr/lib/modules" ] || die "extracted root looks wrong"
# Defence in depth behind the stamp above: an extracted root from the wrong release would otherwise only
# surface later as a confusing dependency failure while installing the runtime RPMs.
ROOT_RELEASE=$(as_root sed -n 's/^VERSION_ID=//p' "$ROOTFS/etc/os-release" | tr -d '"' || true)
[ "$ROOT_RELEASE" = "$FEDORA_RELEASE" ] \
  || die "live root is Fedora $ROOT_RELEASE but this build targets Fedora $FEDORA_RELEASE (stale $W/live.erofs?)"
log "live root: Fedora $ROOT_RELEASE"

## 3. Install runtime dependencies the live media lacks, then the SP11 RPMs. Dependencies are checked
##    (no --nodeps): a missing library would leave e.g. iptsd unable to start on the installed system.
##    Scriptlets are skipped; their effects are applied explicitly below.
DEP_RPMS=()
# By capability, not name (step 46's rule): Fedora 45 ships protobuf-c's library as protobuf3-c, which provides it.
for pkg in $LIVE_EXTRA_PKGS $SENSORS_DEPS_PKGS; do
  if as_root rpm --root "$ROOTFS" -q --whatprovides "$pkg" >/dev/null 2>&1; then continue; fi
  f=$(ls -t "$CACHE_DIR/rpm-deps/f$FEDORA_RELEASE/$pkg"-[0-9]*.rpm 2>/dev/null | head -1 || true)
  [ -n "$f" ] || die "missing dependency RPM for $pkg (run scripts/10-fetch-sources.sh)"
  DEP_RPMS+=("$f")
done
if [ ${#DEP_RPMS[@]} -gt 0 ]; then
  log "installing runtime dependencies into the live root: $(printf '%s ' "${DEP_RPMS[@]##*/}")"
  as_root rpm --root "$ROOTFS" -Uvh --noscripts --replacepkgs "${DEP_RPMS[@]}" >"$W/rpm-deps.log" 2>&1 \
    || { cat "$W/rpm-deps.log" >&2; die "dependency RPM install into live root failed"; }
fi
## 4. Fedora's stock kernel packages go first: the SP11 kernel is the same package family (kernel, kernel-core,
##    kernel-modules*), and Anaconda installs every kernel that has a /boot/vmlinuz-*. rpm -e refuses if anything else
##    still needs them; kernel-tools*, kernel-headers and kernel-devel stay, they own nothing in /boot.
# shellcheck disable=SC2086 # KERNEL_STOCK_PKGS is a list of names and globs for rpm
mapfile -t STOCK_PKGS < <(as_root rpm --root "$ROOTFS" -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' $KERNEL_STOCK_PKGS | sort -u)
if [ ${#STOCK_PKGS[@]} -gt 0 ]; then
  log "removing stock kernel packages: ${STOCK_PKGS[*]}"
  as_root rpm --root "$ROOTFS" -e --noscripts "${STOCK_PKGS[@]}" >"$W/rpm-erase.log" 2>&1 \
    || { cat "$W/rpm-erase.log" >&2; die "stock kernel removal failed"; }
fi
log "installing the SP11 kernel and RPMs into the live root"
as_root rpm --root "$ROOTFS" -U --test --replacepkgs "${KERNEL_RPMS[@]}" "$SRPM" "$IRPM" "${SENSOR_RPMS[@]}" >"$W/rpm-test.log" 2>&1 \
  || { cat "$W/rpm-test.log" >&2; die "SP11 RPMs have unmet dependencies in the live root (add the package to LIVE_EXTRA_PKGS or SENSORS_DEPS_PKGS)"; }
as_root rpm --root "$ROOTFS" -Uvh --noscripts --replacefiles --replacepkgs "${KERNEL_RPMS[@]}" "$SRPM" "$IRPM" "${SENSOR_RPMS[@]}" >"$W/rpm-install.log" 2>&1 \
  || { cat "$W/rpm-install.log" >&2; die "rpm install into live root failed"; }
# shellcheck disable=SC2086
as_root rpm --root "$ROOTFS" -q $KERNEL_PKGS sp11-surface-support sp11-iptsd hexagonrpc libssc iio-sensor-proxy sp11-sensors >/dev/null \
  || die "RPMs not registered in the live root database"
as_root chroot "$ROOTFS" /usr/libexec/sp11/sp11-ucm-apply || die "UCM matcher install failed"
for bin in /usr/libexec/sp11-iptsd /usr/libexec/sp11-iptsd-check-device; do
  as_root chroot "$ROOTFS" "$bin" --help >/dev/null 2>&1 || die "$bin cannot run in the live root (missing shared library?)"
done
as_root depmod -b "$ROOTFS" "$KERNEL_ABI" || die "depmod in live root failed"
# kernel-core's %posttrans (kernel-install, skipped by --noscripts) copies the image and its HMAC to /boot; the live root
# needs /boot/vmlinuz-<version>, which is how Anaconda finds the kernel it installs.
MODDIR="/usr/lib/modules/$KERNEL_ABI"
as_root install -m 0755 "$ROOTFS$MODDIR/vmlinuz" "$ROOTFS/boot/vmlinuz-$KERNEL_ABI"
if as_root test -f "$ROOTFS$MODDIR/.vmlinuz.hmac"; then
  as_root install -m 0644 "$ROOTFS$MODDIR/.vmlinuz.hmac" "$ROOTFS/boot/.vmlinuz-$KERNEL_ABI.hmac"
fi
[ -s "$ROOTFS/boot/vmlinuz-$KERNEL_ABI" ] || die "kernel image missing from live root"
[ -s "$ROOTFS$MODDIR/dtb/$SP11_DTB" ] || die "DTB missing from live root"

## 5. Only the SP11 kernel in the root. Generated files that no package owns can keep a removed kernel's module tree
##    alive; the source media's boot entries go too.
for d in "$ROOTFS"/usr/lib/modules/*/; do
  v=$(basename "$d"); [ "$v" = "$KERNEL_ABI" ] && continue
  as_root rpm --root "$ROOTFS" -qf "/usr/lib/modules/$v" >/dev/null 2>&1 && die "a package still owns /usr/lib/modules/$v"
  log "removing leftover /usr/lib/modules/$v"
  as_root rm -rf --one-file-system "$d"
done
[ "$(ls "$ROOTFS/usr/lib/modules")" = "$KERNEL_ABI" ] || die "module trees other than $KERNEL_ABI left in the live root"
as_root find "$ROOTFS/boot" -maxdepth 1 \( -name 'vmlinuz-*' -o -name 'initramfs-*' -o -name 'System.map-*' -o -name 'config-*' -o -name 'symvers-*' -o -name '.vmlinuz-*.hmac' \) \
  ! -name "vmlinuz-$KERNEL_ABI" ! -name ".vmlinuz-$KERNEL_ABI.hmac" -exec rm -f {} +
as_root rm -rf "$ROOTFS/boot/dtb"
# These globs have to be expanded by root. /boot/loader/entries is 0700 root-owned, so an unprivileged glob
# matches nothing, leaving the source ISO's BLS entries (its rescue entry and one for the stock kernel) in
# the image while the removal appears to succeed.
as_root find "$ROOTFS/boot" -mindepth 1 -maxdepth 1 -name 'dtb-*' -exec rm -rf {} +
if as_root test -d "$ROOTFS/boot/loader/entries"; then
  as_root find "$ROOTFS/boot/loader/entries" -mindepth 1 -name '*.conf' -delete
  [ -z "$(as_root find "$ROOTFS/boot/loader/entries" -name '*.conf' -print -quit)" ] \
    || die "stale BLS entries left in the live root"
fi
[ "$(as_root find "$ROOTFS/boot" -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n')" = "vmlinuz-$KERNEL_ABI" ] || die "unexpected kernels left in /boot"
as_root rm -f "$ROOTFS/etc/modprobe.d/anaconda-denylist.conf"
as_root tee "$ROOTFS/etc/default/grub" >/dev/null <<GRUB
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_DISABLE_RECOVERY=true
GRUB_CMDLINE_LINUX_DEFAULT="quiet rhgb $SP11_ARGS_INSTALLED"
GRUB_ENABLE_BLSCFG=true
GRUB_TERMINAL_INPUT="console"
GRUB
# Device tree, gfxterm resolution, console font and timeout come from the shipped helper, the same one the
# kernel-install plugin and sp11-first-boot run, so the policy has a single source.
as_root chroot "$ROOTFS" /usr/libexec/sp11/sp11-grub-defaults || die "sp11-grub-defaults failed in the live root"
grep -q "^GRUB_DEVICETREE=\"$SP11_DTB\"" "$ROOTFS/etc/default/grub" || die "GRUB_DEVICETREE not set in the live root"
grep -q "^GRUB_FONT=\"/boot/grub2/fonts/$GRUB_FONT_FILE\"\$" "$ROOTFS/etc/default/grub" || die "GRUB_FONT not set in the live root"
# The live menu loads the same console font from the ISO; take the support RPM's copy rather than running
# grub2-mkfont a second time, so both menus are drawn with one font.
FONT_SP11_SRC="$ROOTFS/usr/share/sp11/fonts/$GRUB_FONT_FILE"
as_root test -s "$FONT_SP11_SRC" || die "support RPM does not ship /usr/share/sp11/fonts/$GRUB_FONT_FILE"
as_root install -m 0644 -o "$(id -u)" -g "$(id -g)" "$FONT_SP11_SRC" "$W/$GRUB_FONT_FILE"
[ "$(dd if="$W/$GRUB_FONT_FILE" bs=1 count=4 skip=8 status=none)" = PFF2 ] || die "$GRUB_FONT_FILE is not a PF2 font"

## 6. dracut-live initramfs for the SP11 kernel, generated inside the live root (same arguments Fedora uses).
##    The support RPM's dracut drop-in pulls the whole Denali firmware set into every initramfs. The installed
##    system needs that (host-only initramfs starts the DSP early); the live media does not (the ADSP driver is
##    blacklisted there), so park the drop-in for this run and install only the GPU zap shader.
# Fedora 45 added two aarch64 dracut modules that both defeat the live-media policy above:
# devicetree-firmware's generic path globs $fw_dir/qcom/x1e80100/*/*/*.mbn|elf, which is exactly the Denali
# set, and qcom-adsp modprobes qcom_q6v5_pas from a pre-udev hook. Omitting them is what keeps the live
# image free of the DSP firmware. multipath is Fedora's own live omission.
LIVE_DRACUT_OMIT="multipath devicetree-firmware qcom-adsp"
DRACUT_DROPIN="$ROOTFS/usr/lib/dracut/dracut.conf.d/90-sp11.conf"
ZAP_FW="/usr/lib/firmware/qcom/x1e80100/microsoft/Denali/qcdxkmsuc8380.mbn"
restore_dropin() { [ -e "$DRACUT_DROPIN.live-off" ] && as_root mv -f "$DRACUT_DROPIN.live-off" "$DRACUT_DROPIN" || true; }
cleanup_mounts() { restore_dropin; for m in run sys proc dev; do as_root umount -R "$ROOTFS/$m" 2>/dev/null || true; done; }
trap cleanup_mounts EXIT
for m in dev proc sys run; do as_root mount --rbind "/$m" "$ROOTFS/$m"; as_root mount --make-rslave "$ROOTFS/$m"; done
# The sensors RPMs' scriptlet effects, skipped by --noscripts: the fastrpc user the units run as (hexagonrpc %pre),
# the policy module for iio-sensor-proxy's QRTR sockets (sp11-sensors %post) and the directory hexagonrpcd serves,
# with the writable registry copy (sp11-sensors %posttrans, tmpfiles). Anaconda's rsync carries all three over.
as_root chroot "$ROOTFS" /usr/bin/systemd-sysusers /usr/lib/sysusers.d/hexagonrpc.conf || die "systemd-sysusers failed for hexagonrpc.conf"
as_root chroot "$ROOTFS" /usr/bin/getent passwd fastrpc >/dev/null || die "no fastrpc user in the live root"
as_root chroot "$ROOTFS" /usr/sbin/semodule -i /usr/share/selinux/packages/sp11-sensors.cil || die "semodule -i sp11-sensors.cil failed in the live root"
as_root chroot "$ROOTFS" /usr/sbin/semodule -l | grep -x sp11-sensors >/dev/null || die "sp11-sensors is not in the live root's policy store"
as_root chroot "$ROOTFS" /usr/bin/systemd-tmpfiles --create /usr/lib/tmpfiles.d/sp11-sensors.conf || die "systemd-tmpfiles failed for sp11-sensors.conf"
[ "$(as_root chroot "$ROOTFS" /usr/bin/stat -c %U /var/lib/sp11/hexagonrpc/sensors/persist/registry/sns_reg_config 2>/dev/null)" = fastrpc ] \
  || die "the registry copy under /var/lib/sp11/hexagonrpc is missing or not owned by fastrpc"
[ -e "$ROOTFS/usr/lib/dracut/modules.d/95sp11-sensors" ] && die "a sensors dracut module is in the live root (sp11-sensors older than 1.3?)"
PROFILE_OPT=""; [ -f "$ROOTFS/.profile" ] && PROFILE_OPT="--install /.profile"
[ -f "$DRACUT_DROPIN" ] || die "missing $DRACUT_DROPIN (support RPM payload changed?)"
[ -s "$ROOTFS$ZAP_FW" ] || die "missing GPU zap shader $ZAP_FW in the live root"
as_root mv -f "$DRACUT_DROPIN" "$DRACUT_DROPIN.live-off"
log "generating live initramfs for $KERNEL_ABI (dracut in chroot)"
as_root rm -f "$ROOTFS/boot/initramfs-$KERNEL_ABI.img"
as_root chroot "$ROOTFS" /usr/bin/dracut --force --reproducible --no-hostonly --no-hostonly-cmdline $PROFILE_OPT \
  --add "dmsquash-live livenet pollcdrom" --omit "$LIVE_DRACUT_OMIT" --install "$ZAP_FW" \
  --kver "$KERNEL_ABI" "/boot/initramfs-$KERNEL_ABI.img" >"$W/dracut.log" 2>&1 || { tail -30 "$W/dracut.log" >&2; die "dracut failed"; }
restore_dropin
[ -f "$DRACUT_DROPIN" ] || die "failed to restore $DRACUT_DROPIN"
as_root test -s "$ROOTFS/boot/initramfs-$KERNEL_ABI.img" || die "initramfs not produced"
as_root install -m 0644 -o "$(id -u)" -g "$(id -g)" "$ROOTFS/boot/initramfs-$KERNEL_ABI.img" "$W/initrd"
lsinitrd -m "$W/initrd" | grep -x dmsquash-live >/dev/null || die "initramfs lacks dmsquash-live"
lsinitrd "$W/initrd" | grep "usr/lib/modules/$KERNEL_ABI/kernel/fs/erofs/erofs.ko" >/dev/null || die "initramfs lacks the erofs module for $KERNEL_ABI"
lsinitrd "$W/initrd" | grep -F "${ZAP_FW#/}" >/dev/null || die "live initramfs lacks the GPU zap shader"
lsinitrd "$W/initrd" | grep -F 'Denali/qcadsp8380.mbn' >/dev/null && die "live initramfs still carries the ADSP firmware"
lsinitrd "$W/initrd" | grep -E 'sp11-sensors|hexagonrpc' >/dev/null && die "live initramfs carries files of the sensors stack"
as_root rm -f "$ROOTFS/boot/initramfs-$KERNEL_ABI.img"
cleanup_mounts; trap - EXIT
[ -z "$(mounts_under "$ROOTFS")" ] || die "mounts still active under $ROOTFS (they would be packed into the image): $(mounts_under "$ROOTFS" | tr '\n' ' ')"
as_root install -m 0644 -o "$(id -u)" -g "$(id -g)" "$ROOTFS/boot/vmlinuz-$KERNEL_ABI" "$W/vmlinuz"
as_root rm -rf "$W/dtb"; as_root install -D -m 0644 -o "$(id -u)" -g "$(id -g)" "$ROOTFS/usr/lib/modules/$KERNEL_ABI/dtb/$SP11_DTB" "$W/dtb/$SP11_DTB"
[[ $(fdtget -t s "$W/dtb/$SP11_DTB" / compatible) == *microsoft,denali-oled* ]] || die "DTB compatible check failed"
log "live initramfs: $(du -h "$W/initrd" | cut -f1), kernel: $(du -h "$W/vmlinuz" | cut -f1)"

## 7. Repack the live root as LZMA EROFS with SELinux labels from the root's own file_contexts.
##    Fedora's image also uses dedupe, but erofs-utils compresses single-threaded with -Ededupe (hours here);
##    fragments + big pclusters with all cores keeps the image within a few percent of the original size.
CONTEXTS="$ROOTFS/etc/selinux/targeted/contexts/files/file_contexts"; [ -s "$CONTEXTS" ] || die "missing $CONTEXTS"
log "repacking live root as LZMA EROFS (workers: $(nproc))"
rm -f "$W/remastered.erofs"
# -T alone implies --all-time (erofs-utils 1.9.4): every file would carry the build time, Anaconda's rsync -t would
# copy that onto the installed system, and Fedora's timestamp-checked Python bytecode would be stale everywhere
# (the images built up to 2026-09-21 have this). --mkfs-time stamps the superblock only; the files keep the times
# the extracted root preserved and rpm set.
as_root mkfs.erofs -zlzma,level=6 -C1048576 -Efragments --workers="$(nproc)" -T "$SOURCE_DATE_EPOCH" --mkfs-time \
  --file-contexts="$CONTEXTS" "$W/remastered.erofs" "$ROOTFS" >"$W/mkfs-erofs.log" 2>&1 || { tail -10 "$W/mkfs-erofs.log" >&2; die "mkfs.erofs failed"; }
as_root chown "$(id -u):$(id -g)" "$W/remastered.erofs"
dump.erofs -s "$W/remastered.erofs" | grep 'compr_algs: *lzma' >/dev/null || die "remastered image is not LZMA-compressed"
# A file the remaster never touches must keep its time from the source image.
erofs_mtime() { dump.erofs --path=/usr/lib/os-release "$1" 2>/dev/null | sed -n 's/^Timestamp: *//p' | head -1 || true; }
[ -n "$(erofs_mtime "$W/live.erofs")" ] && [ "$(erofs_mtime "$W/remastered.erofs")" = "$(erofs_mtime "$W/live.erofs")" ] \
  || die "file times did not survive the repack: /usr/lib/os-release is '$(erofs_mtime "$W/remastered.erofs")' in the remastered image, '$(erofs_mtime "$W/live.erofs")' in the source"
log "remastered root: $(du -h "$W/remastered.erofs" | cut -f1)"

## 8. GRUB menu: Fedora's own live menu from the source ISO, plus what the Surface Pro 11 needs in every entry (the
##    Denali OLED device tree, the kernel arguments) and GRUB at the panel's native mode with the large console font.
##    Entries, labels, timeout and default stay Fedora's; a layout this transformation does not recognise stops the
##    build instead of producing a menu without the device tree.
SNIPPET="$W/grub-sp11.cfg"
{
  printf '%s\n' '# Surface Pro 11 (added by the SP11 build): the Denali OLED device tree and the kernel arguments for every' \
    "# entry, and GRUB at the panel's native mode with a large console font (Fedora's font at a low mode as fallback)."
  printf 'set sp11_dtb="($root)%s"\n' "$DTB_ISO"
  printf 'set sp11_args="%s %s"\n' "$SP11_ARGS_INSTALLED" "$SP11_ARGS_LIVE_ONLY"
  printf 'if loadfont ($root)%s; then\n\tset gfxmode=%s\n\tload_video\n\tinsmod gfxterm\n\tterminal_output gfxterm\n' \
    "$FONT_SP11_ISO" "$GRUB_GFXMODE_VALUE"
  [ -z "$FONT_ISO" ] || printf 'elif loadfont ($root)%s; then\n\tset gfxmode=%s\n\tload_video\n\tinsmod gfxterm\n\tterminal_output gfxterm\n' \
    "$FONT_ISO" "$GRUB_GFXMODE_FALLBACK_VALUE"
  printf 'else\n\tterminal_output console\nfi\n'
} > "$SNIPPET"
awk -v snip="$SNIPPET" '
  /^terminal_output console$/ { dropped++; next }
  /^search --file --set=root / { print; while ((getline l < snip) > 0) print l; searched++; next }
  /^[ \t]*linux[ \t]/ { print $0 " $sp11_args"; kernels++; next }
  /^[ \t]*initrd[ \t]/ { print; match($0, /^[ \t]*/); print substr($0, 1, RLENGTH) "devicetree $sp11_dtb"; initrds++; next }
  { print }
  END { if (dropped != 1 || searched != 1 || kernels < 1 || kernels != initrds) exit 1 }
' "$W/src-grub.cfg" > "$W/grub.cfg" \
  || die "Fedora's live grub.cfg has an unexpected layout (see $W/src-grub.cfg); review the menu transformation in step 50"
[ "$(grep -c 'devicetree \$sp11_dtb$' "$W/grub.cfg")" = "$(grep -c '^[[:space:]]*menuentry ' "$W/grub.cfg")" ] \
  || die "not every live menu entry loads the device tree"
log "live menu: Fedora's $(grep -c '^[[:space:]]*menuentry ' "$W/grub.cfg") entries with the Denali DTB, the SP11 arguments and the console font"

## 9. /sp11 payload: the RPMs the media carries, and a note
rm -rf "$W/sp11"; mkdir -p "$W/sp11/rpms"; cp "${KERNEL_RPMS[@]}" "$SRPM" "$IRPM" "${SENSOR_RPMS[@]}" "$W/sp11/rpms/"
render "$PAYLOAD_DIR/README-iso.txt.in" "$W/sp11/README.txt" RELEASE="$MEDIA_LABEL" ABI="$KERNEL_ABI" \
  KERNEL="Fedora ${KERNEL_SRPM%.src.rpm} + SP11 revision $KERNEL_SP11_REV ($KERNEL_PATCH_BASE + ${KERNEL_PATCH_COMMIT:0:12})" \
  DTB="$SP11_DTB" DATE="$(date -u +%FT%TZ)" SKU="$SP11_SKU" MEDIA="$MEDIA_NOTE" \
  EDITION="$FEDORA_EDITION" EDITION_NOTE="$EDITION_NOTE"

## 10. Assemble the ISO by replaying the source boot layout (GPT, El Torito, appended ESP), then implant the
##     checksum Fedora's media check ("Test this media", the live menu's default entry) verifies; xorriso does not
##     carry the source image's over.
log "writing $OUT"
rm -f "$OUT" "$OUT.sha256"
xorriso -indev "$ISO" -outdev "$OUT" -boot_image any replay -volid "$VOLID" \
  -map "$W/remastered.erofs" "$LIVEOS_ISO" \
  -map "$W/vmlinuz" "$KERNEL_ISO" -map "$W/initrd" "$INITRD_ISO" \
  -map "$W/dtb" "$LOADER_DIR/dtb" -map "$W/grub.cfg" /boot/grub2/grub.cfg -map "$W/sp11" /sp11 \
  -map "$W/$GRUB_FONT_FILE" "$FONT_SP11_ISO" \
  -commit >"$W/xorriso.log" 2>&1 || { tail -20 "$W/xorriso.log" >&2; die "xorriso failed"; }
implantisomd5 --force "$OUT" >"$W/implantisomd5.log" 2>&1 || { cat "$W/implantisomd5.log" >&2; die "implantisomd5 failed"; }

## 11. Validate the result
[ "$(xorriso -indev "$OUT" -pvd_info 2>/dev/null | sed -n 's/^Volume Id *: *//p' | head -1)" = "$VOLID" ] || die "output volume id changed"
REPORT=$(xorriso -indev "$OUT" -report_el_torito plain -report_system_area plain 2>/dev/null)
grep -Eq 'El Torito boot img +: +1 +UEFI' <<<"$REPORT" || die "output has no UEFI El Torito boot image"
grep -Eq 'GPT type GUID +: +2 +28732ac11ff8d211ba4b00a0c93ec93b' <<<"$REPORT" || die "output lacks the appended EFI system partition"
xorriso -osirrox on -indev "$OUT" -extract /boot/grub2/grub.cfg "$W/out-grub.cfg" -extract "$DTB_ISO" "$W/out.dtb" -extract "$FONT_SP11_ISO" "$W/out-font.pf2" >/dev/null 2>&1 || die "output lacks grub.cfg, the DTB or the console font"
cmp -s "$W/grub.cfg" "$W/out-grub.cfg" || die "grub.cfg in output differs"
cmp -s "$W/dtb/$SP11_DTB" "$W/out.dtb" || die "DTB in output differs"
cmp -s "$W/$GRUB_FONT_FILE" "$W/out-font.pf2" || die "console font in output differs"
checkisomd5 "$OUT" >"$W/checkisomd5.log" 2>&1 || { cat "$W/checkisomd5.log" >&2; die "the implanted media checksum does not verify"; }
( cd "$OUT_DIR" && sha256sum "$OUTPUT_ISO_NAME" > "$OUTPUT_ISO_NAME.sha256" )
log "ISO ready: $OUT ($(du -h "$OUT" | cut -f1))"
log "sha256: $(cut -d' ' -f1 "$OUT.sha256")"
