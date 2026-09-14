#!/usr/bin/bash
# Shared helpers for the SP11 Fedora live-ISO build. Source this file; do not execute it.
set -Eeuo pipefail
umask 022
export LC_ALL=C.UTF-8

SP11_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../sp11.conf
. "$SP11_ROOT/sp11.conf"

BUILD_DIR="$SP11_ROOT/build"
CACHE_DIR="$BUILD_DIR/cache"
WORK_DIR="$BUILD_DIR/work"
RPM_DIR="$BUILD_DIR/rpms"
OUT_DIR="$BUILD_DIR/out"
HARDWARE_ENV="$BUILD_DIR/hardware.env"
FILES_DIR="$SP11_ROOT/files"
SPEC_DIR="$SP11_ROOT/rpm"
mkdir -p "$CACHE_DIR" "$WORK_DIR" "$RPM_DIR" "$OUT_DIR"

log()  { printf '\033[1;34m[sp11]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[sp11] WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[sp11] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing command '$c' (run scripts/00-setup-host.sh)"
  done
}

as_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

# fetch URL DEST — idempotent download.
fetch() {
  local url=$1 dest=$2
  if [ -s "$dest" ]; then log "cached: $(basename "$dest")"; return 0; fi
  log "downloading $(basename "$dest")"
  curl -fsSL --retry 5 --retry-delay 3 -o "$dest.part" "$url" || die "download failed: $url"
  mv -f "$dest.part" "$dest"
}

sha256_of() { sha256sum "$1" | cut -d' ' -f1; }

verify_sha256() {
  local f=$1 want=$2 have
  have=$(sha256_of "$f")
  [ "$have" = "$want" ] || die "SHA-256 mismatch for $f: got $have, want $want"
  log "verified $(basename "$f")"
}

# verify_in_sums SUMSFILE FILE — verify FILE against a sha256sum-style list (matched by basename).
verify_in_sums() {
  local sums=$1 f=$2 want
  want=$(awk -v n="$(basename "$f")" '($2==n || $2=="*"n){print $1}' "$sums" | head -1)
  [ -n "$want" ] || die "$(basename "$f") is not listed in $sums"
  verify_sha256 "$f" "$want"
}

# git_pin REPO COMMIT DIR — shallow checkout of one exact commit (idempotent).
git_pin() {
  local repo=$1 commit=$2 dir=$3
  if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$commit" ]; then
    log "cached: $(basename "$dir") @ ${commit:0:12}"; return 0
  fi
  rm -rf "$dir"; mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$repo"
  git -C "$dir" fetch -q --depth 1 origin "$commit"
  git -C "$dir" checkout -q FETCH_HEAD
  [ "$(git -C "$dir" rev-parse HEAD)" = "$commit" ] || die "checkout of $repo@$commit failed"
}

load_hardware() {
  [ -f "$HARDWARE_ENV" ] || die "missing $HARDWARE_ENV (run scripts/05-detect-hardware.sh)"
  # shellcheck source=/dev/null
  . "$HARDWARE_ENV"
}

# render TEMPLATE DEST KEY=VALUE... — substitutes @KEY@ tokens, fails on leftovers.
render() {
  local src=$1 dest=$2; shift 2
  local content kv k v
  content=$(cat "$src")
  for kv in "$@"; do
    k=${kv%%=*}; v=${kv#*=}
    content=${content//"@$k@"/"$v"}
  done
  printf '%s\n' "$content" > "$dest"
  if grep -q '@[A-Z][A-Z0-9_]*@' "$dest"; then
    die "unrendered placeholder(s) in $dest: $(grep -o '@[A-Z][A-Z0-9_]*@' "$dest" | sort -u | tr '\n' ' ')"
  fi
}

# build_rpm SPEC_IN NAME SOURCEDIR [KEY=VALUE...] — renders the spec and builds one binary RPM into $RPM_DIR.
# Prints the resulting RPM path.
build_rpm() {
  local spec_in=$1 name=$2 sourcedir=$3; shift 3
  local top="$WORK_DIR/rpmbuild-$name"
  rm -rf "$top"; mkdir -p "$top"/{BUILD,BUILDROOT,RPMS,SPECS,SRPMS}
  render "$spec_in" "$top/SPECS/$name.spec" "$@"
  rm -f "$RPM_DIR/$name"-*.rpm
  rpmbuild -bb \
    --define "_topdir $top" --define "_sourcedir $sourcedir" --define "_rpmdir $RPM_DIR" \
    --define "_rpmfilename %%{NAME}-%%{VERSION}-%%{RELEASE}.%%{ARCH}.rpm" \
    --define "dist .fc${FEDORA_RELEASE}" \
    "$top/SPECS/$name.spec" >"$top/rpmbuild.log" 2>&1 \
    || { tail -40 "$top/rpmbuild.log" >&2; die "rpmbuild failed for $name (log: $top/rpmbuild.log)"; }
  ls -t "$RPM_DIR/$name"-*.rpm | head -1
}

# Newest RPM of a package in $RPM_DIR, or empty. Never fails: callers test the result themselves.
rpm_of() { ls -t "$RPM_DIR/$1"-[0-9]*.rpm 2>/dev/null | head -1 || true; }

# mounts_under DIR — mount targets strictly below DIR, one per line (empty when none). `findmnt -R` only
# descends from a mount point, so match the target prefix instead.
mounts_under() { findmnt -rn -o TARGET | awk -v p="$1/" 'index($0, p) == 1'; }
