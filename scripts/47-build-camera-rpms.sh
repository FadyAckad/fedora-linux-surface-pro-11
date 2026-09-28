#!/usr/bin/bash
# Step 4f: build the camera userspace of the installed system: Fedora's own libcamera source RPM of the target
# release, rebuilt in a mock buildroot of that release with the patches of payload/camera/ (the Surface Pro 11's
# front camera, a Sony IMX681: sensor properties, analogue gain and black-level helper, tuning file of the simple
# pipeline's software ISP, from turbineBMW/surface-pro-11-linux and rebased onto Fedora's version; the software
# ISP's exposure control converging faster and adding digital gain, from Robert Bozik and backported, with an
# analogue-gain bound; the tuning of both cameras) and with the IPA modules re-signed in the directory Fedora's spec
# installs them to. The kernel side (CAMSS, the sensors, the Denali camera nodes) is part of the SP11 patch set; see
# docs/camera.md. Step 50 installs the rebuild in place of Fedora's. Idempotent: skipped while the RPMs match
# sp11.conf and were built from the same inputs; FORCE=1 rebuilds.
. "$(dirname "$0")/lib.sh"
require_cmd rpmbuild mock rpm2cpio cpio rpm openssl python3 cmp strings git

LC_SRPM="$CACHE_DIR/$LIBCAMERA_SRPM"
[ -s "$LC_SRPM" ] || die "missing $LC_SRPM (run scripts/10-fetch-sources.sh)"
verify_sha256 "$LC_SRPM" "$LIBCAMERA_SRPM_SHA256"
LC_VERSION=$(rpm -qp --qf '%{VERSION}' "$LC_SRPM" 2>/dev/null); LC_FEDREL=$(rpm -qp --qf '%{RELEASE}' "$LC_SRPM" 2>/dev/null)
LC_BASEREL=${LC_FEDREL%%.fc*}                                        # 3.fc45 -> 3
[ "$LC_BASEREL" != "$LC_FEDREL" ] || die "unexpected release '$LC_FEDREL' in $(basename "$LC_SRPM")"
EXPECT="$LC_VERSION-$LC_BASEREL.$LIBCAMERA_RPM_SUFFIX.fc$FEDORA_RELEASE"
# Every binary package Fedora's spec builds; libcamera, libcamera-ipa and libcamera-tools are the ones a machine needs
# (the others are handed over for a system that has Fedora's build of them installed).
LC_PKGS="libcamera libcamera-devel libcamera-ipa libcamera-tools libcamera-qcam libcamera-gstreamer libcamera-v4l2 python3-libcamera"
PATCHES=$(find "$PAYLOAD_DIR/camera" -maxdepth 1 -name '*.patch' | LC_ALL=C sort)
[ -n "$PATCHES" ] || die "no patches under $PAYLOAD_DIR/camera"
# %autosetup applies only the patches the spec declares, while the inputs below cover every file: a patch without a
# Patch line would be built into the inputs but never into the packages. (A declared file that is missing stops
# rpmbuild by itself.)
for p in $PATCHES; do
  awk -v n="${p##*/}" '$1 ~ /^Patch[0-9]+:$/ && $2 == n { f = 1 } END { exit !f }' "$SPEC_DIR/libcamera.spec.in" \
    || die "${p##*/} has no Patch line in rpm/libcamera.spec.in, so %autosetup would not apply it"
done

# What the packages are built from: the patches, the spec template, the source RPM and the suffix. Recorded in the
# main package's description; a same-release rebuild from other inputs is refused, because dnf would not install it.
INPUTS=$(printf '%s\n' "SRPM=$(basename "$LC_SRPM")" "SUFFIX=$LIBCAMERA_RPM_SUFFIX" \
  | inputs_sha256 "$SPEC_DIR/libcamera.spec.in" $PATCHES)
have() { local r; r=$(rpm_of "$1"); [ -n "$r" ] && [ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$r" 2>/dev/null)" = "$EXPECT" ]; }
recorded_inputs() { rpm -qp --qf '%{DESCRIPTION}' "$1" 2>/dev/null | sed -n 's/^Inputs: //p' | head -1 || true; }
if have libcamera; then
  rec=$(recorded_inputs "$(rpm_of libcamera)")
  [ "$rec" = "$INPUTS" ] \
    || die "rpm/libcamera.spec.in, payload/camera/ or the source RPM changed since $(basename "$(rpm_of libcamera)") was built, but LIBCAMERA_RPM_SUFFIX is still $LIBCAMERA_RPM_SUFFIX: bump it in sp11.conf (dnf ignores a same-release rebuild)"
fi
all_current() { local p; for p in $LC_PKGS; do have "$p" || return 1; done; }

## 1. The source RPM (its pinned checksum verified above) and the spec the template was derived from.
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CDIR="$BUILD_DIR/camera"; SRC="$CDIR/SOURCES"
rm -rf "$SRC"; mkdir -p "$SRC"
( cd "$SRC" && rpm2cpio "$LC_SRPM" | cpio -idm --quiet ) || die "cannot unpack $(basename "$LC_SRPM")"
[ -s "$SRC/libcamera-v$LC_VERSION.tar.bz2" ] || die "$(basename "$LC_SRPM") does not carry libcamera-v$LC_VERSION.tar.bz2"
[ "$(sha256_of "$SRC/libcamera.spec")" = "$LIBCAMERA_BASE_SPEC_SHA256" ] \
  || die "Fedora's libcamera.spec in $(basename "$LC_SRPM") differs from the one rpm/libcamera.spec.in was derived from: diff $SRC/libcamera.spec against the template, refresh it (and rebase payload/camera/ onto the new version), then set LIBCAMERA_BASE_SPEC_SHA256=$(sha256_of "$SRC/libcamera.spec") in sp11.conf"
