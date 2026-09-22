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

# fetch URL DEST — idempotent, resumable download.
# The partial file is kept as DEST.part between attempts and curl resumes into it (-C -). curl's own
# --retry restarts from byte zero, which never gets a multi-GB ISO through a mirror that drops the
# connection mid-transfer (curl error 18). Every caller verifies a checksum afterwards.
fetch() {
  local url=$1 dest=$2 try rc size=0 prev
  if [ -s "$dest" ]; then log "cached: $(basename "$dest")"; return 0; fi
  log "downloading $(basename "$dest")"
  for try in $(seq 1 10); do
    rc=0
    curl -fsSL --retry 3 --retry-delay 3 --retry-all-errors -C - -o "$dest.part" "$url" || rc=$?
    if [ "$rc" -eq 0 ]; then mv -f "$dest.part" "$dest"; return 0; fi
    prev=$size
    size=$(stat -c %s "$dest.part" 2>/dev/null || echo 0)
    # 33/36: the server refused the range because .part is already complete. Hand it to the caller's
    # checksum check rather than starting the whole transfer again.
    if [ "$rc" -eq 33 ] || [ "$rc" -eq 36 ]; then
      if [ "$size" -gt 0 ] && [ "$size" = "$prev" ]; then mv -f "$dest.part" "$dest"; return 0; fi
    fi
    warn "$(basename "$dest"): interrupted (curl $rc) at $size bytes, retry $try/10"
    sleep 5
  done
  die "download failed after 10 attempts: $url"
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

# build_srpm SPEC_IN NAME SOURCEDIR [KEY=VALUE...] — renders the spec and builds one source RPM.
# Prints the resulting SRPM path. Used when the binary RPM has to be built elsewhere (see mock_rebuild).
build_srpm() {
  local spec_in=$1 name=$2 sourcedir=$3; shift 3
  local top="$WORK_DIR/rpmbuild-$name"
  rm -rf "$top"; mkdir -p "$top"/{BUILD,BUILDROOT,RPMS,SPECS,SRPMS}
  render "$spec_in" "$top/SPECS/$name.spec" "$@"
  rpmbuild -bs \
    --define "_topdir $top" --define "_sourcedir $sourcedir" --define "_srcrpmdir $top/SRPMS" \
    --define "dist .fc${FEDORA_RELEASE}" \
    "$top/SPECS/$name.spec" >"$top/rpmbuild-srpm.log" 2>&1 \
    || { tail -40 "$top/rpmbuild-srpm.log" >&2; die "rpmbuild -bs failed for $name (log: $top/rpmbuild-srpm.log)"; }
  local srpm; srpm=$(ls -t "$top/SRPMS/$name"-*.src.rpm 2>/dev/null | head -1 || true)
  [ -n "$srpm" ] || die "rpmbuild -bs produced no SRPM for $name"
  printf '%s\n' "$srpm"
}

# mock_tail RESULTDIR — print the most informative log tail mock left behind.
mock_tail() {
  local f
  for f in "$1/build.log" "$1/mock-simple.out" "$1/mock.out"; do
    if [ -s "$f" ]; then tail -40 "$f" >&2; return 0; fi
  done
  return 0
}

# mock_rebuild SRPM NAME — rebuild SRPM in the $MOCK_CONFIG buildroot, move the binary RPM into $RPM_DIR
# and print its path. This is how a package links against the *target* release's libraries instead of the
# build host's: sp11-iptsd needs the fmt/spdlog sonames of the Fedora that the live media carries, and
# those change between releases (F44 libfmt.so.11/libspdlog.so.1.15, F45 libfmt.so.12/libspdlog.so.1.17).
mock_rebuild() {
  local srpm=$1 name=$2
  local cfg="/etc/mock/$MOCK_CONFIG.cfg"
  [ -f "$cfg" ] || die "no mock config $cfg (install mock-core-configs, or set MOCK_CONFIG)"
  local resultdir="$WORK_DIR/mock-$name"
  # A previous run under sudo leaves root-owned files here.
  as_root rm -rf "$resultdir"; mkdir -p "$resultdir"
  # mock refuses to build for a user outside the 'mock' group. 00-setup-host.sh adds the membership, but it
  # only takes effect in a new login session, so fall back to sudo in the session that ran the setup.
  local -a mock=(mock)
  case " $(id -nG) " in *" mock "*) ;; *) mock=(sudo mock) ;; esac
  # --no-bootstrap-image: build the bootstrap chroot with dnf rather than pulling
  # registry.fedoraproject.org/fedora:<n> through podman. dnf --releasever against the target repos is all
  # this needs, and it keeps the build off the container registry.
  local -a args=(-r "$MOCK_CONFIG" --resultdir="$resultdir" --no-bootstrap-image --rebuild "$srpm")
  log "rebuilding $(basename "$srpm") in the $MOCK_CONFIG buildroot (several minutes on the first run)"
  if ! "${mock[@]}" "${args[@]}" >"$resultdir/mock.out" 2>&1; then
    # nspawn is mock's default where systemd is pid 1; under WSL it can fail for reasons that have nothing
    # to do with the build, and the plain chroot backend works. Retry once before giving up.
    warn "mock failed with the default isolation; retrying with --isolation=simple"
    "${mock[@]}" --isolation=simple "${args[@]}" >"$resultdir/mock-simple.out" 2>&1 \
      || { mock_tail "$resultdir"; die "mock rebuild failed for $name (logs in $resultdir)"; }
  fi
  local built; built=$(ls -t "$resultdir/$name"-[0-9]*."$FEDORA_ARCH".rpm 2>/dev/null | head -1 || true)
  [ -n "$built" ] || { mock_tail "$resultdir"; die "mock produced no $name binary RPM (logs in $resultdir)"; }
  rm -f "$RPM_DIR/$name"-*.rpm
  install -m 0644 "$built" "$RPM_DIR/$(basename "$built")"
  printf '%s\n' "$RPM_DIR/$(basename "$built")"
}

