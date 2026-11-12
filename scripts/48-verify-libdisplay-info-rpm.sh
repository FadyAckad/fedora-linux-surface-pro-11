#!/usr/bin/bash
# Step 4g: prove the libdisplay-info RPM (scripts/47) replaces Fedora's build in the live root the way
# `dnf install` does on an installed system, does what it is built for, and can be taken back out. Runs in an
# overlay of the extracted live root, so the cached root is never modified.
#   - Fedora's build goes in first, whatever the root carries: with it, the library's high-level lookups (the ones
#     mutter decides HDR by) find no HDR in the EDID of upstream's test panel, whose HDR data sits in its DisplayID
#     v2 extension as the Surface Pro 11 panel's does
#   - the rebuild goes on top with scriptlets: everything that links against the library resolves its symbols, the
#     compositor starts, and the same lookups now report static metadata type 1, PQ and BT.2020 RGB
#   - Fedora's build goes back over it
# What only the device can show (the HDR switch in GNOME, the picture) is not covered: docs/verified.md.
. "$(dirname "$0")/lib.sh"
require_cmd rpm findmnt git readelf

BASE="$WORK_DIR/iso/rootfs"
as_root test -d "$BASE/usr/lib/modules" || die "no extracted live root at $BASE (run scripts/50-build-iso.sh first)"
RPM=$(rpm_of libdisplay-info); [ -n "$RPM" ] || die "no libdisplay-info RPM in $RPM_DIR (run scripts/47-build-libdisplay-info-rpm.sh)"
STOCK="$CACHE_DIR/$LIBDISPLAY_INFO_STOCK_RPM"
[ -s "$STOCK" ] || die "missing $STOCK (run scripts/10-fetch-sources.sh)"
verify_sha256 "$STOCK" "$LIBDISPLAY_INFO_STOCK_SHA256"
NVR_NEW=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$RPM")
NVR_OLD=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$STOCK")
SONAME=$(rpm -qp --provides "$STOCK" | sed -n 's/^\(libdisplay-info\.so\.[0-9]*\)()(64bit)$/\1/p' | head -1 || true)
[ -n "$SONAME" ] || die "$LIBDISPLAY_INFO_STOCK_RPM provides no libdisplay-info soname"
TEST_PATCH="$PAYLOAD_DIR/display/libdisplay-info/0002-test-add-asus-ux3405.patch"
[ -s "$TEST_PATCH" ] || die "missing $TEST_PATCH"

T="$WORK_DIR/verify-libdisplay-info"; M="$T/merged"; E="$WORK_DIR/verify-libdisplay-info-edid"
fail=0
check() { if "$@" >/dev/null 2>&1; then log "  ok: $*"; else warn "  FAIL: $*"; fail=1; fi; }
inroot() { as_root chroot "$M" "$@"; }
teardown() {
  # A cgroup submount under the bound /sys can refuse a recursive unmount; detach lazily rather than leave it.
  for m in dev proc sys; do as_root umount -R "$M/$m" 2>/dev/null || as_root umount -lR "$M/$m" 2>/dev/null || true; done
  as_root umount "$M" 2>/dev/null || as_root umount -l "$M" 2>/dev/null || true
  if [ -z "$(mounts_under "$T")" ]; then as_root rm -rf --one-file-system "$T"; else
    warn "mounts left under $T: $(mounts_under "$T" | tr '\n' ' ')"; fi
  rm -rf "$E"
}
trap teardown EXIT
teardown

# The EDID of upstream's test panel, out of the patch that adds the test (a git binary patch; a repository of its
# own, so the patch's paths are taken from its top).
mkdir -p "$E" && git -C "$E" init -q || die "cannot initialize $E"
git -C "$E" apply --include='test/data/asus-ux3405.edid' "$TEST_PATCH" || die "cannot take the test EDID out of $(basename "$TEST_PATCH")"
EDID="$E/test/data/asus-ux3405.edid"
[ "$(stat -c %s "$EDID" 2>/dev/null || echo 0)" = 256 ] || die "the test EDID out of $(basename "$TEST_PATCH") is not 256 bytes"

