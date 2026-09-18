#!/usr/bin/bash
# Step 4: build the sp11-surface-support RPM: device firmware from this machine's Windows installation,
# ooaklee FullIO v19c audio files, Wi-Fi board data, Bluetooth address service, kernel-install boot
# policy plugin, dracut policy and the first-boot finalizer.
. "$(dirname "$0")/lib.sh"
require_cmd gcc python3 xz rpm2cpio cpio rpmbuild file
load_hardware

# Bump whenever anything under files/ or the generated payload changes, so `dnf upgrade` picks it up.
VERSION="2.2"

CACHED=$(rpm_of sp11-surface-support)
if [ -n "$CACHED" ] && [ "${FORCE:-0}" != 1 ]; then
  # The dist tag counts as well: switching FEDORA_RELEASE must not reuse the other release's package, whose
  # board.bin comes from that release's atheros-firmware and whose %{dist} names the wrong Fedora.
  case "$(rpm -qp --qf '%{VERSION} %{RELEASE}' "$CACHED" 2>/dev/null)" in
    "$VERSION "*".fc$FEDORA_RELEASE") log "support RPM already built: $CACHED (FORCE=1 to rebuild)"; exit 0 ;;
  esac
  log "cached $(basename "$CACHED") is not version $VERSION for Fedora $FEDORA_RELEASE; rebuilding"
fi

SDIR="$BUILD_DIR/support"; STAGE="$SDIR/stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"

