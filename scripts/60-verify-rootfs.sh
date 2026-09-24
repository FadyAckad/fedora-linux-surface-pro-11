#!/usr/bin/bash
# Optional step: verify the remastered live root left behind by scripts/50-build-iso.sh, and simulate the
# installed-system kernel-install hand-off in a chroot, with the inputs Anaconda leaves at that point, to prove the
# BLS entry receives the Denali DTB and the SP11 kernel arguments.
. "$(dirname "$0")/lib.sh"
require_cmd dtc lsinitrd
load_hardware
ROOTFS="$WORK_DIR/iso/rootfs"; [ -d "$ROOTFS/usr/lib/modules/$KERNEL_ABI" ] || die "no remastered root at $ROOTFS (run scripts/50-build-iso.sh)"
fail=0; check() { if "$@"; then log "ok: ${*: -1}"; else warn "FAIL: ${*: -1}"; fail=1; fi; }
r() { as_root "$@"; }

log "--- live root contents"
check r test -s "$ROOTFS/boot/vmlinuz-$KERNEL_ABI"
check r test -s "$ROOTFS/usr/lib/modules/$KERNEL_ABI/vmlinuz"
check r test -s "$ROOTFS/usr/lib/modules/$KERNEL_ABI/dtb/$SP11_DTB"
check r test -s "$ROOTFS/usr/lib/modules/$KERNEL_ABI/modules.dep"
check r test ! -e "$ROOTFS/etc/system-fips"
# The Denali firmware directory holds exactly the files the device tree requests.
dt_fw=$(dtc -I dtb -O dts "$ROOTFS/usr/lib/modules/$KERNEL_ABI/dtb/$SP11_DTB" 2>/dev/null \
  | grep -o 'qcom/x1e80100/microsoft/Denali/[^"]*' | sort -u | tr '\n' ' ' || true)
