#!/usr/bin/bash
# Step 0: install build dependencies on the aarch64 Fedora (WSL) host and sanity-check the environment.
. "$(dirname "$0")/lib.sh"

[ "$(uname -m)" = aarch64 ] || die "this build must run on an aarch64 host (native kernel build, aarch64 RPMs)"
grep -q '^ID=fedora' /etc/os-release || die "this build expects a Fedora host (found: $(. /etc/os-release; echo "$PRETTY_NAME"))"
as_root true || die "sudo is required"

free_gib=$(df -Pk "$BUILD_DIR" | awk 'NR==2{print int($4/1024/1024)}')
[ "$free_gib" -ge 40 ] || die "need at least 40 GiB free under $BUILD_DIR (have ${free_gib} GiB)"

PKGS=(
  # kernel build
  gcc make flex bison bc openssl openssl-devel elfutils-libelf-devel dwarves perl-interpreter perl-Getopt-Long
  python3 rsync zstd xz dtc kmod binutils gawk file diffutils findutils which util-linux patch
  # RPM packaging
  rpm-build rpmdevtools
  # iptsd build
  gcc-c++ cmake meson ninja-build pkgconf-pkg-config cli11-devel eigen3-devel fmt-devel spdlog-devel
  inih-devel guidelines-support-library-devel systemd-rpm-macros
  # ISO remaster
  xorriso erofs-utils erofs-fuse dracut dracut-live cpio curl git dosfstools
  # GRUB console font (grub2-mkfont; DejaVu Sans Mono is the source face)
  grub2-tools-extra dejavu-sans-mono-fonts
  # Windows Bluetooth pairing export
  python3-hivex hivex
  # cross-release RPM builds (sp11-iptsd against the target Fedora's fmt/spdlog)
  mock
)
log "installing build dependencies"
as_root dnf install -y -q "${PKGS[@]}"

# mock refuses to build as an ordinary user outside the 'mock' group. Group changes only take effect in a
# new login session, so this is a warning, not a failure: lib.sh falls back to `sudo mock` meanwhile.
case " $(id -nG) " in
  *" mock "*) ;;
  *) as_root usermod -aG mock "$USER" \
       && warn "added $USER to the 'mock' group; it applies in a new WSL session (wsl.exe --shutdown, or newgrp mock). Until then mock runs through sudo." ;;
esac

FR="$WINDOWS_ROOT/Windows/System32/DriverStore/FileRepository"
[ -d "$FR" ] || warn "Windows DriverStore not found at $FR; firmware extraction (scripts/30) will fail"
command -v powershell.exe >/dev/null 2>&1 || warn "powershell.exe not reachable; hardware detection (scripts/05) needs WSL interop with Windows"

log "host ready: $(nproc) CPUs, ${free_gib} GiB free, gcc $(gcc -dumpversion), rpm $(rpm --version | awk '{print $3}')"
