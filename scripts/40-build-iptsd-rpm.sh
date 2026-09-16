#!/usr/bin/bash
# Step 5: build the sp11-iptsd RPM (pinned upstream iptsd + ooaklee's SP11 udev/systemd integration).
. "$(dirname "$0")/lib.sh"
require_cmd git rpmbuild meson ninja g++

# sp11-iptsd links against fmt and spdlog, whose sonames change between Fedora releases, so the RPM has to
# be built against the libraries of the release on the live media rather than the host's. Same release =
# build here; different = build in a mock buildroot for the target.
HOST_RELEASE=$(rpm -E '%{fedora}')
case "$IPTSD_BUILD_MODE" in
  auto) if [ "$FEDORA_RELEASE" = "$HOST_RELEASE" ]; then BUILD_MODE=host; else BUILD_MODE=mock; fi ;;
  host|mock) BUILD_MODE=$IPTSD_BUILD_MODE ;;
  *) die "IPTSD_BUILD_MODE must be auto, host or mock (got '$IPTSD_BUILD_MODE')" ;;
esac
[ "$BUILD_MODE" = host ] || require_cmd mock
log "iptsd build mode: $BUILD_MODE (host Fedora $HOST_RELEASE, target Fedora $FEDORA_RELEASE)"

CACHED=$(rpm_of sp11-iptsd)
if [ -n "$CACHED" ] && [ "${FORCE:-0}" != 1 ]; then
  if [ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$CACHED" 2>/dev/null)" = "$IPTSD_VERSION-$IPTSD_RPM_RELEASE.fc$FEDORA_RELEASE" ] \
     && rpm -qp --qf '%{DESCRIPTION}' "$CACHED" 2>/dev/null | grep -F "$IPTSD_COMMIT" >/dev/null; then
    log "iptsd RPM already built: $CACHED (FORCE=1 to rebuild)"; exit 0
  fi
  log "cached $(basename "$CACHED") is not iptsd $IPTSD_VERSION-$IPTSD_RPM_RELEASE @ ${IPTSD_COMMIT:0:12}; rebuilding"
fi
IDIR="$BUILD_DIR/iptsd"; SRC="$IDIR/SOURCES"; rm -rf "$SRC"; mkdir -p "$SRC"
[ "$(git -C "$CACHE_DIR/iptsd" rev-parse HEAD)" = "$IPTSD_COMMIT" ] || die "iptsd checkout is not at $IPTSD_COMMIT"
[ "$(git -C "$CACHE_DIR/oe" rev-parse HEAD)" = "$OE_COMMIT" ] || die "OE checkout is not at $OE_COMMIT"
git -C "$CACHE_DIR/iptsd" archive --format=tar.gz --prefix="iptsd-$IPTSD_COMMIT/" -o "$SRC/iptsd-$IPTSD_COMMIT.tar.gz" HEAD
OEI="$CACHE_DIR/oe/userspace/iptsd-sp11"
# ooaklee's templates use @IPTSD@/@CHECKER@/@SYSTEMCTL@/@SYSTEMD_ESCAPE@; render them for Fedora's paths here.
for f in packaging/70-sp11-iptsd.rules.in packaging/sp11-iptsd@.service.in packaging/sp11-iptsd-restart.in; do
  [ -f "$OEI/$f" ] || die "missing $OEI/$f"
  out="$SRC/$(basename "${f%.in}")"
  render "$OEI/$f" "$out" IPTSD=/usr/libexec/sp11-iptsd CHECKER=/usr/libexec/sp11-iptsd-check-device \
    SYSTEMCTL=/usr/bin/systemctl SYSTEMD_ESCAPE=/usr/bin/systemd-escape
done
for f in config/surface-pro-11-0c80.conf config/surface-pro-11-0c83.conf; do
  [ -f "$OEI/$f" ] || die "missing $OEI/$f"; install -m 0644 "$OEI/$f" "$SRC/$(basename "$f")"
done
grep -q 'KERNELS=="001C:045E:0C83' "$SRC/70-sp11-iptsd.rules" || die "udev rule does not match the OLED digitizer 045E:0C83"
bash -n "$SRC/sp11-iptsd-restart" || die "rendered sleep hook has a syntax error"
if [ "$BUILD_MODE" = host ]; then
  log "building sp11-iptsd RPM (meson, system libraries)"
  RPM=$(build_rpm "$SPEC_DIR/sp11-iptsd.spec.in" sp11-iptsd "$SRC" COMMIT="$IPTSD_COMMIT" VERSION="$IPTSD_VERSION" RPMREL="$IPTSD_RPM_RELEASE")
else
  log "building sp11-iptsd SRPM, then rebuilding it against Fedora $FEDORA_RELEASE libraries"
  SRPM=$(build_srpm "$SPEC_DIR/sp11-iptsd.spec.in" sp11-iptsd "$SRC" COMMIT="$IPTSD_COMMIT" VERSION="$IPTSD_VERSION" RPMREL="$IPTSD_RPM_RELEASE")
  RPM=$(mock_rebuild "$SRPM" sp11-iptsd)
fi
rpm -qpl "$RPM" | grep -x /usr/libexec/sp11-iptsd >/dev/null || die "RPM lacks /usr/libexec/sp11-iptsd"

# The point of the mock route is the linkage, so assert it: a cross-release build must not have picked up
# the host's sonames. Comparing against what the host's own fmt/spdlog provide keeps this release-agnostic.
if [ "$BUILD_MODE" = mock ]; then
  REQS=$(rpm -qp --requires "$RPM" 2>/dev/null)
  for pkg in fmt spdlog; do
    host_soname=$(rpm -q --provides "$pkg" 2>/dev/null | grep -oE "lib[a-zA-Z]+\.so\.[0-9]+(\.[0-9]+)*" | sort -u | head -1 || true)
    [ -n "$host_soname" ] || continue
    if printf '%s\n' "$REQS" | grep -F "$host_soname" >/dev/null; then
      die "sp11-iptsd still requires the host's $host_soname; the $MOCK_CONFIG buildroot did not take effect"
    fi
  done
  log "iptsd links: $(printf '%s\n' "$REQS" | grep -E 'libfmt|libspdlog|libINIReader' | tr '\n' ' ' || true)"
fi
log "iptsd RPM: $RPM ($(du -h "$RPM" | cut -f1))"
