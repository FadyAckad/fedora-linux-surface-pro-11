#!/usr/bin/bash
# Step 3: build the SP11 kernel packages from Fedora's own kernel source RPM (KERNEL_SRPM, pinned in sp11.conf) with
# the SP11 patch set (the kernel fork's pinned commits as step 10 writes them out, applied by kernel.spec as
# linux-kernel-test.patch) and configuration additions (files/$KERNEL_CONFIG_FRAGMENT, kernel.spec's kernel-local),
# under buildid .sp11.<KERNEL_SP11_REV>. The result is Fedora's kernel package family, built in a mock buildroot of
# the target release; nothing else about Fedora's kernel changes.
. "$(dirname "$0")/lib.sh"
require_cmd rpm rpmbuild rpm2cpio cpio mock fdtget dtc modinfo depmod python3 zstd sha256sum

KDIR="$BUILD_DIR/kernel"
SRPM_IN="$CACHE_DIR/$KERNEL_SRPM"
mkdir -p "$KDIR"

# The declared revision must be the content sp11.conf pins for it: kernel-core is install-only, and the same uname
# rebuilt with another patch set or fragment would collide with the installed package instead of replacing it.
REV_SHA=$(kernel_rev_sha256)
[ "$REV_SHA" = "${KERNEL_SP11_REV_SHA256:-}" ] \
  || die "files/$KERNEL_CONFIG_FRAGMENT and KERNEL_PATCH_COMMIT do not match SP11 revision $KERNEL_SP11_REV (KERNEL_SP11_REV_SHA256 in sp11.conf); a changed patch set or fragment needs a new revision: bump KERNEL_SP11_REV and set KERNEL_SP11_REV_SHA256=$REV_SHA"

[ -s "$SRPM_IN" ] || die "missing $SRPM_IN (run scripts/10-fetch-sources.sh)"
verify_sha256 "$SRPM_IN" "$KERNEL_SRPM_SHA256"

