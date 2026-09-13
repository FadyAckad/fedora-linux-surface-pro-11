#!/usr/bin/bash
# Step 5: build the sp11-iptsd RPM (pinned upstream iptsd + ooaklee's SP11 udev/systemd integration).
. "$(dirname "$0")/lib.sh"
require_cmd git rpmbuild meson ninja g++

if [ -n "$(rpm_of sp11-iptsd)" ] && [ "${FORCE:-0}" != 1 ]; then
  log "iptsd RPM already built: $(rpm_of sp11-iptsd) (FORCE=1 to rebuild)"; exit 0
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
log "building sp11-iptsd RPM (meson, system libraries)"
RPM=$(build_rpm "$SPEC_DIR/sp11-iptsd.spec.in" sp11-iptsd "$SRC" COMMIT="$IPTSD_COMMIT" VERSION="$IPTSD_VERSION")
rpm -qpl "$RPM" | grep -x /usr/libexec/sp11-iptsd >/dev/null || die "RPM lacks /usr/libexec/sp11-iptsd"
log "iptsd RPM: $RPM ($(du -h "$RPM" | cut -f1))"