pkg_fw=$(cd "$ROOTFS/usr/lib/firmware" && find qcom/x1e80100/microsoft/Denali -type f | sort | tr '\n' ' ')
check test -n "$dt_fw"
check test "$pkg_fw" = "$dt_fw"
check r test -s "$ROOTFS/usr/lib/firmware/qcom/x1e80100/X1E80100-Microsoft-Surface-Pro-11-tplg.bin"
check r test -s "$ROOTFS/usr/lib/firmware/ath12k/WCN7850/hw2.0/board.bin"
check r test -f "$ROOTFS/usr/share/alsa/ucm2/conf.d/x1e80100/x1e80100.conf"
check r grep -qF "Regex \"$UCM_SP11_REGEX\"" "$ROOTFS/usr/share/alsa/ucm2/conf.d/x1e80100/x1e80100.conf"
# The microphone gain step 30 inserts into ooaklee's Mic device (UCM_MIC_GAIN).
hifi="$ROOTFS/usr/share/alsa/ucm2/Qualcomm/x1e80100/SP11-HiFi.conf"
for d in 0 1; do check r grep -qE "^[[:space:]]*cset \"name='TX_DEC$d Volume' $UCM_MIC_GAIN\"\$" "$hifi"; done
check r test -x "$ROOTFS/usr/libexec/sp11-iptsd"
check r test -x "$ROOTFS/usr/libexec/sp11/sp11-bt-set-addr"
check r grep -q "SP11_BT_MAC=\"$SP11_BT_MAC\"" "$ROOTFS/etc/sp11/bluetooth-address"
check r test -x "$ROOTFS/usr/lib/kernel/install.d/15-sp11-surface.install"
check r test -x "$ROOTFS/etc/grub.d/29_sp11_windows"
check r test -f "$ROOTFS/usr/lib/grub/arm64-efi/chain.mod"
check r test -s "$ROOTFS/usr/share/sp11/fonts/$GRUB_FONT_FILE"
# GRUB cannot read the font from /usr on a LUKS install; Anaconda rsyncs /boot/grub2 to the target.
check r test -s "$ROOTFS/boot/grub2/fonts/$GRUB_FONT_FILE"
check r sh -c "[ \"\$(dd if='$ROOTFS/usr/share/sp11/fonts/$GRUB_FONT_FILE' bs=1 count=4 skip=8 status=none)\" = PFF2 ]"
# The shipped kernel is Fedora's configuration plus kernel-local (step 20 compares the whole configuration).
check config_fragment_holds "$PAYLOAD_DIR/$KERNEL_CONFIG_FRAGMENT" "$ROOTFS/usr/lib/modules/$KERNEL_ABI/config"
check r grep -qx 'scmi-cpufreq' "$ROOTFS/usr/lib/modules-load.d/sp11-scmi-cpufreq.conf"
check r test -L "$ROOTFS/usr/lib/systemd/system/multi-user.target.wants/sp11-first-boot.service"
check r test ! -e "$ROOTFS/etc/modprobe.d/anaconda-denylist.conf"
stock=$(r find "$ROOTFS/boot" -maxdepth 1 -name 'vmlinuz-*' ! -name "vmlinuz-$KERNEL_ABI" | wc -l); check test "$stock" -eq 0
bls=$(r find "$ROOTFS/boot/loader/entries" -name '*.conf' 2>/dev/null | wc -l); check test "$bls" -eq 0
check r grep -q '^excludepkgs=kernel,.*kernel-uki-\*$' "$ROOTFS/usr/share/dnf5/repos.override.d/90-sp11-kernel.repo"
check r test ! -e "$ROOTFS/etc/dnf/libdnf5.conf.d/90-sp11.conf"
# shellcheck disable=SC2086
check r rpm --root "$ROOTFS" -q $KERNEL_PKGS sp11-surface-support sp11-iptsd
check test "$(r rpm --root "$ROOTFS" -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)" = "$KERNEL_ABI"
# The sensors stack is part of the media (inert here: no FastRPC node without the ADSP; active on the installed
# system). Step 50 applied its scriptlet effects itself: the fastrpc user, the policy module, the registry copy.
check r rpm --root "$ROOTFS" -q hexagonrpc libssc iio-sensor-proxy sp11-sensors
for rpmf in "$(rpm_of hexagonrpc)" "$(rpm_of libssc)" "$(rpm_of iio-sensor-proxy)" "$(rpm_of sp11-sensors)"; do
  check r rpm --root "$ROOTFS" -U --test --replacepkgs "$rpmf"
done
check r sh -c "rpm --root '$ROOTFS' -q --qf '%{RELEASE}\n' iio-sensor-proxy | grep -q '\.sp11\.'"
check r chroot "$ROOTFS" /usr/bin/sh -c 'ldd /usr/libexec/iio-sensor-proxy | grep -q libssc.so.2'
check r chroot "$ROOTFS" /usr/bin/getent passwd fastrpc
check r sh -c "chroot '$ROOTFS' /usr/sbin/semodule -l | grep -qx sp11-sensors"
check r test -s "$ROOTFS/var/lib/sp11/hexagonrpc/sensors/persist/registry/sns_reg_config"
check test "$(r stat -c %Y "$ROOTFS/var/lib/sp11/hexagonrpc/sensors/persist/registry/tdm_uid.bin")" = "$(r stat -c %Y "$ROOTFS$SENSORS_PAYLOAD_DIR/sensors/registry/tdm_uid.bin")"
check r grep -q 'iio-sensor-proxy' "$ROOTFS/etc/dnf/libdnf5.conf.d/91-sp11-sensors.conf"
check r test ! -e "$ROOTFS/usr/lib/dracut/modules.d/95sp11-sensors"
check sh -c "! lsinitrd '$WORK_DIR/iso/initrd' | grep -qE 'sp11-sensors|hexagonrpc'"
for rpmf in "$(rpm_of kernel-core)" "$(rpm_of sp11-surface-support)" "$(rpm_of sp11-iptsd)"; do
  check r rpm --root "$ROOTFS" -U --test --replacepkgs "$rpmf"
done
for bin in /usr/libexec/sp11-iptsd /usr/libexec/sp11-iptsd-check-device /usr/libexec/sp11/sp11-bt-set-addr; do
  check r chroot "$ROOTFS" /usr/bin/sh -c "! ldd $bin | grep -q 'not found'"
