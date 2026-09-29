#!/usr/bin/bash
# Run payload/camera/sp11-camera-probe on the host against probe-fake.py's simulated sensors: the scenarios that tell
# a sensor which takes the frame length the driver writes from one that ignores it (kernel revisions 7 and 8), and an
# OV13858 whose gain stops at 15.5x. The probe needs root (sudo -n); it only runs the fakes and writes to a temporary
# directory. Usage: probe-fake.sh [probe arguments]   (without arguments: the standard scenarios)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"; ln -s "$HERE/probe-fake.py" "$T/bin/media-ctl"; ln -s "$HERE/probe-fake.py" "$T/bin/v4l2-ctl"
touch "$T/media0"
# The probe looks for /dev/media*; the copy under test looks where FAKE_MEDIA_GLOB points instead.
sed "s#glob.glob('/dev/media\[0-9\]\*')#glob.glob(os.environ.get('FAKE_MEDIA_GLOB', '/dev/media[0-9]*'))#" \
  "$ROOT/payload/camera/sp11-camera-probe" > "$T/probe.py"
grep -q FAKE_MEDIA_GLOB "$T/probe.py" || { echo "the probe's /dev/media glob changed; adapt the sed above" >&2; exit 1; }
fail=0
r() {  # r "<FAKE_* settings>" <probe arguments>; a failing probe (or sudo) prints a FAIL line and sets fail
  local env=$1 rc=0; shift
  rm -f "$T/state.json" "$T/state.json.log"
  echo "=== $env :: $*"
  # shellcheck disable=SC2086 # the settings are separate words
  sudo -n env "PATH=$T/bin:/usr/bin:/bin" "FAKE_STATE=$T/state.json" "FAKE_MEDIA_GLOB=$T/media[0-9]*" "TMPDIR=$T" \
    $env python3 -B "$T/probe.py" "$@" >"$T/out" 2>&1 || rc=$?
  grep -vE '^(front|rear) camera:' "$T/out" || true
  [ "$rc" -eq 0 ] || { echo "FAIL (exit status $rc): $(tail -n 1 "$T/out")"; fail=1; }
}
if [ $# -gt 0 ]; then r "${FAKE_ENV:-}" "$@"; exit "$fail"; fi
r "FAKE_FRONT=rev8 FAKE_SCENE=1.4" front --frame-length
r "FAKE_FRONT=rev8-ignored FAKE_SCENE=1.4" front --frame-length
r "FAKE_FRONT=rev7 FAKE_SCENE=1.4" front --frame-length
r "FAKE_SCENE=1.0 FAKE_GAIN_STOP=15.5" rear --gain-range
r "FAKE_SCENE=1.0" rear --gain-range
r "FAKE_FRONT=rev8 FAKE_SCENE=1.4" front
exit "$fail"
