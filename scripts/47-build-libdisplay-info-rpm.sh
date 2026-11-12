#!/usr/bin/bash
# Step 4f: build libdisplay-info with upstream's DisplayID v2 CTA-861 support. GNOME shows its HDR switch for the
# built-in panel only when the kernel's connector properties and the panel's EDID agree, and mutter reads the EDID
# through this library. The panel announces its BT.2020 colorimetry and its HDR static metadata in a CTA-861 data
# block inside its DisplayID v2 extension, which Fedora's 0.3.0 does not read (docs/display.md).
#   libdisplay-info   Fedora's own source RPM of the target release, rebuilt with the upstream commits in
#                     payload/display/libdisplay-info/
# Built in a mock buildroot of the target release, where upstream's test suite runs with the test those commits add
# for a panel of the same kind. The soname stays, so the RPM replaces Fedora's build in place and what links
# against the library (mutter, Mesa's Vulkan drivers) keeps working: the step compares the rebuild with Fedora's own
# binary RPM (files, requirements, capabilities, exported symbols). Idempotent: skipped while the RPM matches
# sp11.conf, refused when its inputs changed without a new suffix; FORCE=1 rebuilds.
. "$(dirname "$0")/lib.sh"
require_cmd rpmbuild mock rpm2cpio cpio rpm nm comm

SRPM_IN="$CACHE_DIR/$LIBDISPLAY_INFO_SRPM"; STOCK="$CACHE_DIR/$LIBDISPLAY_INFO_STOCK_RPM"
[ -s "$SRPM_IN" ] || die "missing $SRPM_IN (run scripts/10-fetch-sources.sh)"
[ -s "$STOCK" ] || die "missing $STOCK (run scripts/10-fetch-sources.sh)"
verify_sha256 "$SRPM_IN" "$LIBDISPLAY_INFO_SRPM_SHA256"
verify_sha256 "$STOCK" "$LIBDISPLAY_INFO_STOCK_SHA256"
VERSION=$(rpm -qp --qf '%{VERSION}' "$SRPM_IN"); FEDREL=$(rpm -qp --qf '%{RELEASE}' "$SRPM_IN")
BASEREL=${FEDREL%%.fc*}                                          # 2.fc45 -> 2
[ "$BASEREL" != "$FEDREL" ] || die "unexpected release '$FEDREL' in $LIBDISPLAY_INFO_SRPM"
[ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$STOCK")" = "$VERSION-$FEDREL" ] \
  || die "$LIBDISPLAY_INFO_STOCK_RPM is not the build of $LIBDISPLAY_INFO_SRPM"
# The template is Fedora's spec at the time of writing; a source RPM with patches needs it refreshed first.
[ -z "$(rpm -qp --qf '[%{PATCH}\n]' "$SRPM_IN" 2>/dev/null)" ] \
  || die "$LIBDISPLAY_INFO_SRPM carries patches: refresh rpm/libdisplay-info.spec.in from its spec first"

