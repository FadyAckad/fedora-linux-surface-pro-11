#!/usr/bin/bash
# Step 2: download and verify every external input (idempotent; cached under build/cache).
. "$(dirname "$0")/lib.sh"
require_cmd curl sha256sum git python3 ar tar xz cpio rpm2cpio dnf

## Fedora live ISO (FEDORA_EDITION) + upstream CHECKSUM (all spins of a compose share one)
fetch "$FEDORA_ISO_BASEURL/$FEDORA_CHECKSUM_NAME" "$CACHE_DIR/$FEDORA_CHECKSUM_NAME"
fetch "$FEDORA_ISO_BASEURL/$FEDORA_ISO_NAME" "$CACHE_DIR/$FEDORA_ISO_NAME"
( cd "$CACHE_DIR" && sha256sum -c --ignore-missing "$FEDORA_CHECKSUM_NAME" 2>/dev/null | grep -x "$FEDORA_ISO_NAME: OK" >/dev/null ) \
  || die "Fedora ISO failed checksum verification"
log "verified $FEDORA_ISO_NAME"

## Kernel release (ooaklee)
KSUMS="$CACHE_DIR/$KERNEL_RELEASE_TAG.SHA256SUMS"
fetch "$KERNEL_RELEASE_BASEURL/SHA256SUMS" "$KSUMS"
case "$KERNEL_MODE" in
  build)
    fetch "$KERNEL_RELEASE_BASEURL/$KERNEL_SOURCE_TARBALL" "$CACHE_DIR/$KERNEL_SOURCE_TARBALL"
    verify_in_sums "$KSUMS" "$CACHE_DIR/$KERNEL_SOURCE_TARBALL"
    ;;
  prebuilt)
    for f in "$KERNEL_IMAGE_DEB" "$KERNEL_MODULES_DEB"; do
      fetch "$KERNEL_RELEASE_BASEURL/$f" "$CACHE_DIR/$f"; verify_in_sums "$KSUMS" "$CACHE_DIR/$f"
    done
    ;;
  *) die "KERNEL_MODE must be 'build' or 'prebuilt'" ;;
esac

## Audio release (ooaklee FullIO v19c)
AUDIO_DIR="$CACHE_DIR/$AUDIO_RELEASE_TAG"; mkdir -p "$AUDIO_DIR"
for f in $AUDIO_FILES; do fetch "$AUDIO_RELEASE_BASEURL/$f" "$AUDIO_DIR/$f"; done
( cd "$AUDIO_DIR" && sha256sum -c --quiet SHA256SUMS ) || die "audio release failed checksum verification"
log "verified $AUDIO_RELEASE_TAG"

## Pen: upstream iptsd + ooaklee OE integration templates
git_pin "$IPTSD_REPO" "$IPTSD_COMMIT" "$CACHE_DIR/iptsd"
git_pin "$OE_REPO" "$OE_COMMIT" "$CACHE_DIR/oe"

## Bluetooth helper source, Wi-Fi board-data encoder
fetch "$BT_HELPER_URL" "$CACHE_DIR/sp11-bt-set-addr.c"
verify_sha256 "$CACHE_DIR/sp11-bt-set-addr.c" "$BT_HELPER_SHA256"
fetch "$BDENCODER_URL" "$CACHE_DIR/ath12k-bdencoder"
python3 -m py_compile "$CACHE_DIR/ath12k-bdencoder" || die "ath12k-bdencoder is not valid Python"

## linux-firmware board-2.bin (WCN7850) from Fedora's atheros-firmware package. Unlike the pinned downloads
## above, the dnf caches float with the repos and carry no checksum: key them by release and honour FORCE=1.
WIFI_DIR="$CACHE_DIR/wifi/f$FEDORA_RELEASE"; mkdir -p "$WIFI_DIR"
if [ "${FORCE:-0}" = 1 ] || ! ls "$WIFI_DIR"/atheros-firmware-*.rpm >/dev/null 2>&1; then
  log "downloading atheros-firmware (Fedora $FEDORA_RELEASE)"
  rm -f "$WIFI_DIR"/atheros-firmware-*.rpm
  ( cd "$WIFI_DIR" && dnf -q download --releasever="$FEDORA_RELEASE" atheros-firmware ) || die "dnf download atheros-firmware failed"
fi
## Runtime dependency RPMs for the live root (same repo state as the build host, so sonames match)
DEPS_DIR="$CACHE_DIR/rpm-deps/f$FEDORA_RELEASE"; mkdir -p "$DEPS_DIR"
for pkg in $LIVE_EXTRA_PKGS; do
  if [ "${FORCE:-0}" = 1 ] || ! ls "$DEPS_DIR/$pkg"-[0-9]*.rpm >/dev/null 2>&1; then
    log "downloading $pkg (Fedora $FEDORA_RELEASE)"
    rm -f "$DEPS_DIR/$pkg"-[0-9]*.rpm
    ( cd "$DEPS_DIR" && dnf -q download --releasever="$FEDORA_RELEASE" --arch=aarch64 "$pkg" ) || die "dnf download $pkg failed"
  fi
done
log "all sources present under $CACHE_DIR"