# mock_chain SRPM... — build several SRPMs in the $MOCK_CONFIG buildroot in the given order (`mock --chain`): the
# binary RPMs of each build enter a local repository the later builds resolve against, which is how
# iio-sensor-proxy gets libssc-devel before either package exists in Fedora. Every binary RPM (subpackages
# included) is copied into $RPM_DIR, replacing older builds of the same names. Needs createrepo_c on the host.
mock_chain() {
  local cfg="/etc/mock/$MOCK_CONFIG.cfg"
  [ -f "$cfg" ] || die "no mock config $cfg (install mock-core-configs, or set MOCK_CONFIG)"
  local resultdir="$WORK_DIR/mock-chain"
  as_root rm -rf "$resultdir"; mkdir -p "$resultdir"
  local -a mock=(mock)
  case " $(id -nG) " in *" mock "*) ;; *) mock=(sudo mock) ;; esac
  local -a args=(-r "$MOCK_CONFIG" --no-bootstrap-image --chain --localrepo "$resultdir" "$@")
  local names; names=$(printf '%s ' "${@##*/}")
  log "chain-building ${names}in the $MOCK_CONFIG buildroot (several minutes on the first run)"
  if ! "${mock[@]}" "${args[@]}" >"$resultdir/mock.out" 2>&1; then
    warn "mock failed with the default isolation; retrying with --isolation=simple"
    as_root rm -rf "$resultdir/results"
    "${mock[@]}" --isolation=simple "${args[@]}" >"$resultdir/mock-simple.out" 2>&1 \
      || { f=$(find "$resultdir" -name build.log -newer "$resultdir/mock.out" 2>/dev/null | head -1 || true)
           [ -n "$f" ] && tail -40 "$f" >&2; mock_tail "$resultdir"; die "mock chain build failed (logs in $resultdir)"; }
  fi
  local rpm name srpm
  while IFS= read -r rpm; do
    name=$(rpm -qp --qf '%{NAME}' "$rpm" 2>/dev/null) || die "cannot read $rpm"
    rm -f "$RPM_DIR/$name"-[0-9]*.rpm
    install -m 0644 "$rpm" "$RPM_DIR/$(basename "$rpm")"
  done < <(find "$resultdir" -name "*.$FEDORA_ARCH.rpm" -o -name '*.noarch.rpm' | sort)
  for srpm in "$@"; do
    name=$(rpm -qp --qf '%{NAME}' "$srpm")
    [ -n "$(rpm_of "$name")" ] || { mock_tail "$resultdir"; die "mock chain produced no $name binary RPM (logs in $resultdir)"; }
    printf '%s\n' "$(rpm_of "$name")"
  done
}

