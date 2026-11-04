#!/usr/bin/bash
# Step 2: download and verify every external input (idempotent; cached under build/cache).
. "$(dirname "$0")/lib.sh"
require_cmd curl sha256sum git python3 tar xz cpio rpm2cpio dnf

## Fedora live ISO (FEDORA_EDITION) + upstream CHECKSUM (one per product; all spins of a compose share one)
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
# ...and the SP11 patch set: the kernel fork, the submodule linux-sp11, pinned by its gitlink (KERNEL_PATCH_COMMIT).
# Only that commit is fetched, with its history back to the pinned base (a shallow fetch, deepened until the base is
# there; about 250 MB once), and checked out; the series is written from it and checked against the commit's tree.
# A full clone, as `git submodule add --reference` leaves, passes without a fetch. The fork's history is 5 GB, which
# `git submodule update` would fetch whole for a commit it lacks: .gitmodules sets update=none, so the generic
# submodule commands skip it and no fetch of this repository recurses into it; this step owns it.
kernel_patch_pin
G="$KERNEL_PATCH_GIT"
if [ ! -e "$G/.git" ]; then
  log "initializing the submodule linux-sp11 (the kernel fork, shallow)"
  git -C "$SP11_ROOT" submodule init -q -- linux-sp11 || die "cannot register the submodule linux-sp11"
  url=$(git -C "$SP11_ROOT" config --get submodule.linux-sp11.url) || die "no URL registered for the submodule linux-sp11"
  mkdir -p "$G" && git init -q "$G" && git -C "$G" remote add origin "$url" || die "cannot initialize $G"
fi
depth=0
until git -C "$G" merge-base --is-ancestor "$KERNEL_PATCH_BASE_COMMIT" "$KERNEL_PATCH_COMMIT" 2>/dev/null; do
  depth=$((depth + 64)); [ "$depth" -le 1024 ] || die "$KERNEL_PATCH_BASE ($KERNEL_PATCH_BASE_COMMIT) is not an ancestor of ${KERNEL_PATCH_COMMIT:0:12} within 1024 commits"
  [ "$depth" -gt 64 ] || log "fetching the pinned fork commit ${KERNEL_PATCH_COMMIT:0:12} back to $KERNEL_PATCH_BASE"
  git -C "$G" fetch -q --no-tags --depth="$depth" origin "$KERNEL_PATCH_COMMIT" \
    || die "cannot fetch $KERNEL_PATCH_COMMIT from $(git -C "$G" remote get-url origin)"
done
head=$(git -C "$G" rev-parse -q --verify HEAD 2>/dev/null || true)
if [ -z "$head" ]; then
  git -C "$G" checkout -q --detach "$KERNEL_PATCH_COMMIT" || die "cannot check out $KERNEL_PATCH_COMMIT in $G"
  # its .git into the superproject's, as `git submodule add` lays it out
  git -C "$SP11_ROOT" submodule absorbgitdirs -- linux-sp11 >/dev/null 2>&1 || warn "linux-sp11/.git stays a directory (git submodule absorbgitdirs failed)"
elif [ "$head" != "$KERNEL_PATCH_COMMIT" ]; then
  die "linux-sp11 is checked out at ${head:0:12}, the index pins ${KERNEL_PATCH_COMMIT:0:12}: 'git -C linux-sp11 checkout --detach ${KERNEL_PATCH_COMMIT:0:12}' follows the pin, 'git add linux-sp11' pins the checkout (a changed patch set needs a new KERNEL_SP11_REV)"
fi
git -C "$G" diff --quiet HEAD -- || die "linux-sp11 has uncommitted changes; the patch set is read from commits only"
n=$(git -C "$G" rev-list --count "$KERNEL_PATCH_BASE_COMMIT..$KERNEL_PATCH_COMMIT")
if [ ! -f "$KERNEL_PATCH_SERIES/.complete" ] || [ "${FORCE:-0}" = 1 ]; then
  rm -rf "$KERNEL_PATCH_SERIES"; mkdir -p "$KERNEL_PATCH_SERIES"
  git -C "$G" format-patch -q --no-signature --no-renames -o "$KERNEL_PATCH_SERIES" \
    "$KERNEL_PATCH_BASE_COMMIT..$KERNEL_PATCH_COMMIT" || die "format-patch of the SP11 patch set failed"
  [ "$(find "$KERNEL_PATCH_SERIES" -name '*.patch' | wc -l)" = "$n" ] || die "the SP11 series does not have $n patches"
  kernel_series_check || die "the SP11 series does not rebuild the tree of $KERNEL_PATCH_COMMIT"
  touch "$KERNEL_PATCH_SERIES/.complete"
fi
log "SP11 patch set: $n commits, $KERNEL_PATCH_BASE..${KERNEL_PATCH_COMMIT:0:12}$([ -f "$(git -C "$G" rev-parse --git-path shallow)" ] && echo ' (shallow)')"

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
## Sensors stack (scripts/45): hexagonrpc from the project's fork, the submodule hexagonrpc pinned by its gitlink
## (HEXAGONRPC_COMMIT); only that commit is fetched, under the rules of linux-sp11 above (this step owns it, the
## generic submodule commands skip it). Then libssc's pinned upstream checkout, Fedora's iio-sensor-proxy source RPM
## (pinned in sp11.conf, rebuilt with its SSC drivers), and the runtime dependencies the live root may lack (steps 50
## and 46 add them).
submodule_pin hexagonrpc "$HEXAGONRPC_COMMIT"
git_pin "$LIBSSC_REPO" "$LIBSSC_COMMIT" "$CACHE_DIR/libssc"
fetch "$IIO_SENSOR_PROXY_SRPM_URL" "$CACHE_DIR/$IIO_SENSOR_PROXY_SRPM"
verify_sha256 "$CACHE_DIR/$IIO_SENSOR_PROXY_SRPM" "$IIO_SENSOR_PROXY_SRPM_SHA256"
for pkg in $SENSORS_DEPS_PKGS; do
  if [ "${FORCE:-0}" = 1 ] || ! ls "$DEPS_DIR/$pkg"-[0-9]*.rpm >/dev/null 2>&1; then
    log "downloading $pkg (Fedora $FEDORA_RELEASE)"
    rm -f "$DEPS_DIR/$pkg"-[0-9]*.rpm
    ( cd "$DEPS_DIR" && dnf -q download --releasever="$FEDORA_RELEASE" --arch=aarch64 "$pkg" ) || die "dnf download $pkg failed"
  fi
done
log "all sources present under $CACHE_DIR"