## 1. Qualcomm platform firmware from the Windows DriverStore (device-bound; newest copy of each file wins,
##    the same rule Fedora's qcom-firmware-extract uses): exactly the files the Denali device tree requests,
##    under the names it requests them by. Windows ships the DSP device-tree blobs as *_dtbs.elf.
FR="$WINDOWS_ROOT/Windows/System32/DriverStore/FileRepository"
[ -d "$FR" ] || die "Windows DriverStore not found at $FR (is Windows mounted at $WINDOWS_ROOT?)"
FWD="$STAGE/usr/lib/firmware/qcom/x1e80100/microsoft/Denali"; install -d "$FWD"
for pair in qcadsp8380.mbn:qcadsp8380.mbn adsp_dtbs.elf:adsp_dtb.mbn qccdsp8380.mbn:qccdsp8380.mbn \
            cdsp_dtbs.elf:cdsp_dtb.mbn qcdxkmsuc8380.mbn:qcdxkmsuc8380.mbn; do
  win=${pair%%:*}; dt=${pair#*:}
  src=$(find "$FR" -maxdepth 2 -type f -iname "$win" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
  [ -n "$src" ] || die "firmware $win not found in $FR"
  file -b "$src" | grep ELF >/dev/null || die "$win does not look like a signed ELF image"
  install -m 0644 "$src" "$FWD/$dt"
  log "firmware $dt <- ${src#"$FR"/}"
done

## 2. Audio: FullIO v19c topology + UCM (regex corrected for the 5G SKU and validated against this machine)
AUDIO_DIR="$CACHE_DIR/$AUDIO_RELEASE_TAG"
( cd "$AUDIO_DIR" && sha256sum -c --quiet SHA256SUMS ) || die "audio release checksum failure"
install -D -m 0644 "$AUDIO_DIR/X1E80100-Microsoft-Surface-Pro-11-tplg.bin" "$STAGE/usr/lib/firmware/qcom/x1e80100/X1E80100-Microsoft-Surface-Pro-11-tplg.bin"
install -D -m 0644 "$AUDIO_DIR/MICROSOFT-Surface-Pro-11in.conf" "$STAGE/usr/share/alsa/ucm2/Qualcomm/x1e80100/MICROSOFT-Surface-Pro-11in.conf"
install -D -m 0644 "$AUDIO_DIR/SP11-HiFi.conf" "$STAGE/usr/share/alsa/ucm2/Qualcomm/x1e80100/SP11-HiFi.conf"
UCM_OUT="$STAGE/usr/share/sp11/ucm/x1e80100.conf"; install -d "$(dirname "$UCM_OUT")"
grep -q 'Regex "Microsoft Corporation.\*Surface.\*Microsoft Surface Pro, 11th Edition"' "$AUDIO_DIR/x1e80100.conf" \
  || die "unexpected SP11 matcher in $AUDIO_DIR/x1e80100.conf; review UCM_SP11_REGEX handling"
sed "s|Regex \"Microsoft Corporation\.\*Surface\.\*Microsoft Surface Pro, 11th Edition\"|Regex \"$UCM_SP11_REGEX\"|" \
  "$AUDIO_DIR/x1e80100.conf" > "$UCM_OUT"
grep -qF "Regex \"$UCM_SP11_REGEX\"" "$UCM_OUT" || die "UCM regex substitution failed"
printf '%s\n' "$SP11_UCM_DMI_INFO" | grep -Eq "$UCM_SP11_REGEX" || die "UCM regex does not match this device: $SP11_UCM_DMI_INFO"
log "UCM matcher validated against '$SP11_UCM_DMI_INFO'"

## 3. Wi-Fi: WCN7850 board.bin fallback extracted from linux-firmware's board-2.bin
WIFI_TMP="$SDIR/wifi"; rm -rf "$WIFI_TMP"; mkdir -p "$WIFI_TMP/x"
RPM_AF=$(ls -t "$CACHE_DIR/wifi/f$FEDORA_RELEASE"/atheros-firmware-*.rpm 2>/dev/null | head -1 || true)
[ -n "$RPM_AF" ] || die "atheros-firmware RPM missing (run scripts/10-fetch-sources.sh)"
rpm2cpio "$RPM_AF" | cpio -i --quiet --to-stdout ./usr/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin.xz \
  | xz -d > "$WIFI_TMP/board-2.bin" || die "cannot extract board-2.bin.xz from $(basename "$RPM_AF")"
( cd "$WIFI_TMP/x" && python3 "$CACHE_DIR/ath12k-bdencoder" --extract "$WIFI_TMP/board-2.bin" >/dev/null 2>&1 ) \
  || die "ath12k-bdencoder extraction failed"
[ -s "$WIFI_TMP/x/$WIFI_BOARD_ENTRY.bin" ] || die "board entry '$WIFI_BOARD_ENTRY' not found in board-2.bin"
install -D -m 0644 "$WIFI_TMP/x/$WIFI_BOARD_ENTRY.bin" "$STAGE/usr/lib/firmware/ath12k/WCN7850/hw2.0/board.bin"
log "Wi-Fi board.bin: $WIFI_BOARD_ENTRY ($(stat -c %s "$STAGE/usr/lib/firmware/ath12k/WCN7850/hw2.0/board.bin") bytes)"

## 4. Bluetooth public address (raw HCI management helper + udev-triggered service)
verify_sha256 "$CACHE_DIR/sp11-bt-set-addr.c" "$BT_HELPER_SHA256"
# Upstream copies the printed octets into the MGMT payload in string order, but bdaddr_t is little-endian
# (byte 0 = last printed octet), so the unpatched helper sets the address byte-reversed.
# The bonds transferred from Windows are tied to the real address, so store the octets reversed.
BT_SRC="$SDIR/sp11-bt-set-addr.c"; cp "$CACHE_DIR/sp11-bt-set-addr.c" "$BT_SRC"
sed -i 's/^\t\tout\[i\] = (uint8_t)val;$/\t\tout[5 - i] = (uint8_t)val; \/* bdaddr_t is little-endian *\//' "$BT_SRC"
grep -q 'out\[5 - i\] = (uint8_t)val;' "$BT_SRC" || die "bdaddr byte-order patch did not apply to sp11-bt-set-addr.c"
install -d "$STAGE/usr/libexec/sp11"
gcc -O2 -Wall -Wextra -o "$STAGE/usr/libexec/sp11/sp11-bt-set-addr" "$BT_SRC" || die "sp11-bt-set-addr failed to compile"
install -m 0755 "$FILES_DIR/sp11-bt-apply" "$STAGE/usr/libexec/sp11/sp11-bt-apply"
install -D -m 0644 "$FILES_DIR/sp11-bluetooth-address@.service" "$STAGE/usr/lib/systemd/system/sp11-bluetooth-address@.service"
install -D -m 0644 "$FILES_DIR/99-sp11-bluetooth-address.rules" "$STAGE/usr/lib/udev/rules.d/99-sp11-bluetooth-address.rules"
install -d -m 0755 "$STAGE/etc/sp11"
printf '# Bluetooth public address of this Surface Pro 11 (from Windows)\nSP11_BT_MAC="%s"\n' "$SP11_BT_MAC" > "$STAGE/etc/sp11/bluetooth-address"
chmod 0600 "$STAGE/etc/sp11/bluetooth-address"

## 5. Boot policy: kernel-install plugin, first-boot finalizer, dracut policy, UCM apply helper
install -m 0755 "$FILES_DIR/sp11-ucm-apply" "$STAGE/usr/libexec/sp11/sp11-ucm-apply"
install -m 0755 "$FILES_DIR/sp11-grub-modules" "$STAGE/usr/libexec/sp11/sp11-grub-modules"
install -m 0755 "$FILES_DIR/sp11-grub-defaults" "$STAGE/usr/libexec/sp11/sp11-grub-defaults"
# The ISO build removes the stock kernel packages; they must not come back through `dnf upgrade`.
install -D -m 0644 "$FILES_DIR/90-sp11-dnf.conf" "$STAGE/etc/dnf/libdnf5.conf.d/90-sp11.conf"
install -D -m 0755 "$FILES_DIR/29_sp11_windows" "$STAGE/etc/grub.d/29_sp11_windows"
install -m 0755 "$FILES_DIR/sp11-first-boot" "$STAGE/usr/libexec/sp11/sp11-first-boot"
install -m 0755 "$FILES_DIR/sp11-bt-import-pairings" "$STAGE/usr/libexec/sp11/sp11-bt-import-pairings"
install -m 0755 "$FILES_DIR/sp11-diag" "$STAGE/usr/libexec/sp11/sp11-diag"
install -D -m 0644 "$FILES_DIR/sp11-first-boot.service" "$STAGE/usr/lib/systemd/system/sp11-first-boot.service"
install -d "$STAGE/usr/lib/systemd/system/multi-user.target.wants"
ln -sf ../sp11-first-boot.service "$STAGE/usr/lib/systemd/system/multi-user.target.wants/sp11-first-boot.service"
install -D -m 0755 "$FILES_DIR/15-sp11-surface.install" "$STAGE/usr/lib/kernel/install.d/15-sp11-surface.install"
install -D -m 0644 "$FILES_DIR/90-sp11.conf" "$STAGE/usr/lib/dracut/dracut.conf.d/90-sp11.conf"
install -D -m 0644 "$FILES_DIR/90-sp11.sysctl.conf" "$STAGE/usr/lib/sysctl.d/90-sp11.conf"
install -d "$STAGE/etc/kernel"; printf '%s\n' "$SP11_DTB" > "$STAGE/etc/kernel/devicetree"
cat > "$STAGE/etc/sp11/sp11.env" <<ENV
# Surface Pro 11 boot policy (generated by scripts/30-build-support-rpm.sh)
SP11_DTB="$SP11_DTB"
SP11_ARGS_INSTALLED="$SP11_ARGS_INSTALLED"
SP11_ARGS_LIVE_ONLY="$SP11_ARGS_LIVE_ONLY"
SP11_GRUB_GFXMODE="$GRUB_GFXMODE_VALUE"
SP11_GRUB_TIMEOUT="$GRUB_TIMEOUT_VALUE"
SP11_SKU="$SP11_SKU"
ENV
# `bash -n A B C` parses only A (B and C become positional parameters): check every script on its own.
for f in "$STAGE/usr/lib/kernel/install.d/15-sp11-surface.install" \
         "$STAGE"/usr/libexec/sp11/sp11-{first-boot,grub-modules,grub-defaults,bt-import-pairings,diag,bt-apply,ucm-apply}; do
  bash -n "$f" || die "shell syntax error in ${f#"$STAGE"}"
done
sh -n "$STAGE/etc/grub.d/29_sp11_windows" || die "syntax error in 29_sp11_windows"

## 6. RPM
log "building sp11-surface-support RPM"
RPM=$(build_rpm "$SPEC_DIR/sp11-surface-support.spec.in" sp11-surface-support "$SDIR" \
  STAGE="$STAGE" VERSION="$VERSION" SKU="$SP11_SKU" AUDIO_TAG="$AUDIO_RELEASE_TAG")
rpm -qpl "$RPM" | grep -x "/usr/lib/firmware/qcom/x1e80100/microsoft/Denali/qcdxkmsuc8380.mbn" >/dev/null || die "RPM lacks GPU zap firmware"
log "support RPM: $RPM ($(du -h "$RPM" | cut -f1))"