as_root mkdir -p "$T"/upper "$T"/work "$M"
as_root mount -t overlay overlay -o "lowerdir=$BASE,upperdir=$T/upper,workdir=$T/work" "$M"
for m in dev proc sys; do as_root mount --rbind "/$m" "$M/$m"; as_root mount --make-rslave "$M/$m"; done
as_root install -d "$M/tmp/ldi"
as_root cp "$RPM" "$STOCK" "$EDID" "$M/tmp/ldi/"
NEW_IN="/tmp/ldi/$(basename "$RPM")"; OLD_IN="/tmp/ldi/$(basename "$STOCK")"

# The two lookups mutter decides HDR by (its src/backends/edid-parse.c), through the root's own Python: the HDR
# static metadata (type 1, PQ) and the supported signal colorimetry (BT.2020 RGB) of the test panel.
as_root tee "$M/tmp/ldi/hdr-lookup.py" >/dev/null <<'EOF'
import ctypes, sys
lib = ctypes.CDLL(sys.argv[1])
class Hdr(ctypes.Structure):
    _fields_ = [("max", ctypes.c_float), ("max_fall", ctypes.c_float), ("min", ctypes.c_float),
                ("type1", ctypes.c_bool), ("traditional_sdr", ctypes.c_bool), ("traditional_hdr", ctypes.c_bool),
                ("pq", ctypes.c_bool), ("hlg", ctypes.c_bool)]
class Colorimetry(ctypes.Structure):
    _fields_ = [("bt2020_cycc", ctypes.c_bool), ("bt2020_ycc", ctypes.c_bool), ("bt2020_rgb", ctypes.c_bool),
                ("st2113_rgb", ctypes.c_bool), ("ictcp", ctypes.c_bool)]
lib.di_info_parse_edid.restype = ctypes.c_void_p
lib.di_info_parse_edid.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
lib.di_info_get_hdr_static_metadata.restype = ctypes.POINTER(Hdr)
lib.di_info_get_hdr_static_metadata.argtypes = [ctypes.c_void_p]
lib.di_info_get_supported_signal_colorimetry.restype = ctypes.POINTER(Colorimetry)
lib.di_info_get_supported_signal_colorimetry.argtypes = [ctypes.c_void_p]
data = open(sys.argv[2], "rb").read()
info = lib.di_info_parse_edid(data, len(data))
if not info:
    sys.exit("di_info_parse_edid failed")
hdr = lib.di_info_get_hdr_static_metadata(info).contents
col = lib.di_info_get_supported_signal_colorimetry(info).contents
print("type1=%d pq=%d bt2020_rgb=%d" % (hdr.type1, hdr.pq, col.bt2020_rgb))
EOF
lookup() { inroot /usr/bin/python3 /tmp/ldi/hdr-lookup.py "$SONAME" /tmp/ldi/asus-ux3405.edid 2>&1 | tail -1 || true; }
have_python=1
as_root test -x "$M/usr/bin/python3" || { have_python=0; warn "  no python3 in this root; the HDR lookups are not exercised"; }