rm -f "$SRC/libcamera.spec"
for p in $PATCHES; do install -m 0644 "$p" "$SRC/"; done

## 2. The packages, in the target release's buildroot.
if [ "${FORCE:-0}" = 1 ] || ! all_current; then
  SRPM=$(build_srpm "$SPEC_DIR/libcamera.spec.in" libcamera "$SRC" \
    VERSION="$LC_VERSION" BASEREL="$LC_BASEREL" SUFFIX="$LIBCAMERA_RPM_SUFFIX" INPUTS="$INPUTS")
  mock_rebuild_family "$SRPM" libcamera >/dev/null
  all_current || die "the mock build did not produce every one of $LC_PKGS at $EXPECT"
else
  log "libcamera RPMs are current ($EXPECT); skipping the mock build (FORCE=1 to rebuild)"
fi
RPM_LC=$(rpm_of libcamera); RPM_IPA=$(rpm_of libcamera-ipa); RPM_TOOLS=$(rpm_of libcamera-tools)
[ "$(recorded_inputs "$RPM_LC")" = "$INPUTS" ] || die "$(basename "$RPM_LC") does not record the inputs it was built from"

## 3. What the rebuild is for, in the packages: the IMX681 in the core library (sensor properties) and in the simple
##    IPA (gain and black-level helper), the exposure control's tuning parameters in the simple IPA, the whole-quad
##    downscaling in the GPU debayering's shader, every tuning file as the patches leave it, and IPA signatures
##    that verify against the key built into libcamera.so, so libcamera runs the IPA in its own process instead
##    of isolated.
X="$T/x"; mkdir -p "$X"
for r in "$RPM_LC" "$RPM_IPA"; do ( cd "$X" && rpm2cpio "$r" | cpio -idm --quiet ) || die "cannot unpack $(basename "$r")"; done
SO="$X/usr/lib64/libcamera.so.$LC_VERSION"
[ -f "$SO" ] || die "$(basename "$RPM_LC") lacks /usr/lib64/libcamera.so.$LC_VERSION"
grep -a -x imx681 < <(strings -n 6 "$SO") >/dev/null || die "libcamera.so does not know the IMX681 (sensor properties missing)"
grep -a -x imx681 < <(strings -n 6 "$X/usr/lib64/libcamera/ipa/ipa_soft_simple.so") >/dev/null \
  || die "ipa_soft_simple.so does not know the IMX681 (camera sensor helper missing)"
for k in maxDigitalGain maxAnalogueGain exposureTarget; do
  grep -a -x "$k" < <(strings -n 6 "$X/usr/lib64/libcamera/ipa/ipa_soft_simple.so") >/dev/null \
    || die "ipa_soft_simple.so does not read the $k tuning parameter (exposure control patches missing)"
done
# The GPU debayering's shaders are compiled into libcamera.so as text.
grep -a -F 'vec3 quad_rgb(vec2 pixel)' < <(strings -n 6 "$SO") >/dev/null \
  || die "libcamera.so's packed Bayer shader lacks quad_rgb() (whole-quad downscaling patch missing)"
# The tuning files as the patches leave them: their hunks alone, applied in order outside any repository.
mkdir -p "$T/tuning"
for p in $PATCHES; do
  ( cd "$T/tuning" && git apply --include='src/ipa/simple/data/*.yaml' "$p" ) \
    || die "cannot apply the tuning-file hunks of $(basename "$p")"
done
n=0
for y in "$T"/tuning/src/ipa/simple/data/*.yaml; do
  [ -e "$y" ] || continue
  f=/usr/share/libcamera/ipa/simple/$(basename "$y")
  [ -f "$X$f" ] || die "$(basename "$RPM_IPA") lacks $f"
  cmp -s "$y" "$X$f" || die "the installed $f differs from the one payload/camera/ leaves"
  n=$((n + 1))
done
[ "$n" -ge 2 ] || die "payload/camera/ leaves $n tuning files, expected the IMX681's and the OV13858's"
ipa_signatures_ok "$SO" "$X/usr/lib64/libcamera/ipa" || die "IPA module signatures do not verify against the key in libcamera.so"
log "libcamera RPMs: $(for p in $LC_PKGS; do basename "$(rpm_of "$p")"; done | tr '\n' ' ')($(du -ch $(for p in $LC_PKGS; do rpm_of "$p"; done) | tail -1 | cut -f1))"

## 4. Prove the packages install into the live root and hold together with Fedora's camera packages there.
if as_root test -d "$WORK_DIR/iso/rootfs/usr/lib/modules"; then
  "$(dirname "$0")/48-verify-camera-rpms.sh" || die "48-verify-camera-rpms.sh failed"
else
  warn "no extracted live root, so the RPMs were not verified; run scripts/48-verify-camera-rpms.sh after scripts/50-build-iso.sh"
fi
