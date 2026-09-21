#!/usr/bin/bash
# Step 3: produce the kernel-sp11 RPM (kernel image, modules, Denali DTBs).
#   KERNEL_MODE=build    compile natively from ooaklee's source tarball with ooaklee's annotations config,
#                        plus the kernel.org stable patch KERNEL_STABLE_VERSION and, with KERNEL_SP11_REV set, this
#                        repository's config policy fragment (Fedora's LSM stack, no Ubuntu-only modules) and
#                        source patches (files/$KERNEL_PATCH_DIR)
#   KERNEL_MODE=prebuilt repackage ooaklee's released .deb payload
. "$(dirname "$0")/lib.sh"
require_cmd make gcc python3 depmod tar ar rpmbuild zstd xz patch

KDIR="$BUILD_DIR/kernel"
PAYLOAD="$KDIR/payload"
MODDIR="$PAYLOAD/usr/lib/modules/$KERNEL_ABI"
mkdir -p "$KDIR"

CACHED=$(rpm_of kernel-sp11)
if [ -n "$CACHED" ] && [ "${FORCE:-0}" != 1 ]; then
  if rpm -qpl "$CACHED" 2>/dev/null | grep -x "/boot/vmlinuz-$KERNEL_ABI" >/dev/null; then
    log "kernel RPM already built: $CACHED (FORCE=1 to rebuild)"; exit 0
  fi
  log "cached $(basename "$CACHED") is not kernel $KERNEL_ABI; rebuilding"
fi

# Options the ISO depends on. The build fails if the config lost any of them.
REQUIRED_OPTS="EROFS_FS EROFS_FS_ZIP EROFS_FS_ZIP_LZMA EROFS_FS_XATTR FW_LOADER_COMPRESS_XZ ATH12K DRM_MSM
  TOUCHSCREEN_MSHW0485 BT_QCA BT_HCIUART_QCA SND_SOC_X1E80100 SOUNDWIRE_QCOM QCOM_Q6V5_PAS QCOM_PD_MAPPER
  SURFACE_AGGREGATOR BATTERY_QCOM_BATTMGR EFI_ZBOOT NVME_CORE OVERLAY_FS ISO9660_FS DM_SNAPSHOT"
check_config() {
  local cfg=$1 o
  for o in $REQUIRED_OPTS; do grep -qE "^CONFIG_${o}=[ym]" "$cfg" || die "kernel config lacks CONFIG_$o"; done
  grep -q '^CONFIG_CRYPTO_FIPS=y' "$cfg" && die "CONFIG_CRYPTO_FIPS=y is not allowed"
  log "kernel config check passed (FIPS not compiled in, EROFS/LZMA, ath12k, msm, mshw0485, audio present)"
}

stage_common() {
  # Fedora layout: /usr/lib/modules/<abi>/{vmlinuz,System.map,config,dtb/...}; Anaconda uses /usr/lib/modules/<abi>/vmlinuz.
  install -m 0755 "$PAYLOAD/boot/vmlinuz-$KERNEL_ABI" "$MODDIR/vmlinuz"
  install -m 0644 "$PAYLOAD/boot/System.map-$KERNEL_ABI" "$MODDIR/System.map"
  install -m 0644 "$PAYLOAD/boot/config-$KERNEL_ABI" "$MODDIR/config"
  rm -f "$MODDIR/build" "$MODDIR/source"
  [ -s "$MODDIR/dtb/$SP11_DTB" ] || die "missing DTB $SP11_DTB in payload"
  # Fedora's depmod resolves <base>/lib/modules; the payload uses the /usr/lib layout, so expose it via a symlink.
  local base; base=$(mktemp -d); ln -s "$PAYLOAD/usr/lib" "$base/lib"
  depmod -b "$base" "$KERNEL_ABI" || { rm -rf "$base"; die "depmod failed"; }
  rm -rf "$base"
  [ -s "$MODDIR/modules.dep" ] || die "depmod produced no modules.dep under $MODDIR"
  # Ubuntu's out-of-tree drivers (ubuntu/ in the source) have no place in a Fedora kernel: the config policy
  # turns them off, and any future one that arrives "default m" fails here instead of shipping unnoticed.
  # (A path filter on the module root, not a find in kernel/ubuntu: that directory is absent once the policy is
  # on, and a find on a missing directory fails, which under pipefail ends the script without a message.)
  local ubuntu_mods; ubuntu_mods=$(find "$MODDIR/kernel" -path '*/kernel/ubuntu/*' -name '*.ko*' | wc -l)
  if [ "$ubuntu_mods" -gt 0 ] && [ -n "$KERNEL_SP11_REV" ]; then
    die "$ubuntu_mods Ubuntu-only module(s) under kernel/ubuntu in the payload"
  elif [ "$ubuntu_mods" -gt 0 ]; then
    warn "$ubuntu_mods Ubuntu-only module(s) under kernel/ubuntu in the payload (ooaklee's config as published)"
  fi
  local dtb_compat
  dtb_compat=$(fdtget -t s "$MODDIR/dtb/$SP11_DTB" / compatible 2>/dev/null || true)
  [[ $dtb_compat == *microsoft,denali-oled* ]] || die "DTB compatible check failed: '$dtb_compat'"
  log "payload staged: $(du -sh "$PAYLOAD" | cut -f1), $(find "$MODDIR/kernel" -name '*.ko*' | wc -l) modules, DTB compatible: $dtb_compat"
}