## Checks on the kernel packages (after a build and on a cached build alike): every package the live media installs
## at the configured uname, the device tree, the configuration against Fedora's, the SP11 modules and parameters.
check_kernel_rpms() {
  local STOCK="$CACHE_DIR/$KERNEL_STOCK_CORE_RPM" STOCK_CONFIG="$KDIR/config-$KERNEL_FEDORA_VERSION-$KERNEL_FEDORA_RELEASE.fc$FEDORA_RELEASE"
  [ -s "$STOCK" ] || die "missing $STOCK (run scripts/10-fetch-sources.sh)"
  verify_sha256 "$STOCK" "$KERNEL_STOCK_CORE_SHA256"
  # rpm2cpio names files ./...; cpio extracts nothing, silently, for a pattern without the ./
  rpm2cpio "$STOCK" | cpio -i --quiet --to-stdout "./lib/modules/$KERNEL_FEDORA_VERSION-$KERNEL_FEDORA_RELEASE.fc$FEDORA_RELEASE.$FEDORA_ARCH/config" >"$STOCK_CONFIG" || true
  [ -s "$STOCK_CONFIG" ] || die "cannot read the configuration of $KERNEL_STOCK_CORE_RPM"
  for p in $KERNEL_PKGS; do
    r=$(rpm_of "$p")
    [ -n "$r" ] && [ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$r")" = "$KERNEL_ABI" ] || die "no $p RPM for $KERNEL_ABI"
  done
  CHK="$KDIR/check"
  rm -rf "$CHK"; mkdir -p "$CHK"
  for p in $KERNEL_PKGS; do ( cd "$CHK" && rpm2cpio "$(rpm_of "$p")" | cpio -idm --quiet ) || die "cannot unpack $p"; done
  MOD="$CHK/lib/modules/$KERNEL_ABI"; [ -d "$MOD" ] || MOD="$CHK/usr/lib/modules/$KERNEL_ABI"
  [ -s "$MOD/vmlinuz" ] || die "kernel-core lacks lib/modules/$KERNEL_ABI/vmlinuz"
  [ -s "$MOD/dtb/$SP11_DTB" ] || die "kernel-core lacks the device tree $SP11_DTB"
  dtb_compat=$(fdtget -t s "$MOD/dtb/$SP11_DTB" / compatible 2>/dev/null || true)
  [[ $dtb_compat == *microsoft,denali-oled* ]] || die "DTB compatible check failed: '$dtb_compat'"
  # By compatible: the node's path depends on the SoC dtsi (spi10 sits under the QUP wrapper, /soc@0/geniqup@ac0000).
  dtc -q -I dtb -O dts "$MOD/dtb/$SP11_DTB" | grep -F 'compatible = "microsoft,mshw0485";' >/dev/null \
    || die "the SP11 device tree lacks the touch controller (patch set not applied?)"
  # Every enabled user of the RPMh power domains and of the interconnect in that tree has a driver in the packages:
  # otherwise those providers never reach sync_state and Linux keeps its boot-time maximum rail and bus votes for
  # good, and the CDSP never wakes from its first sleep (kernel-local enables the drivers Fedora leaves out).
  local moddir=${MOD#"$CHK"}; moddir=${moddir%/"$KERNEL_ABI"}
  depmod -b "$CHK" -m "$moddir" -o "$CHK/depmod" "$KERNEL_ABI" || die "depmod failed on the kernel packages"
  missing=$(python3 "$SP11_ROOT/scripts/sync-state-drivers.py" "$MOD/dtb/$SP11_DTB" "$MOD/vmlinuz" \
            "$CHK/depmod$moddir/$KERNEL_ABI/modules.alias" "$MOD/modules.builtin.modinfo") \
    || die "no driver for these users of the RPMh power domains or the interconnect; add it to kernel-local: $(printf '%s\n' "$missing" | tr '\n' ';')"
  # The configuration is the one Fedora shipped in the same build, plus exactly the kernel-local lines; only the build's
  # identity and the values Kconfig derives from the toolchain of the buildroot may differ.
  config_fragment_holds "$FILES_DIR/$KERNEL_CONFIG_FRAGMENT" "$MOD/config" || die "kernel-local did not survive Fedora's configuration processing"
  settings() { grep -E '^(CONFIG_[A-Za-z0-9_]+=|# CONFIG_[A-Za-z0-9_]+ is not set$)' "$1" \
    | grep -vE '^(# )?CONFIG_(BUILD_SALT|CC_VERSION_TEXT|GCC_VERSION|CLANG_VERSION|AS_VERSION|LD_VERSION|LLD_VERSION|PAHOLE_VERSION|RUSTC_VERSION|RUSTC_VERSION_TEXT|RUSTC_LLVM_VERSION|RUSTC_LLVM_MAJOR_VERSION|BINDGEN_VERSION_TEXT|CC_IS_[A-Z_]+|AS_IS_[A-Z_]+|LD_IS_[A-Z_]+|CC_CAN_[A-Z0-9_]+|CC_HAS_[A-Z0-9_]+|AS_HAS_[A-Z0-9_]+|LD_CAN_[A-Z0-9_]+|TOOLS_SUPPORT_[A-Z0-9_]+|RUSTC_HAS_[A-Z0-9_]+|PAHOLE_HAS_[A-Z0-9_]+)[= ]' | sort; }
  # Expected: kernel-local's lines ('>') and Fedora's own value of each symbol kernel-local overrides ('<').
  delta=$(diff <(settings "$STOCK_CONFIG") <(settings "$MOD/config") | grep -E '^[<>]' \
          | grep -vxF -f <(grep -E '^(CONFIG_|# CONFIG_)' "$FILES_DIR/$KERNEL_CONFIG_FRAGMENT" | sed 's/^/> /') \
          | grep -vE -f <(sed -nE 's/^(# )?(CONFIG_[A-Za-z0-9_]+)(=.*| is not set)$/^< (# )?\2( is not set|=)/p' \
                            "$FILES_DIR/$KERNEL_CONFIG_FRAGMENT") || true)
  [ -z "$delta" ] || die "the configuration differs from Fedora's $KERNEL_STOCK_CORE_RPM beyond kernel-local ('<' Fedora, '>' SP11): $(printf '%s\n' "$delta" | tr '\n' ';')"
  for m in mshw0485_touch soundwire-qcom snd-soc-wsa884x surface_aggregator_registry; do
    find "$MOD" -name "$m.ko*" | grep . >/dev/null || die "module $m missing from the kernel packages"
  done
  # The parameters the SP11 userspace relies on: the pen's HIDRAW bridge and the SoundWire argument on the command line.
  modinfo -F parm "$(find "$MOD" -name 'mshw0485_touch.ko*' | head -1)" | grep '^ipts_hid_bridge:' >/dev/null \
    || die "mshw0485_touch has no ipts_hid_bridge parameter"
  modinfo -F parm "$(find "$MOD" -name 'soundwire-qcom.ko*' | head -1)" | grep '^sp11_feedback_active_offset2_zero:' >/dev/null \
    || die "soundwire-qcom has no sp11_feedback_active_offset2_zero parameter"
  log "kernel $KERNEL_ABI: configuration = Fedora's ${KERNEL_STOCK_CORE_RPM%.rpm} + kernel-local; DTB compatible: $dtb_compat"
  rm -rf "$CHK"
}

CACHED=$(rpm_of kernel-core)
if [ -n "$CACHED" ] && [ "${FORCE:-0}" != 1 ]; then
  if [ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$CACHED" 2>/dev/null)" = "$KERNEL_ABI" ]; then
    log "kernel RPMs already built: $(basename "$CACHED") and its family (FORCE=1 to rebuild); checking them"
    check_kernel_rpms; exit 0
  fi
  log "cached $(basename "$CACHED") is not kernel $KERNEL_ABI; rebuilding"
fi

## 1. Fedora's sources plus the SP11 additions, in the slots kernel.spec provides for local builds
SRC="$KDIR/sources"
rm -rf "$SRC"; mkdir -p "$SRC"
( cd "$SRC" && rpm2cpio "$SRPM_IN" | cpio -idm --quiet ) || die "cannot unpack $KERNEL_SRPM"
for f in kernel.spec linux-kernel-test.patch kernel-local "kernel-$FEDORA_ARCH-fedora.config"; do
  [ -f "$SRC/$f" ] || die "$KERNEL_SRPM has no $f (kernel.spec layout changed?)"
done
[ ! -s "$SRC/linux-kernel-test.patch" ] || die "$KERNEL_SRPM ships a non-empty linux-kernel-test.patch"
[ -f "$KERNEL_PATCH_SERIES/.complete" ] || die "missing the SP11 patch series of $KERNEL_PATCH_COMMIT (run scripts/10-fetch-sources.sh)"
kernel_series_check || die "the SP11 series in $KERNEL_PATCH_SERIES does not rebuild the tree of $KERNEL_PATCH_COMMIT"
cat "$KERNEL_PATCH_SERIES"/*.patch > "$SRC/linux-kernel-test.patch"
[ "$(wc -l < "$SRC/linux-kernel-test.patch")" -gt 9 ] || die "the patch set is empty (kernel.spec ignores a test patch of 9 lines or fewer)"
cp "$FILES_DIR/$KERNEL_CONFIG_FRAGMENT" "$SRC/kernel-local"
[ "$(grep -c '^# define buildid \.local$' "$SRC/kernel.spec")" = 1 ] || die "kernel.spec has no single '# define buildid .local' line"
sed -i "s/^# define buildid \.local\$/%define buildid $KERNEL_BUILDID/" "$SRC/kernel.spec"
log "Fedora $KERNEL_SRPM + $(find "$KERNEL_PATCH_SERIES" -name '*.patch' | wc -l) SP11 patches (${KERNEL_PATCH_COMMIT:0:12}) + kernel-local, buildid $KERNEL_BUILDID"

## 2. Source RPM, then the binary packages in a buildroot of the target release
TOP="$KDIR/rpmbuild"
rm -rf "$TOP"; mkdir -p "$TOP"/{BUILD,SRPMS}
rpmbuild -bs --define "_topdir $TOP" --define "_sourcedir $SRC" --define "_srcrpmdir $TOP/SRPMS" \
  --define "dist .fc$FEDORA_RELEASE" --define "fedora $FEDORA_RELEASE" "$SRC/kernel.spec" >"$KDIR/srpm.log" 2>&1 \
  || { tail -20 "$KDIR/srpm.log" >&2; die "rpmbuild -bs failed (log: $KDIR/srpm.log)"; }
SP11_SRPM="$TOP/SRPMS/kernel-$KERNEL_FEDORA_VERSION-$KERNEL_RPM_RELEASE.src.rpm"
[ -s "$SP11_SRPM" ] || die "rpmbuild -bs did not produce $(basename "$SP11_SRPM"): $(ls "$TOP/SRPMS")"
# shellcheck disable=SC2086 # KERNEL_MOCK_OPTS is a list of options
mapfile -t BUILT < <(mock_rebuild_family "$SP11_SRPM" sp11-kernel $KERNEL_MOCK_OPTS)
log "built: $(printf '%s ' "${BUILT[@]##*/}")"
check_kernel_rpms
