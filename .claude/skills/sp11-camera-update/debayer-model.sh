#!/usr/bin/bash
# Render libcamera's packed-Bayer shader, as patched and as released, under Mesa's software renderer in a mock root of
# the target release (debayer-model.py): the dark-frame chessboard test and the colour check of payload/camera/0007.
# Usage: debayer-model.sh <libcamera clone with payload/camera/ applied> <its release tag, e.g. v0.7.2>
# The mock root (uniqueext debayer) persists between runs; `mock -r <config> --uniqueext=debayer --scrub=all`
# removes it.
set -euo pipefail
TREE=$(cd "$1" && pwd); TAG=$2
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
# The mock configuration of the target release, as the pipeline uses it (MOCK_CONFIG in sp11.conf).
MOCK=$(bash -c ". '$ROOT/scripts/lib.sh' >/dev/null 2>&1; echo \"\$MOCK_CONFIG\"")
[ -n "$MOCK" ] || { echo "cannot read MOCK_CONFIG from sp11.conf" >&2; exit 1; }
SH=src/libcamera/shaders
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cp "$HERE/debayer-model.py" "$TREE/$SH/identity.vert" "$TREE/$SH/bayer_1x_packed.frag" "$W/"
git -C "$TREE" show "$TAG:$SH/bayer_1x_packed.frag" > "$W/bayer_1x_packed.frag.orig"
m() { mock -r "$MOCK" --uniqueext=debayer --quiet "$@"; }
if ! m --chroot 'python3 -c "import OpenGL, numpy"' >/dev/null 2>&1; then
  m --init
  m --install mesa-dri-drivers mesa-libEGL mesa-libGLES python3-pyopengl python3-numpy
fi
m --chroot 'rm -rf /builddir/debayer && mkdir -p /builddir/debayer'
m --copyin "$W/debayer-model.py" "$W/identity.vert" "$W/bayer_1x_packed.frag" "$W/bayer_1x_packed.frag.orig" /builddir/debayer/
m --chroot 'cd /builddir/debayer && EGL_PLATFORM=surfaceless PYOPENGL_PLATFORM=egl LIBGL_ALWAYS_SOFTWARE=1 python3 debayer-model.py'