EXPECT="$VERSION-$BASEREL.$LIBDISPLAY_INFO_RPM_SUFFIX.fc$FEDORA_RELEASE"
PATCHES="$PAYLOAD_DIR/display/libdisplay-info"
ls "$PATCHES"/*.patch >/dev/null 2>&1 || die "no patches under $PATCHES"
# What the RPM is built from: the template, the patches and Fedora's source RPM. Recorded in the RPM's description;
# a rebuild of the same release from other inputs is refused, because dnf would not install it.
INPUTS=$(printf '%s\n' "LIBDISPLAY_INFO_SRPM_SHA256=$LIBDISPLAY_INFO_SRPM_SHA256" \
  | inputs_sha256 "$SPEC_DIR/libdisplay-info.spec.in" "$PATCHES")
recorded_inputs() { rpm -qp --qf '%{DESCRIPTION}' "$1" 2>/dev/null | sed -n 's/^Inputs: //p' | head -1 || true; }
current() { local r; r=$(rpm_of libdisplay-info); [ -n "$r" ] && [ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$r" 2>/dev/null)" = "$EXPECT" ]; }
if current && [ "$(recorded_inputs "$(rpm_of libdisplay-info)")" != "$INPUTS" ]; then
  die "the libdisplay-info patches, its spec template or its source RPM changed since $(basename "$(rpm_of libdisplay-info)") was built, but LIBDISPLAY_INFO_RPM_SUFFIX is still $LIBDISPLAY_INFO_RPM_SUFFIX: bump it in sp11.conf (dnf ignores a rebuild of the same release)"
fi

if [ "${FORCE:-0}" = 1 ] || ! current; then
  ## 1. Sources: Fedora's, out of its source RPM, plus the patches
  SRC="$WORK_DIR/libdisplay-info-src"; rm -rf "$SRC"; mkdir -p "$SRC"
  ( cd "$SRC" && rpm2cpio "$SRPM_IN" | cpio -idm --quiet ) || die "cannot unpack $LIBDISPLAY_INFO_SRPM"
  [ -s "$SRC/libdisplay-info-$VERSION.tar.xz" ] || die "$LIBDISPLAY_INFO_SRPM does not carry libdisplay-info-$VERSION.tar.xz"
  # The template is Fedora's spec plus the patches and the release suffix: a spec Fedora changed (a build
  # requirement, a file, a scriptlet) must be merged into the template, not built around from the frozen copy.
  [ "$(sha256_of "$SRC/libdisplay-info.spec")" = "$LIBDISPLAY_INFO_BASE_SPEC_SHA256" ] \
    || die "Fedora's libdisplay-info.spec in $LIBDISPLAY_INFO_SRPM differs from the one rpm/libdisplay-info.spec.in was derived from: diff $SRC/libdisplay-info.spec against the template, refresh it, then set LIBDISPLAY_INFO_BASE_SPEC_SHA256=$(sha256_of "$SRC/libdisplay-info.spec") in sp11.conf"
  rm -f "$SRC/libdisplay-info.spec"
  install -m 0644 "$PATCHES"/*.patch "$SRC/"   # applied by rpm/libdisplay-info.spec.in (%autosetup -S git -p1)

  ## 2. Rebuild in the target release's buildroot; upstream's tests run in %check
  SRPM=$(build_srpm "$SPEC_DIR/libdisplay-info.spec.in" libdisplay-info "$SRC" \
    VERSION="$VERSION" BASEREL="$BASEREL" SUFFIX="$LIBDISPLAY_INFO_RPM_SUFFIX" INPUTS="$INPUTS")
  mock_rebuild "$SRPM" libdisplay-info >/dev/null
  current || die "the rebuild did not produce libdisplay-info $EXPECT"
  # The test the patches add is the proof inside the build: a panel of the same kind, whose HDR data sits in the
  # DisplayID v2 extension only, decoded and read through the high-level lookups.
  BLOG="$WORK_DIR/mock-libdisplay-info/build.log"
  for t in decode-asus-ux3405 print-asus-ux3405; do
    grep -E "libdisplay-info:$t +OK" "$BLOG" >/dev/null || die "the build did not pass upstream's test $t (see $BLOG)"
  done
  grep -E '^Fail: +0 *$' "$BLOG" >/dev/null || die "upstream's test suite did not finish without a failure (see $BLOG)"
  log "upstream's tests in the build: $(grep -E '^Ok: ' "$BLOG" | tr -s ' ' | head -1 || true)"
else
  log "libdisplay-info RPM already built for Fedora $FEDORA_RELEASE: $(basename "$(rpm_of libdisplay-info)"); checking it (FORCE=1 to rebuild)"
fi
RPM=$(rpm_of libdisplay-info)
[ "$(recorded_inputs "$RPM")" = "$INPUTS" ] || die "$(basename "$RPM") does not record the inputs it was built from"

## 3. A drop-in for Fedora's build: the same files and requirements, every capability and every exported symbol of
##    Fedora's, plus the three functions the DisplayID v2 support adds.
T="$WORK_DIR/libdisplay-info-check"; rm -rf "$T"; mkdir -p "$T"
LIB="./usr/lib64/libdisplay-info.so.$VERSION"
files() { rpm -qpl "$1" | grep -v '^/usr/lib/\.build-id' | sort; }
cmp -s <(files "$STOCK") <(files "$RPM") \
  || die "$(basename "$RPM") does not carry the files of Fedora's build: $(comm -3 <(files "$STOCK") <(files "$RPM") | tr -s '\t\n' '  ')"
reqs() { rpm -qp --requires "$1" | sort -u; }
cmp -s <(reqs "$STOCK") <(reqs "$RPM") \
  || die "$(basename "$RPM") requires something else than Fedora's build: $(comm -3 <(reqs "$STOCK") <(reqs "$RPM") | tr -s '\t\n' '  ')"
caps() { rpm -qp --provides "$1" | grep -E '\.so\.[0-9]+\(' | sort -u || true; }
[ -n "$(caps "$STOCK")" ] || die "$LIBDISPLAY_INFO_STOCK_RPM provides no shared library"
[ -z "$(comm -23 <(caps "$STOCK") <(caps "$RPM"))" ] \
  || die "$(basename "$RPM") lacks a library Fedora's build provides: $(comm -23 <(caps "$STOCK") <(caps "$RPM") | tr '\n' ' ')"
syms() { rpm2cpio "$1" | cpio -i --quiet --to-stdout "$LIB" > "$T/lib.so" && nm -D --defined-only "$T/lib.so" | awk '{print $3}' | sort -u; }
syms "$STOCK" > "$T/stock.syms"; syms "$RPM" > "$T/sp11.syms"
[ -s "$T/stock.syms" ] && [ -s "$T/sp11.syms" ] || die "cannot read the exported symbols of $LIB"
[ -z "$(comm -23 "$T/stock.syms" "$T/sp11.syms")" ] \
  || die "$(basename "$RPM") lacks symbols Fedora's build exports: $(comm -23 "$T/stock.syms" "$T/sp11.syms" | tr '\n' ' ')"
for s in di_displayid2_get_data_blocks di_displayid2_data_block_get_tag di_displayid2_data_block_get_cta_data_blocks; do
  grep -x "$s" "$T/sp11.syms" >/dev/null || die "$(basename "$RPM") was built without the DisplayID v2 data blocks (no $s)"
done
log "libdisplay-info RPM: $(basename "$RPM") ($(wc -l < "$T/sp11.syms") exported symbols, Fedora's $(wc -l < "$T/stock.syms"); added: $(comm -13 "$T/stock.syms" "$T/sp11.syms" | tr '\n' ' '))"
rm -rf "$T"

## 4. Prove it replaces Fedora's build in the live root and reads a panel's HDR data there.
if as_root test -d "$WORK_DIR/iso/rootfs/usr/lib/modules"; then
  "$(dirname "$0")/48-verify-libdisplay-info-rpm.sh" || die "48-verify-libdisplay-info-rpm.sh failed"
else
  warn "no extracted live root, so the RPM was not verified; run scripts/48-verify-libdisplay-info-rpm.sh after scripts/50-build-iso.sh"
fi