# This repository's source patches (files/$KERNEL_PATCH_DIR/*.patch, name order, part of KERNEL_SP11_REV). The tree
# keeps copies of the set it carries in .sp11-patches/: an unchanged set is left alone, a changed one is taken out
# again (patch -R, newest first) before the current set goes in, so a built tree stays built and make recompiles
# only what the patches touch. KERNEL_SP11_REV= takes every patch out (ooaklee's release as published).
apply_local_patches() {
  local src=$1 dir="$1/.sp11-patches" plog="$KDIR/local-patches.log" want=() have=() p i same=1
  if [ -n "$KERNEL_SP11_REV" ]; then
    for p in "$FILES_DIR/$KERNEL_PATCH_DIR"/*.patch; do [ -f "$p" ] && want+=("$p"); done
  fi
  if [ -d "$dir" ]; then
    for p in "$dir"/*.patch; do [ -f "$p" ] && have+=("$p"); done
  fi
  if [ "${#want[@]}" -eq "${#have[@]}" ]; then
    for i in "${!want[@]}"; do
      if [ "$(basename "${want[$i]}")" != "$(basename "${have[$i]}")" ] || ! cmp -s "${want[$i]}" "${have[$i]}"; then
        same=0; break
      fi
    done
    if [ "$same" = 1 ]; then
      [ "${#want[@]}" -eq 0 ] || log "local patches already in the tree: $(for p in "${want[@]}"; do basename "$p"; done | tr '\n' ' ')"
      return 0
    fi
  fi
  : >"$plog"
  # -R with --forward: a hunk that is not applied is an error, never a silent forward application.
  for (( i=${#have[@]}-1; i>=0; i-- )); do
    patch -d "$src" -p1 -R --batch --forward --fuzz=0 --no-backup-if-mismatch <"${have[$i]}" >>"$plog" 2>&1 \
      || die "cannot take $(basename "${have[$i]}") out of $src again (log: $plog); delete the tree to start over"
    rm -f "${have[$i]}"
    log "local patch taken out: $(basename "${have[$i]}")"
  done
  [ "${#want[@]}" -gt 0 ] || { rmdir "$dir" 2>/dev/null || true; return 0; }
  mkdir -p "$dir"
  for p in "${want[@]}"; do
    patch -d "$src" -p1 --batch --forward --fuzz=0 --no-backup-if-mismatch <"$p" >>"$plog" 2>&1 \
      || { grep -E 'FAILED|Reversed|can.t find|malformed' "$plog" | head -20 >&2 || true
           die "$(basename "$p") does not apply to $src (log: $plog)"; }
    cp "$p" "$dir/"
    log "local patch applied: $(basename "$p")"
  done
}

build_from_source() {
  local tarball="$CACHE_DIR/$KERNEL_SOURCE_TARBALL" src="$KDIR/src/linux-$KERNEL_SOURCE_COMMIT"
  [ -s "$tarball" ] || die "missing $tarball (run scripts/10-fetch-sources.sh)"
  if [ -n "$KERNEL_STABLE_VERSION" ]; then
    # A tree of its own, so the published source and its build stay untouched. The stamp is written only after the
    # whole patch applied; a tree without it is extracted again.
    local patchf="$CACHE_DIR/patch-$KERNEL_STABLE_VERSION.xz" plog="$KDIR/stable-patch.log"
    src="$src-stable-$KERNEL_STABLE_VERSION"
    if [ ! -f "$src/.sp11-stable-$KERNEL_STABLE_VERSION" ]; then
      [ -s "$patchf" ] || die "missing $patchf (run scripts/10-fetch-sources.sh)"
      verify_sha256 "$patchf" "$KERNEL_STABLE_SHA256"
      log "extracting kernel source and applying kernel.org stable patch-$KERNEL_STABLE_VERSION"
      rm -rf "$src"; mkdir -p "$src"
      tar -xzf "$tarball" -C "$src" --strip-components=1
      # --batch: never prompt (a prompt would read the patch stream); --forward: an already applied hunk is an error.
      xz -dc "$patchf" | patch -d "$src" -p1 --batch --forward --fuzz=1 --no-backup-if-mismatch >"$plog" 2>&1 \
        || { grep -E 'FAILED|Reversed|can.t find|malformed' "$plog" | head -20 >&2 || true
             die "patch-$KERNEL_STABLE_VERSION does not apply to $KERNEL_RELEASE_TAG (log: $plog)"; }
      log "patch-$KERNEL_STABLE_VERSION applied: $(grep -c '^patching file' "$plog") files, $(grep -c 'with fuzz' "$plog") hunk(s) with fuzz (log: $plog)"
      touch "$src/.sp11-stable-$KERNEL_STABLE_VERSION"
    fi
  elif [ ! -f "$src/Makefile" ]; then
    log "extracting kernel source"; mkdir -p "$KDIR/src"; tar -xzf "$tarball" -C "$KDIR/src"
  fi
  apply_local_patches "$src"
  [ -f "$src/debian.$KERNEL_FLAVOUR/config/annotations" ] || die "no debian.$KERNEL_FLAVOUR/config/annotations in source"
  cd "$src"
  local localversion="${KERNEL_ABI#"$KERNEL_BUILD_VERSION"}"   # e.g. -jg-0sp11v23-qcom-x1e

  log "generating .config from ooaklee's annotations (arch arm64, flavour $KERNEL_FLAVOUR)"
  python3 debian/scripts/misc/annotations --file "debian.$KERNEL_FLAVOUR/config/annotations" \
    --arch arm64 --flavour "$KERNEL_FLAVOUR" --export > .config || die "annotations export failed"
  # Identity: Ubuntu's packaging injects the ABI at build time; reproduce it through LOCALVERSION.
  scripts/config --set-str LOCALVERSION "$localversion"
  scripts/config --disable LOCALVERSION_AUTO
  scripts/config --set-str VERSION_SIGNATURE "SP11 $KERNEL_ABI (ooaklee ${KERNEL_SOURCE_COMMIT:0:12}${KERNEL_STABLE_VERSION:+ + stable $KERNEL_STABLE_VERSION}, built on Fedora $(rpm -E %{fedora}))"
  scripts/config --disable CRYPTO_FIPS
  if [ -n "$KERNEL_SP11_REV" ]; then
    # Config policy (Fedora's LSM stack, Ubuntu-only modules off) as a Kconfig fragment: -m merges it into
    # .config without running make, olddefconfig below resolves the dependencies, and the fragment is asserted
    # against the result (merge_config.sh checks its own values only when it runs make itself).
    log "merging config policy (SP11 revision $KERNEL_SP11_REV): files/$KERNEL_CONFIG_FRAGMENT"
    scripts/kconfig/merge_config.sh -m .config "$FILES_DIR/$KERNEL_CONFIG_FRAGMENT" >"$KDIR/config-merge.log" 2>&1 \
      || { cat "$KDIR/config-merge.log" >&2; die "merge_config.sh failed"; }
  fi
  make -s olddefconfig
  # kernelrelease is a no-sync-config target and setlocalversion reads include/config/auto.conf, which on a
  # built tree still holds the previous LOCALVERSION; sync it first, as the build itself would.
  make -s syncconfig
  [ "$(make -s kernelrelease)" = "$KERNEL_ABI" ] || die "kernelrelease '$(make -s kernelrelease)' != '$KERNEL_ABI'"
  check_config .config
  if [ -n "$KERNEL_SP11_REV" ]; then
    config_fragment_holds "$FILES_DIR/$KERNEL_CONFIG_FRAGMENT" .config || die "config policy did not survive olddefconfig"
    log "config policy (SP11 revision $KERNEL_SP11_REV) holds: $(sed -n 's/^CONFIG_LSM=//p' .config)"
  fi

  log "building kernel $KERNEL_ABI with $KERNEL_JOBS jobs (log: $KDIR/build.log)"
  export KBUILD_BUILD_USER=sp11 KBUILD_BUILD_HOST=fedora KBUILD_BUILD_VERSION=1
  make -j"$KERNEL_JOBS" CONFIG_DEBUG_SECTION_MISMATCH=y vmlinuz.efi modules dtbs >"$KDIR/build.log" 2>&1 \
    || { tail -50 "$KDIR/build.log" >&2; die "kernel build failed (see $KDIR/build.log)"; }
  [ -s arch/arm64/boot/vmlinuz.efi ] || die "vmlinuz.efi was not produced"

  log "staging payload"
  rm -rf "$PAYLOAD"; mkdir -p "$PAYLOAD/boot" "$PAYLOAD/usr/lib"
  make -s INSTALL_MOD_PATH="$PAYLOAD" INSTALL_MOD_STRIP=1 modules_install >>"$KDIR/build.log" 2>&1 || die "modules_install failed"
  if [ -d "$PAYLOAD/lib/modules" ] && [ ! -d "$PAYLOAD/usr/lib/modules" ]; then
    mv "$PAYLOAD/lib/modules" "$PAYLOAD/usr/lib/modules"; rmdir "$PAYLOAD/lib" 2>/dev/null || true
  fi
  [ -d "$MODDIR/kernel" ] || die "modules were not installed under $MODDIR"
  install -m 0755 arch/arm64/boot/vmlinuz.efi "$PAYLOAD/boot/vmlinuz-$KERNEL_ABI"
  install -m 0644 System.map "$PAYLOAD/boot/System.map-$KERNEL_ABI"
  install -m 0644 .config "$PAYLOAD/boot/config-$KERNEL_ABI"
  install -d "$MODDIR/dtb/qcom"
  for d in "$SP11_DTB" "$SP11_DTB_EXTRA"; do
    install -m 0644 "arch/arm64/boot/dts/$d" "$MODDIR/dtb/$d"
  done
  stage_common
}

build_from_prebuilt() {
  local img="$CACHE_DIR/$KERNEL_IMAGE_DEB" mod="$CACHE_DIR/$KERNEL_MODULES_DEB" tmp="$KDIR/deb"
  [ -s "$img" ] && [ -s "$mod" ] || die "missing kernel .deb files (run scripts/10-fetch-sources.sh with KERNEL_MODE=prebuilt)"
  rm -rf "$PAYLOAD" "$tmp"; mkdir -p "$PAYLOAD" "$tmp"
  local deb
  for deb in "$img" "$mod"; do
    ( cd "$tmp" && rm -f data.tar* && ar x "$deb" && tar -xf data.tar* -C "$PAYLOAD" ) || die "failed to unpack $deb"
  done
  [ -s "$PAYLOAD/boot/vmlinuz-$KERNEL_ABI" ] || die "vmlinuz missing in linux-image deb"
  [ -d "$MODDIR/kernel" ] || die "modules missing in linux-modules deb"
  check_config "$PAYLOAD/boot/config-$KERNEL_ABI"
  install -d "$MODDIR/dtb/qcom"
  for d in "$SP11_DTB" "$SP11_DTB_EXTRA"; do
    install -m 0644 "$PAYLOAD/usr/lib/firmware/$KERNEL_ABI/device-tree/$d" "$MODDIR/dtb/$d"
  done
  # Drop Ubuntu-only payload: full DTB tree under firmware/, modprobe blacklist, docs.
  rm -rf "$PAYLOAD/usr/lib/firmware" "$PAYLOAD/usr/lib/modprobe.d" "$PAYLOAD/usr/share"
  stage_common
}

case "$KERNEL_MODE" in
  build)    build_from_source ;;
  prebuilt) build_from_prebuilt ;;
  *) die "KERNEL_MODE must be 'build' or 'prebuilt'" ;;
esac

log "building kernel-sp11 RPM"
RPM=$(build_rpm "$SPEC_DIR/kernel-sp11.spec.in" kernel-sp11 "$KDIR" \
  ABI="$KERNEL_ABI" KVER="$KERNEL_BUILD_VERSION" KREL="$KERNEL_RPM_RELEASE" PAYLOAD="$PAYLOAD" \
  MODE="$KERNEL_MODE" COMMIT="$KERNEL_SOURCE_COMMIT" RELEASE_TAG="$KERNEL_RELEASE_TAG" \
  STABLE="${KERNEL_STABLE_VERSION:+, kernel.org stable patch-$KERNEL_STABLE_VERSION}" \
  POLICY="${KERNEL_SP11_REV:+, SP11 revision $KERNEL_SP11_REV: Fedora LSM stack, no Ubuntu-only modules$(
    for p in "$FILES_DIR/$KERNEL_PATCH_DIR"/*.patch; do [ -f "$p" ] && printf ', %s' "$(basename "$p" .patch)"; done)}")
rpm -qp --provides "$RPM" | grep -x 'kernel-uname-r' >/dev/null || die "RPM lacks kernel-uname-r provide"
rpm -qpl "$RPM" | grep -x "/boot/vmlinuz-$KERNEL_ABI" >/dev/null || die "RPM lacks /boot/vmlinuz-$KERNEL_ABI"
log "kernel RPM: $RPM ($(du -h "$RPM" | cut -f1))"
