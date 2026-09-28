#!/usr/bin/bash
# Step 4g: prove the camera RPMs (scripts/47) install into the live root the way `dnf install` does on the installed
# system and hold together with Fedora's camera packages there: libcamera, libcamera-ipa and libcamera-tools replace
# Fedora's build in one transaction, PipeWire's libcamera plugin still resolves the library, the tuning files of
# both cameras are in place and parse, and the IPA modules' signatures verify against the installed library's key.
# Runs in an overlay of the extracted live root, so the cached root is never modified. What only the device can show
# (the sensors, the picture, the privacy LED) is left to the device steps.
. "$(dirname "$0")/lib.sh"
require_cmd rpm findmnt openssl python3

BASE="$WORK_DIR/iso/rootfs"
as_root test -d "$BASE/usr/lib/modules" || die "no extracted live root at $BASE (run scripts/50-build-iso.sh first)"
declare -a RPMS=()
for n in libcamera libcamera-ipa libcamera-tools; do
  r=$(rpm_of "$n"); [ -n "$r" ] || die "no $n RPM in $RPM_DIR (run scripts/47-build-camera-rpms.sh)"; RPMS+=("$r")
done
VER=$(rpm -qp --qf '%{VERSION}' "${RPMS[0]}"); EVR=$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "${RPMS[0]}")
PREV=$(as_root rpm --root "$BASE" -q libcamera 2>/dev/null || true)

T="$WORK_DIR/verify-camera"; M="$T/merged"
fail=0
check() { if "$@" >/dev/null 2>&1; then log "  ok: $*"; else warn "  FAIL: $*"; fail=1; fi; }
inroot() { as_root chroot "$M" "$@"; }
teardown() {
  # A cgroup submount under the bound /sys can refuse a recursive unmount; detach lazily rather than leave it.
  for m in dev proc sys; do as_root umount -R "$M/$m" 2>/dev/null || as_root umount -lR "$M/$m" 2>/dev/null || true; done
  as_root umount "$M" 2>/dev/null || as_root umount -l "$M" 2>/dev/null || true
  if [ -z "$(mounts_under "$T")" ]; then as_root rm -rf --one-file-system "$T"; else
    warn "mounts left under $T: $(mounts_under "$T" | tr '\n' ' ')"; fi
}
setup_overlay() {
  teardown
  as_root mkdir -p "$T"/upper "$T"/work "$M"
  as_root mount -t overlay overlay -o "lowerdir=$BASE,upperdir=$T/upper,workdir=$T/work" "$M"
  for m in dev proc sys; do as_root mount --rbind "/$m" "$M/$m"; as_root mount --make-rslave "$M/$m"; done
  as_root install -d "$M/tmp/camera"
}
# Copies RPMs into the chroot; prints their chroot-side paths.
stage_rpms() { local f; for f in "$@"; do as_root cp "$f" "$M/tmp/camera/"; echo "/tmp/camera/$(basename "$f")"; done; }
trap teardown EXIT
setup_overlay
declare -a IN=(); mapfile -t IN < <(stage_rpms "${RPMS[@]}")

## 1. Install as dnf would: the dependency check, then the transaction that replaces Fedora's build (on a root that
##    already carries this build, a reinstall).
log "--- install into an overlay of the live root (${PREV:-no libcamera installed}): ${#RPMS[@]} camera RPMs"
inroot /usr/bin/rpm -U --test --replacepkgs --define '_pkgverify_level none' "${IN[@]}" \
  || die "the camera RPMs have unmet dependencies in the live root (see above)"
inroot /usr/bin/rpm -U --replacepkgs --define '_pkgverify_level none' "${IN[@]}" || die "rpm -U of the camera RPMs failed in the chroot"
for n in libcamera libcamera-ipa libcamera-tools; do
  check as_root sh -c "chroot '$M' /usr/bin/rpm -q --qf '%{VERSION}-%{RELEASE}' $n | grep -x '$EVR'"
done

## 2. Linkage: the library, the IPA, the tools and PipeWire's plugin (Fedora's, built against Fedora's library).
log "--- linkage"
for b in /usr/lib64/libcamera.so.$VER /usr/lib64/libcamera/ipa/ipa_soft_simple.so /usr/bin/cam; do
  check as_root test -e "$M$b"
  check as_root sh -c "chroot '$M' /usr/bin/ldd '$b' >/dev/null && ! chroot '$M' /usr/bin/ldd '$b' | grep -q 'not found'"
done
if inroot /usr/bin/rpm -q pipewire-plugin-libcamera >/dev/null 2>&1; then
  spa=$(inroot /usr/bin/rpm -ql pipewire-plugin-libcamera | grep -E '/libspa-libcamera\.so$' | head -1 || true)
  check test -n "$spa"
  check as_root sh -c "chroot '$M' /usr/bin/ldd '$spa' | grep -q 'libcamera.so.0' && ! chroot '$M' /usr/bin/ldd '$spa' | grep -q 'not found'"
else
  warn "the live root has no pipewire-plugin-libcamera; desktop applications would not see the cameras"
fi
check as_root sh -c "chroot '$M' /usr/bin/cam --help 2>&1 | grep -q -- '--camera'"

## 3. What the rebuild is for: the IMX681 in the core and the simple IPA, its tuning file, valid IPA signatures.
log "--- IMX681 support and IPA signatures"
check as_root sh -c "strings -n 6 '$M/usr/lib64/libcamera.so.$VER' | grep -qx imx681"
check as_root sh -c "strings -n 6 '$M/usr/lib64/libcamera/ipa/ipa_soft_simple.so' | grep -qx imx681"
check as_root sh -c "strings -n 6 '$M/usr/lib64/libcamera.so.$VER' | grep -qF 'vec3 quad_rgb(vec2 pixel)'"
check as_root grep -q '^      blackLevel: 4096$' "$M/usr/share/libcamera/ipa/simple/imx681.yaml"
check as_root grep -q '^      blackLevel: 4096$' "$M/usr/share/libcamera/ipa/simple/ov13858.yaml"
check as_root test -f "$M/usr/share/libcamera/ipa/simple/uncalibrated.yaml"
# Both cameras' files parse, and their exposure control may add digital gain (the tuning key the IPA reads).
check as_root chroot "$M" /usr/bin/python3 -c '
import sys, yaml
for f in sys.argv[1:]:
    agc = [a["Agc"] for a in yaml.safe_load(open(f))["algorithms"] if "Agc" in a][0]
    assert float(agc["maxDigitalGain"]) > 1.0, f
' /usr/share/libcamera/ipa/simple/imx681.yaml /usr/share/libcamera/ipa/simple/ov13858.yaml
check as_root chroot "$M" /usr/bin/python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' \
  /usr/share/libcamera/ipa/simple/uncalibrated.yaml
check ipa_signatures_ok "$M/usr/lib64/libcamera.so.$VER" "$M/usr/lib64/libcamera/ipa"

[ "$fail" -eq 0 ] || die "camera RPM verification failed (see FAIL lines above)"
log "camera RPMs verified in an overlay of the live root: $(for r in "${RPMS[@]}"; do basename "$r"; done | tr '\n' ' ')"
