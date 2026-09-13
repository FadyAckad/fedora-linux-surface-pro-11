#!/usr/bin/bash
# Step 3: produce the kernel-sp11 RPM (kernel image, modules, Denali DTBs).
#   KERNEL_MODE=build    compile natively from ooaklee's source tarball with ooaklee's annotations config
#   KERNEL_MODE=prebuilt repackage ooaklee's released .deb payload
. "$(dirname "$0")/lib.sh"
require_cmd make gcc python3 depmod tar ar rpmbuild zstd

KDIR="$BUILD_DIR/kernel"
PAYLOAD="$KDIR/payload"
MODDIR="$PAYLOAD/usr/lib/modules/$KERNEL_ABI"
mkdir -p "$KDIR"

if [ -n "$(rpm_of kernel-sp11)" ] && [ "${FORCE:-0}" != 1 ]; then
  log "kernel RPM already built: $(rpm_of kernel-sp11) (FORCE=1 to rebuild)"; exit 0
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
  local dtb_compat
  dtb_compat=$(fdtget -t s "$MODDIR/dtb/$SP11_DTB" / compatible 2>/dev/null || true)
  [[ $dtb_compat == *microsoft,denali-oled* ]] || die "DTB compatible check failed: '$dtb_compat'"
  log "payload staged: $(du -sh "$PAYLOAD" | cut -f1), $(find "$MODDIR/kernel" -name '*.ko*' | wc -l) modules, DTB compatible: $dtb_compat"
}

build_from_source() {
  local tarball="$CACHE_DIR/$KERNEL_SOURCE_TARBALL" src="$KDIR/src/linux-$KERNEL_SOURCE_COMMIT"
  [ -s "$tarball" ] || die "missing $tarball (run scripts/10-fetch-sources.sh)"
  if [ ! -f "$src/Makefile" ]; then
    log "extracting kernel source"; mkdir -p "$KDIR/src"; tar -xzf "$tarball" -C "$KDIR/src"
  fi
  [ -f "$src/debian.$KERNEL_FLAVOUR/config/annotations" ] || die "no debian.$KERNEL_FLAVOUR/config/annotations in source"
  cd "$src"
  local localversion="${KERNEL_ABI#"$KERNEL_UPSTREAM_VERSION"}"   # e.g. -jg-0sp11v23-qcom-x1e

  log "generating .config from ooaklee's annotations (arch arm64, flavour $KERNEL_FLAVOUR)"
  python3 debian/scripts/misc/annotations --file "debian.$KERNEL_FLAVOUR/config/annotations" \
    --arch arm64 --flavour "$KERNEL_FLAVOUR" --export > .config || die "annotations export failed"
  # Identity: Ubuntu's packaging injects the ABI at build time; reproduce it through LOCALVERSION.
  scripts/config --set-str LOCALVERSION "$localversion"
  scripts/config --disable LOCALVERSION_AUTO
  scripts/config --set-str VERSION_SIGNATURE "SP11 $KERNEL_ABI (ooaklee ${KERNEL_SOURCE_COMMIT:0:12}, built on Fedora $FEDORA_RELEASE)"
  scripts/config --disable CRYPTO_FIPS
  make -s olddefconfig
  [ "$(make -s kernelrelease)" = "$KERNEL_ABI" ] || die "kernelrelease '$(make -s kernelrelease)' != '$KERNEL_ABI'"
  check_config .config

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
  ABI="$KERNEL_ABI" KVER="$KERNEL_UPSTREAM_VERSION" KREL="$KERNEL_RPM_RELEASE" PAYLOAD="$PAYLOAD" \
  MODE="$KERNEL_MODE" COMMIT="$KERNEL_SOURCE_COMMIT" RELEASE_TAG="$KERNEL_RELEASE_TAG")
rpm -qp --provides "$RPM" | grep -x 'kernel-uname-r' >/dev/null || die "RPM lacks kernel-uname-r provide"
rpm -qpl "$RPM" | grep -x "/boot/vmlinuz-$KERNEL_ABI" >/dev/null || die "RPM lacks /boot/vmlinuz-$KERNEL_ABI"
log "kernel RPM: $RPM ($(du -h "$RPM" | cut -f1))"