done
check r chroot "$ROOTFS" /usr/libexec/sp11-iptsd-check-device --help
check r test -x "$ROOTFS/usr/bin/liveinst"
# Step 50 replaces the stock kernel packages with the SP11 build of the same packages and removes every module tree
# the stock kernel leaves behind: every kernel package in the root is the SP11 build.
# shellcheck disable=SC2086
mapfile -t stock_pkgs < <(r rpm --root "$ROOTFS" -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' $KERNEL_STOCK_PKGS \
  | grep -vF -- "-$KERNEL_ABI" || true)
log "stock kernel packages: ${stock_pkgs[*]:-none}"
check test "${#stock_pkgs[@]}" -eq 0
check test "$(ls "$ROOTFS/usr/lib/modules")" = "$KERNEL_ABI"
# The plugin does not filter live-only arguments, so Anaconda must not carry any of them into the installed system.
check r test -f "$ROOTFS/etc/anaconda/anaconda.conf"
check r sh -c "! grep -rqE 'modprobe\.blacklist|rd\.driver\.blacklist' '$ROOTFS/etc/anaconda'"

log "--- kernel-install hand-off simulation (chroot, inputs as Anaconda leaves them)"
T="$WORK_DIR/iso/handoff-test"
[ -z "$(mounts_under "$T")" ] || die "mounts left under $T from an earlier run; unmount them first: $(mounts_under "$T" | tr '\n' ' ')"
r rm -rf --one-file-system "$T"; mkdir -p "$T"
# Work on a throwaway overlay of the real root so the live root stays untouched.
r mkdir -p "$T/upper" "$T/work" "$T/merged"
cleanup() { [ -n "${LOOP:-}" ] && { r umount "$T/esp" 2>/dev/null || true; r losetup -d "$LOOP" 2>/dev/null || true; }; r umount -R "$T/merged/dev" "$T/merged/proc" "$T/merged/sys" 2>/dev/null || true; r umount "$T/merged" 2>/dev/null || true; }
trap cleanup EXIT
r mount -t overlay overlay -o "lowerdir=$ROOTFS,upperdir=$T/upper,workdir=$T/work" "$T/merged" || die "overlay mount failed"
M="$T/merged"
for d in dev proc sys; do r mount --rbind "/$d" "$M/$d"; r mount --make-rslave "$M/$d"; done
# Anaconda's bootloader step writes /etc/default/grub from scratch (only the preserved live arguments reach
# GRUB_CMDLINE_LINUX) and its grub2-mkconfig writes /etc/kernel/cmdline from it; its payload step has already turned
# the live media's modprobe.blacklist= into anaconda-denylist.conf. kernel-install add comes next. (On a BTRFS root
# Anaconda repeats its bootloader step afterwards, which sp11-first-boot corrects on the first boot.)
ANACONDA_ARGS="rd.luks.uuid=luks-0000-test rhgb quiet clk_ignore_unused pd_ignore_unused"
r tee "$M/etc/default/grub" >/dev/null <<GRUB
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="\$(sed 's, release .*\$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="$ANACONDA_ARGS"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
GRUB
printf 'root=UUID=0000-test ro %s\n' "$ANACONDA_ARGS" | r tee "$M/etc/kernel/cmdline" >/dev/null
r tee "$M/etc/modprobe.d/anaconda-denylist.conf" >/dev/null <<<"blacklist qcom_q6v5_pas"
r tee "$M/etc/kernel/install.conf" >/dev/null <<<"initrd_generator=none"
echo 0123456789abcdef0123456789abcdef | r tee "$M/etc/machine-id" >/dev/null
r mkdir -p "$M/boot/loader/entries" "$M/boot/grub2"
r chroot "$M" /usr/bin/kernel-install --verbose add "$KERNEL_ABI" "/usr/lib/modules/$KERNEL_ABI/vmlinuz" 2>&1 | tee "$T/kernel-install.log" >/dev/null || warn "kernel-install returned non-zero (see $T/kernel-install.log)"
entry=$(r find "$M/boot/loader/entries" -name "*$KERNEL_ABI*.conf" | head -1)
log "BLS entry: ${entry:-none}"
[ -n "$entry" ] && r cat "$entry" | sed 's/^/    /'
check test -n "$entry"
check r grep -q "^devicetree /dtb-$KERNEL_ABI/$SP11_DTB" "$entry"
check r test -s "$M/boot/dtb-$KERNEL_ABI/$SP11_DTB"
for a in $SP11_ARGS_INSTALLED; do check r grep -q "^options .*\b$a\b" "$entry"; done
# `grep -vq` would succeed on any non-matching line; assert absence with a negated grep instead.
for a in $SP11_ARGS_LIVE_ONLY; do check r sh -c "! grep -q '^options .*$a' '$entry'"; done
check r grep -q "^GRUB_DEVICETREE=\"$SP11_DTB\"" "$M/etc/default/grub"
check r grep -q '^GRUB_TERMINAL_OUTPUT="gfxterm"' "$M/etc/default/grub"
check r grep -q "^GRUB_GFXMODE=$GRUB_GFXMODE_VALUE\$" "$M/etc/default/grub"
check r grep -q "^GRUB_FONT=\"/boot/grub2/fonts/$GRUB_FONT_FILE\"\$" "$M/etc/default/grub"
check r test -s "$M/boot/grub2/fonts/$GRUB_FONT_FILE"
check r grep -q "^GRUB_TIMEOUT=$GRUB_TIMEOUT_VALUE\$" "$M/etc/default/grub"
for a in $ANACONDA_ARGS $SP11_ARGS_INSTALLED; do check r grep -qwF -- "$a" "$M/etc/kernel/cmdline"; done
check r grep -q '^root=UUID=0000-test ro ' "$M/etc/kernel/cmdline"
check r test ! -e "$M/etc/modprobe.d/anaconda-denylist.conf"

log "--- Windows chainload generator (fake Windows ESP on a loop device, run in the chroot)"
IMG="$T/fake-esp.img"; LOOP=""
cleanup_loop() { [ -n "$LOOP" ] && { r umount "$T/esp" 2>/dev/null || true; r losetup -d "$LOOP" 2>/dev/null || true; }; }
truncate -s 64M "$IMG"
printf 'label: gpt\ntype=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=FAKE-WIN-ESP\n' | r sfdisk -q "$IMG" >/dev/null
LOOP=$(r losetup -fP --show "$IMG") && log "loop device: $LOOP"
r mkfs.vfat -F 32 -n WINESP "${LOOP}p1" >/dev/null
mkdir -p "$T/esp"; r mount "${LOOP}p1" "$T/esp"
r mkdir -p "$T/esp/EFI/Microsoft/Boot"; r touch "$T/esp/EFI/Microsoft/Boot/bootmgfw.efi"; r umount "$T/esp"
ESP_UUID=$(r blkid -s UUID -o value "${LOOP}p1")
r mkdir -p "$M/boot/grub2"
GEN_OUT=$(r chroot "$M" /usr/bin/env pkgdatadir=/usr/share/grub /etc/grub.d/29_sp11_windows 2>"$T/generator.err") || warn "generator exited non-zero: $(cat "$T/generator.err")"
printf '%s\n' "$GEN_OUT" | sed 's/^/    /'
check grep -q "search --no-floppy --fs-uuid --set=root $ESP_UUID" <<<"$GEN_OUT"
check grep -q "chainloader /EFI/Microsoft/Boot/bootmgfw.efi" <<<"$GEN_OUT"
check grep -q "^menuentry 'Windows Boot Manager (on ${LOOP}p1)'" <<<"$GEN_OUT"
check r test -f "$M/boot/grub2/arm64-efi/chain.mod"
check r cmp -s "$M/usr/lib/grub/arm64-efi/chain.mod" "$M/boot/grub2/arm64-efi/chain.mod"
check r test -z "$(r findmnt -rno TARGET "${LOOP}p1")"
cleanup_loop
cleanup; trap - EXIT
[ "$fail" = 0 ] && log "all checks passed" || die "some checks failed"