# Newest RPM of a package in $RPM_DIR, or empty. Never fails: callers test the result themselves.
rpm_of() { ls -t "$RPM_DIR/$1"-[0-9]*.rpm 2>/dev/null | head -1 || true; }

# config_fragment_holds FRAGMENT CONFIG — every line of a Kconfig fragment holds in CONFIG: a "CONFIG_X=v" line
# must appear verbatim, a "# CONFIG_X is not set" line must have no CONFIG_X= at all. Warns per violation and
# returns 1 without exiting, so the caller decides (step 20 dies, step 60 counts a failed check).
config_fragment_holds() {
  local frag=$1 cfg=$2 line sym rc=0
  while IFS= read -r line; do
    case "$line" in
      CONFIG_*=*)
        grep -qxF -- "$line" "$cfg" \
          || { warn "config policy: '$line' not in $cfg (actual: $(grep -E "^${line%%=*}=" "$cfg" || echo unset))"; rc=1; } ;;
      "# CONFIG_"*" is not set")
        sym=${line#"# "}; sym=${sym% is not set}
        ! grep -qE "^${sym}=" "$cfg" \
          || { warn "config policy: '$line' violated in $cfg (actual: $(grep -E "^${sym}=" "$cfg"))"; rc=1; } ;;
    esac
  done < "$frag"
  return $rc
}

# inputs_sha256 PATH... — one hash over every regular file below the given paths (content and path, the path
# relative to the repository where it lies inside it, sorted, so the value is the same in every checkout) followed
# by whatever lines stdin carries (values from sp11.conf). Steps 30 and 45 record it in the RPM they build and
# refuse to rebuild the same version from other inputs: dnf ignores a same-version rebuild. Callers without extra
# lines pass </dev/null.
inputs_sha256() {
  local p f
  for p in "$@"; do [ -e "$p" ] || die "inputs_sha256: no such path: $p"; done
  {
    for p in "$@"; do
      find "$p" -type f | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s  %s\n' "$(sha256_of "$f")" "${f#"$SP11_ROOT/"}"
      done
    done
    cat
  } | sha256sum | cut -d' ' -f1
}

# kernel_rev_sha256 — the content of the SP11 kernel revision: its number, the fragment's effective lines (as
# config_fragment_holds reads them) and, per patch in name order, its name and the diff from its first "--- " line.
# Comments and patch descriptions do not count. sp11.conf pins it as KERNEL_SP11_REV_SHA256; step 20 compares, so
# neither the files nor the number can change alone.
kernel_rev_sha256() {
  local p
  {
    printf 'KERNEL_SP11_REV=%s\n' "$KERNEL_SP11_REV"
    grep -E '^(CONFIG_[A-Za-z0-9_]+=|# CONFIG_[A-Za-z0-9_]+ is not set$)' "$FILES_DIR/$KERNEL_CONFIG_FRAGMENT" || true
    for p in "$FILES_DIR/$KERNEL_PATCH_DIR"/*.patch; do
      [ -f "$p" ] || continue
      printf '== %s\n' "$(basename "$p")"; sed -n '/^--- /,$p' "$p"
    done
  } | sha256sum | cut -d' ' -f1
}

# mounts_under DIR — mount targets strictly below DIR, one per line (empty when none). `findmnt -R` only
# descends from a mount point, so match the target prefix instead.
mounts_under() { findmnt -rn -o TARGET | awk -v p="$1/" 'index($0, p) == 1'; }
