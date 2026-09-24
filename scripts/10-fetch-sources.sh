#!/usr/bin/bash
# Step 2: download and verify every external input (idempotent; cached under build/cache).
. "$(dirname "$0")/lib.sh"
require_cmd curl sha256sum git python3 tar xz cpio rpm2cpio dnf

## Fedora live ISO (FEDORA_EDITION) + upstream CHECKSUM (all spins of a compose share one)
fetch "$FEDORA_ISO_BASEURL/$FEDORA_CHECKSUM_NAME" "$CACHE_DIR/$FEDORA_CHECKSUM_NAME"
fetch "$FEDORA_ISO_BASEURL/$FEDORA_ISO_NAME" "$CACHE_DIR/$FEDORA_ISO_NAME"
( cd "$CACHE_DIR" && sha256sum -c --ignore-missing "$FEDORA_CHECKSUM_NAME" 2>/dev/null | grep -x "$FEDORA_ISO_NAME: OK" >/dev/null ) \
  || die "Fedora ISO failed checksum verification"
log "verified $FEDORA_ISO_NAME"

## Kernel: Fedora's own kernel source RPM for the target release, checksum pinned in sp11.conf (Koji keeps every build)
fetch "$KERNEL_SRPM_URL" "$CACHE_DIR/$KERNEL_SRPM"
verify_sha256 "$CACHE_DIR/$KERNEL_SRPM" "$KERNEL_SRPM_SHA256"
# ...and Fedora's own kernel-core of that build, the reference step 20 compares the SP11 configuration with
fetch "$KERNEL_STOCK_CORE_URL" "$CACHE_DIR/$KERNEL_STOCK_CORE_RPM"
verify_sha256 "$CACHE_DIR/$KERNEL_STOCK_CORE_RPM" "$KERNEL_STOCK_CORE_SHA256"
# ...and the SP11 patch set: the kernel fork's pinned commit with its history back to the pinned base, fetched without
# file contents (a few MB) and deepened until the base is there; the series is written from it, git fetching the
# contents of the files the patches touch on demand, and checked against the commit's tree. Lookups before and after
# the fetch run with GIT_NO_LAZY_FETCH: in a partial clone, asking for a missing commit makes git fetch it with its
# whole history (3 GB of Linux commits and trees).
G="$KERNEL_PATCH_GIT"
if [ ! -d "$G" ]; then
  git init -q --bare "$G"
  git -C "$G" config core.repositoryformatversion 1
  git -C "$G" config extensions.partialClone origin
  git -C "$G" remote add origin "$KERNEL_PATCH_REPO"
  git -C "$G" config remote.origin.promisor true
  git -C "$G" config remote.origin.partialclonefilter blob:none
fi
git -C "$G" remote set-url origin "$KERNEL_PATCH_REPO"
depth=0
until GIT_NO_LAZY_FETCH=1 git -C "$G" merge-base --is-ancestor "$KERNEL_PATCH_BASE_COMMIT" "$KERNEL_PATCH_COMMIT" 2>/dev/null; do
  depth=$((depth + 64)); [ "$depth" -le 1024 ] || die "$KERNEL_PATCH_BASE_COMMIT is not an ancestor of $KERNEL_PATCH_COMMIT within 1024 commits"
  git -C "$G" fetch -q --no-tags --filter=blob:none --depth="$depth" origin "$KERNEL_PATCH_COMMIT" \
    || die "cannot fetch $KERNEL_PATCH_COMMIT from $KERNEL_PATCH_REPO"
done
n=$(GIT_NO_LAZY_FETCH=1 git -C "$G" rev-list --count "$KERNEL_PATCH_BASE_COMMIT..$KERNEL_PATCH_COMMIT")
if [ ! -f "$KERNEL_PATCH_SERIES/.complete" ] || [ "${FORCE:-0}" = 1 ]; then
  rm -rf "$KERNEL_PATCH_SERIES"; mkdir -p "$KERNEL_PATCH_SERIES"
  git -C "$G" format-patch -q --no-signature --no-renames -o "$KERNEL_PATCH_SERIES" \
    "$KERNEL_PATCH_BASE_COMMIT..$KERNEL_PATCH_COMMIT" || die "format-patch of the SP11 patch set failed"
  [ "$(find "$KERNEL_PATCH_SERIES" -name '*.patch' | wc -l)" = "$n" ] || die "the SP11 series does not have $n patches"
  kernel_series_check || die "the SP11 series does not rebuild the tree of $KERNEL_PATCH_COMMIT"
  touch "$KERNEL_PATCH_SERIES/.complete"
fi
log "SP11 patch set: $n commits, $KERNEL_PATCH_BASE..${KERNEL_PATCH_COMMIT:0:12}"

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
## Runtime dependency RPMs for the live root, from the target release's repositories (their sonames have to match
## the live root's libraries, not the host's)
DEPS_DIR="$CACHE_DIR/rpm-deps/f$FEDORA_RELEASE"; mkdir -p "$DEPS_DIR"
for pkg in $LIVE_EXTRA_PKGS; do
  if [ "${FORCE:-0}" = 1 ] || ! ls "$DEPS_DIR/$pkg"-[0-9]*.rpm >/dev/null 2>&1; then
    log "downloading $pkg (Fedora $FEDORA_RELEASE)"
    rm -f "$DEPS_DIR/$pkg"-[0-9]*.rpm
    ( cd "$DEPS_DIR" && dnf -q download --releasever="$FEDORA_RELEASE" --arch=aarch64 "$pkg" ) || die "dnf download $pkg failed"
  fi
done
## Sensors stack (scripts/45, installed system only): pinned upstream checkouts, Fedora's iio-sensor-proxy source
## RPM of the target release (rebuilt with its SSC drivers), and the runtime dependencies the live-root
## verification (scripts/46) may have to add. None of this enters the ISO.
git_pin "$HEXAGONRPC_REPO" "$HEXAGONRPC_COMMIT" "$CACHE_DIR/hexagonrpc"
git_pin "$LIBSSC_REPO" "$LIBSSC_COMMIT" "$CACHE_DIR/libssc"
if [ "${FORCE:-0}" = 1 ] || ! ls "$DEPS_DIR"/iio-sensor-proxy-[0-9]*.src.rpm >/dev/null 2>&1; then
  log "downloading the iio-sensor-proxy source RPM (Fedora $FEDORA_RELEASE)"
  rm -f "$DEPS_DIR"/iio-sensor-proxy-[0-9]*.src.rpm
  ( cd "$DEPS_DIR" && dnf -q download --releasever="$FEDORA_RELEASE" --source iio-sensor-proxy ) || die "dnf download --source iio-sensor-proxy failed"
fi
for pkg in $SENSORS_DEPS_PKGS; do
  if [ "${FORCE:-0}" = 1 ] || ! ls "$DEPS_DIR/$pkg"-[0-9]*.rpm >/dev/null 2>&1; then
    log "downloading $pkg (Fedora $FEDORA_RELEASE)"
    rm -f "$DEPS_DIR/$pkg"-[0-9]*.rpm
    ( cd "$DEPS_DIR" && dnf -q download --releasever="$FEDORA_RELEASE" --arch=aarch64 "$pkg" ) || die "dnf download $pkg failed"
  fi
done
log "all sources present under $CACHE_DIR"