# Every installed file that links against the library, by the packages that require its soname. readelf is the
# host's: a live root need not carry binutils.
users() {
  local pkgs
  pkgs=$(inroot /usr/bin/rpm -q --whatrequires "$SONAME()(64bit)" --qf '%{NAME}\n' 2>/dev/null | sort -u | tr '\n' ' ' || true)
  [ -n "$pkgs" ] || return 0
  # shellcheck disable=SC2086 # a list of package names
  inroot /usr/bin/rpm -ql $pkgs 2>/dev/null | as_root sh -c '
    while IFS= read -r f; do
      [ -f "$1$f" ] && [ ! -L "$1$f" ] || continue
      readelf -d "$1$f" 2>/dev/null | grep "NEEDED.*$2" >/dev/null && echo "$f"
    done; true' sh "$M" "$SONAME"
}
unresolved() { local f; for f in "$@"; do inroot /usr/bin/ldd -r "$f" 2>&1 | grep -E 'undefined symbol|not found' | sed "s|^|$f: |" || true; done; }
compositors() {  # the root's compositor has to start with every symbol bound up front
  local c
  for c in /usr/bin/mutter /usr/bin/kwin_wayland; do
    as_root test -x "$M$c" || continue
    check inroot /usr/bin/env LD_BIND_NOW=1 "$c" --version
  done
}

## 1. Fedora's build, whatever the root carries: the state every installation starts from.
log "--- Fedora's build: $NVR_OLD"
inroot /usr/bin/rpm -U --oldpackage --replacepkgs --define '_pkgverify_level none' "$OLD_IN" || die "rpm -U of Fedora's libdisplay-info failed in the chroot"
check test "$(inroot /usr/bin/rpm -q libdisplay-info)" = "$NVR_OLD"
mapfile -t USERS < <(users)
log "  packages that need $SONAME: $(inroot /usr/bin/rpm -q --whatrequires "$SONAME()(64bit)" --qf '%{NAME} ' 2>/dev/null || true)"
log "  files linked against it: ${#USERS[@]}"
check test "${#USERS[@]}" -ge 1
check test -z "$(unresolved "${USERS[@]}")"
compositors
if [ "$have_python" = 1 ]; then
  log "  HDR lookups with Fedora's build: $(lookup)"
  # The case the rebuild exists for: Fedora's build must not see the panel's HDR data, or the check below proves
  # nothing.
  check test "$(lookup)" = "type1=0 pq=0 bt2020_rgb=0"
fi

## 2. The rebuild on top, as `dnf install ./libdisplay-info-*.rpm` does: the dependency check, then the transaction
##    with scriptlets.
log "--- the rebuild: $NVR_NEW"
inroot /usr/bin/rpm -U --test --define '_pkgverify_level none' "$NEW_IN" || die "the libdisplay-info RPM has unmet dependencies in the live root (see above)"
inroot /usr/bin/rpm -U --define '_pkgverify_level none' "$NEW_IN" || die "rpm -U of the libdisplay-info RPM failed in the chroot"
check test "$(inroot /usr/bin/rpm -q libdisplay-info)" = "$NVR_NEW"
check inroot /usr/bin/rpm -V libdisplay-info
check as_root test -e "$M/usr/lib64/$SONAME"
check test -z "$(unresolved "${USERS[@]}")"
[ -z "$(unresolved "${USERS[@]}")" ] || warn "  unresolved: $(unresolved "${USERS[@]}" | tr '\n' ' ')"
compositors
if [ "$have_python" = 1 ]; then
  log "  HDR lookups with the rebuild: $(lookup)"
  check test "$(lookup)" = "type1=1 pq=1 bt2020_rgb=1"
fi

## 3. The way back: Fedora's build over the rebuild, as `dnf downgrade libdisplay-info` does.
log "--- the way back: $NVR_OLD"
inroot /usr/bin/rpm -U --oldpackage --define '_pkgverify_level none' "$OLD_IN" || die "rpm -U --oldpackage of Fedora's libdisplay-info failed in the chroot"
check test "$(inroot /usr/bin/rpm -q libdisplay-info)" = "$NVR_OLD"
check inroot /usr/bin/rpm -V libdisplay-info
check test -z "$(unresolved "${USERS[@]}")"
compositors

teardown; trap - EXIT
[ "$fail" -eq 0 ] || die "libdisplay-info RPM verification failed (see the FAIL lines above)"
log "libdisplay-info RPM verified in the live root: $(basename "$RPM")"
