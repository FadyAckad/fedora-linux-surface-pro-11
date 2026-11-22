#!/usr/bin/bash
# Step 2b: the Secure Boot add-on of the kernel step 20 built (docs/secure-boot.md). With Secure Boot on, Fedora's
# own boot path does not work on the Surface Pro 11: shim's loader does not return for an image it has verified.
# What does work is GRUB's chainloader starting one file signed with the builder's own key:
#   sp11-secureboot-stub                 systemd's EFI stub, built in mock from the tarball of Fedora's source RPM
#                                        with the patch in payload/secureboot/stub/ (a build input, kept in
#                                        build/secureboot/, never installed)
#   sp11-kernel-secureboot-<KERNEL_ABI>  that stub, the kernel and this unit's device tree packed with ukify into
#                                        one file, signed with sbsign, with the certificate beside it
# The file holds no command line and no initramfs: GRUB passes the boot entry's options, and the stub reads the
# initramfs from the ESP, where the support RPM's sp11-secureboot keeps a copy.
# Runs only on a host with the signing key (SECUREBOOT_KEY_DIR in sp11.conf); without it the step says so and
# builds nothing. The private key is read by sbsign here and nowhere else: it enters no mock root and no RPM. It is
# kept encrypted with its owner's passphrase, which sbsign asks for on the terminal when it signs a new image.
# Idempotent: skipped while both packages match sp11.conf, refused when their inputs changed without a new
# release; FORCE=1 rebuilds.
. "$(dirname "$0")/lib.sh"

KEY="$SECUREBOOT_KEY_DIR/sp11-mok.key"; CRT="$SECUREBOOT_KEY_DIR/sp11-mok.crt"
if [ ! -s "$KEY" ] || [ ! -s "$CRT" ]; then
  log "no Secure Boot key in $SECUREBOOT_KEY_DIR (sp11-mok.key, sp11-mok.crt): no signed boot image is built"
  exit 0
fi
require_cmd rpmbuild mock rpm2cpio cpio rpm ukify sbsign sbverify openssl objdump objcopy strings cmp
load_hardware

SB_DIR="$BUILD_DIR/secureboot"; mkdir -p "$SB_DIR"
recorded_inputs() { rpm -qp --qf '%{DESCRIPTION}' "$1" 2>/dev/null | sed -n 's/^Inputs: //p' | head -1 || true; }

## 1. The stub
SRPM_IN="$CACHE_DIR/$SECUREBOOT_STUB_SRPM"
[ -s "$SRPM_IN" ] || die "missing $SRPM_IN (run scripts/10-fetch-sources.sh)"
verify_sha256 "$SRPM_IN" "$SECUREBOOT_STUB_SRPM_SHA256"
STUB_VERSION=$(rpm -qp --qf '%{VERSION}' "$SRPM_IN")
STUB_TAG="$STUB_VERSION-sp11.$SECUREBOOT_STUB_RELEASE"          # what the stub reports (the StubInfo variable)
STUB_EXPECT="$STUB_VERSION-$SECUREBOOT_STUB_RELEASE.fc$FEDORA_RELEASE"
STUB_PATCHES="$PAYLOAD_DIR/secureboot/stub"
ls "$STUB_PATCHES"/*.patch >/dev/null 2>&1 || die "no patch under $STUB_PATCHES"
STUB_INPUTS=$(printf '%s\n' "SECUREBOOT_STUB_SRPM_SHA256=$SECUREBOOT_STUB_SRPM_SHA256" \
  | inputs_sha256 "$SPEC_DIR/sp11-secureboot-stub.spec.in" "$STUB_PATCHES")
stub_rpm() { ls -t "$SB_DIR"/sp11-secureboot-stub-[0-9]*."$FEDORA_ARCH".rpm 2>/dev/null | head -1 || true; }
stub_current() {
  local r; r=$(stub_rpm)
  [ -n "$r" ] && [ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$r" 2>/dev/null)" = "$STUB_EXPECT" ]
}
if stub_current && [ "$(recorded_inputs "$(stub_rpm)")" != "$STUB_INPUTS" ]; then
  die "the stub's patch, its spec template or its source RPM changed since $(basename "$(stub_rpm)") was built, but SECUREBOOT_STUB_RELEASE is still $SECUREBOOT_STUB_RELEASE: bump it in sp11.conf (the stub reports its release, and the images built from it record it)"
fi
if [ "${FORCE:-0}" = 1 ] || ! stub_current; then
  SRC="$WORK_DIR/secureboot-stub-src"; rm -rf "$SRC"; mkdir -p "$SRC"
  ( cd "$SRC" && rpm2cpio "$SRPM_IN" | cpio -idm --quiet "./systemd-$STUB_VERSION.tar.gz" ) \
    || die "cannot unpack $SECUREBOOT_STUB_SRPM"
  [ -s "$SRC/systemd-$STUB_VERSION.tar.gz" ] || die "$SECUREBOOT_STUB_SRPM does not carry systemd-$STUB_VERSION.tar.gz"
  install -m 0644 "$STUB_PATCHES"/*.patch "$SRC/"      # applied by rpm/sp11-secureboot-stub.spec.in (%autosetup -p1)
  SRPM=$(build_srpm "$SPEC_DIR/sp11-secureboot-stub.spec.in" sp11-secureboot-stub "$SRC" \
    VERSION="$STUB_VERSION" RELEASE="$SECUREBOOT_STUB_RELEASE" VERSION_TAG="$STUB_TAG" INPUTS="$STUB_INPUTS")
  BUILT=$(mock_rebuild "$SRPM" sp11-secureboot-stub)
  # A build input, not a package for the device: out of the directory the hand-offs and the ISO are filled from.
  rm -f "$SB_DIR"/sp11-secureboot-stub-*.rpm
  mv "$BUILT" "$SB_DIR/"
  stub_current || die "the build did not produce sp11-secureboot-stub $STUB_EXPECT"
else
  log "stub already built: $(basename "$(stub_rpm)") (FORCE=1 to rebuild)"
fi
STUB_RPM=$(stub_rpm)
[ "$(recorded_inputs "$STUB_RPM")" = "$STUB_INPUTS" ] || die "$(basename "$STUB_RPM") does not record the inputs it was built from"
STUB="$SB_DIR/linuxaa64.efi.stub"
rpm2cpio "$STUB_RPM" | cpio -i --quiet --to-stdout ./usr/lib/sp11/secureboot/linuxaa64.efi.stub > "$STUB" \
  || die "cannot take the stub out of $(basename "$STUB_RPM")"
sections_of() { objdump -h "$1" | awk '$1 ~ /^[0-9]+$/ {print $2}' | tr '\n' ' '; }
case " $(sections_of "$STUB") " in *" .sbat "*) ;; *) die "the stub has no .sbat section (shim refuses such an image)" ;; esac
strings -a "$STUB" | grep -F "systemd-stub $STUB_TAG" >/dev/null || die "the stub does not report itself as $STUB_TAG"
STUB_SHA256=$(sha256_of "$STUB")
log "stub: systemd-stub $STUB_TAG, $(stat -c %s "$STUB") bytes, sha256 ${STUB_SHA256:0:16}…"

## 2. The image: kernel and device tree out of the kernel package under test, behind the stub, signed
KCORE=$(rpm_of kernel-core)
[ -n "$KCORE" ] && [ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$KCORE")" = "$KERNEL_ABI" ] \
  || die "no kernel-core RPM for $KERNEL_ABI in $RPM_DIR (run scripts/20-build-kernel.sh)"
KERNEL_EVR=$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$KCORE")
NAME="sp11-kernel-secureboot-$KERNEL_ABI"
EXPECT="1-$SECUREBOOT_IMAGE_RELEASE.fc$FEDORA_RELEASE"
CERT_SHA256=$(openssl x509 -in "$CRT" -outform DER | sha256sum | cut -d' ' -f1)
# What the package is built from. The signature is not part of it (sbsign records the signing time, so two
# builds of the same inputs differ there and nowhere else), and neither is the private key.
INPUTS=$(printf '%s\n' "STUB_INPUTS=$STUB_INPUTS" "KERNEL_CORE_SHA256=$(sha256_of "$KCORE")" "SP11_DTB=$SP11_DTB" \
  "CERT_SHA256=$CERT_SHA256" | inputs_sha256 "$SPEC_DIR/sp11-kernel-secureboot.spec.in")
addon_rpm() { ls -t "$RPM_DIR/$NAME"-[0-9]*."$FEDORA_ARCH".rpm 2>/dev/null | head -1 || true; }
addon_current() {
  local r; r=$(addon_rpm)
  [ -n "$r" ] && [ "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$r" 2>/dev/null)" = "$EXPECT" ]
}
if addon_current && [ "$(recorded_inputs "$(addon_rpm)")" != "$INPUTS" ]; then
  die "the stub, the kernel package, the device tree, the certificate or the spec template changed since $(basename "$(addon_rpm)") was built, but SECUREBOOT_IMAGE_RELEASE is still $SECUREBOOT_IMAGE_RELEASE: bump it in sp11.conf (dnf ignores a rebuild of the same release)"
fi
if [ "${FORCE:-0}" = 1 ] || ! addon_current; then
  if grep -q -- '-----BEGIN ENCRYPTED PRIVATE KEY-----' "$KEY" && ! { : < /dev/tty; } 2>/dev/null; then
    die "the signing key is encrypted and this run has no terminal for its passphrase: run scripts/25-build-secureboot-rpms.sh in a terminal"
  fi
  IMG="$WORK_DIR/secureboot-image"; rm -rf "$IMG"; mkdir -p "$IMG/rpm" "$IMG/src"
  ( cd "$IMG/rpm" && rpm2cpio "$KCORE" | cpio -idm --quiet "./lib/modules/$KERNEL_ABI/vmlinuz" \
      "./lib/modules/$KERNEL_ABI/dtb/$SP11_DTB" ) || die "cannot unpack $(basename "$KCORE")"
  VMLINUZ="$IMG/rpm/lib/modules/$KERNEL_ABI/vmlinuz"; DTB="$IMG/rpm/lib/modules/$KERNEL_ABI/dtb/$SP11_DTB"
  [ -s "$VMLINUZ" ] && [ -s "$DTB" ] || die "$(basename "$KCORE") lacks vmlinuz or $SP11_DTB"
  # No command line and no initramfs section: the stub then takes GRUB's arguments also with Secure Boot on, and
  # the initramfs is the device's own (dracut builds it there). No os-release either: the file names one kernel.
  # No hardware-ID table: ukify would build one from the host's systemd, for a choice among several device trees
  # that this file, with its one tree, does not make.
  ukify build --linux="$VMLINUZ" --stub="$STUB" --devicetree="$DTB" --os-release="" --hwids="" \
    --uname="$KERNEL_ABI" --output="$IMG/unsigned.efi" >"$IMG/ukify.log" 2>&1 \
    || { tail -20 "$IMG/ukify.log" >&2; die "ukify failed (log: $IMG/ukify.log)"; }
  sbsign --key "$KEY" --cert "$CRT" --output "$IMG/src/sp11-secureboot.efi" "$IMG/unsigned.efi" >"$IMG/sbsign.log" 2>&1 \
    || { tail -20 "$IMG/sbsign.log" >&2; die "sbsign failed (log: $IMG/sbsign.log)"; }
  openssl x509 -in "$CRT" -outform DER -out "$IMG/src/sp11-secureboot.der"
  # What the device's tool compares before it offers the image: the kernel the image holds must be the installed
  # one (a kernel rebuilt under the same version has other module keys, and its modules would be refused).
  printf '%s\n' "KERNEL=$KERNEL_ABI" "VMLINUZ_SHA256=$(sha256_of "$VMLINUZ")" "DTB=$SP11_DTB" "STUB=$STUB_TAG" \
    "CERT_SHA256=$CERT_SHA256" > "$IMG/src/sp11-secureboot.info"
  build_rpm "$SPEC_DIR/sp11-kernel-secureboot.spec.in" "$NAME" "$IMG/src" \
    KERNEL_ABI="$KERNEL_ABI" KERNEL_EVR="$KERNEL_EVR" RELEASE="$SECUREBOOT_IMAGE_RELEASE" SKU="$SP11_SKU" \
    DTB="${SP11_DTB##*/}" STUB="$STUB_TAG" CERT_SHA256="$CERT_SHA256" INPUTS="$INPUTS" >/dev/null
  addon_current || die "the build did not produce $NAME $EXPECT"
else
  log "add-on already built: $(basename "$(addon_rpm)") (FORCE=1 to rebuild)"
fi
RPM=$(addon_rpm)
[ "$(recorded_inputs "$RPM")" = "$INPUTS" ] || die "$(basename "$RPM") does not record the inputs it was built from"
# One kernel's set in build/rpms/: the add-ons of earlier kernel builds go, as their kernel packages went.
for old in "$RPM_DIR"/sp11-kernel-secureboot-*.rpm; do
  [ -e "$old" ] || continue
  case "$old" in "$RPM_DIR/$NAME"-[0-9]*) ;; *) log "removing $(basename "$old") (not for $KERNEL_ABI)"; rm -f "$old" ;; esac
done

## 3. Check the package on every run, cached or not: the signature, what the file holds, what the package says
T="$WORK_DIR/secureboot-check"; rm -rf "$T"; mkdir -p "$T"
( cd "$T" && rpm2cpio "$RPM" | cpio -idm --quiet ) || die "cannot unpack $(basename "$RPM")"
F="$T/lib/modules/$KERNEL_ABI"
[ -s "$F/sp11-secureboot.efi" ] && [ -s "$F/sp11-secureboot.der" ] && [ -s "$F/sp11-secureboot.info" ] \
  || die "$(basename "$RPM") lacks one of its three files"
sbverify --cert "$CRT" "$F/sp11-secureboot.efi" >"$T/sbverify.log" 2>&1 \
  || { cat "$T/sbverify.log" >&2; die "the image in $(basename "$RPM") does not verify against $CRT"; }
[ "$(sha256_of "$F/sp11-secureboot.der")" = "$CERT_SHA256" ] || die "the certificate in $(basename "$RPM") is not the one of $CRT"
SECTIONS=" $(sections_of "$F/sp11-secureboot.efi") "
for s in .linux .dtb .sbat .uname; do
  case "$SECTIONS" in *" $s "*) ;; *) die "the image has no $s section (sections:$SECTIONS)" ;; esac
done
for s in .cmdline .initrd .hwids .dtbauto .osrel; do
  case "$SECTIONS" in *" $s "*) die "the image carries a $s section, which the image proven on the device does not (.cmdline and .initrd would make the stub ignore GRUB's arguments or the device's initramfs)" ;; esac
done
( cd "$T" && rpm2cpio "$KCORE" | cpio -idm --quiet "./lib/modules/$KERNEL_ABI/vmlinuz" "./lib/modules/$KERNEL_ABI/dtb/$SP11_DTB" )
# A section's file size is its content padded to the file alignment: compare the content's own length.
section_is() {  # section_is SECTION FILE: is the section's content the file, byte for byte?
  objcopy -O binary --only-section="$1" "$F/sp11-secureboot.efi" "$T/section.bin" 2>/dev/null || return 1
  cmp -s -n "$(stat -c %s "$2")" "$T/section.bin" "$2"
}
section_is .linux "$F/vmlinuz" || die "the image's kernel is not the vmlinuz of $(basename "$KCORE")"
section_is .dtb "$F/dtb/$SP11_DTB" || die "the image's device tree is not $SP11_DTB of $(basename "$KCORE")"
grep -qx "VMLINUZ_SHA256=$(sha256_of "$F/vmlinuz")" "$F/sp11-secureboot.info" || die "sp11-secureboot.info names another kernel image"
rpm -qp --requires "$RPM" | grep -qx "kernel-core = $KERNEL_EVR" || die "$(basename "$RPM") does not require kernel-core = $KERNEL_EVR"
log "add-on RPM: $(basename "$RPM") ($(du -h "$RPM" | cut -f1)); image $(stat -c %s "$F/sp11-secureboot.efi") bytes, sections:${SECTIONS}signed by certificate ${CERT_SHA256:0:16}…"
rm -rf "$T"

## 4. The device side (the support RPM's tool, the kernel-install plugin, a kernel's removal) is step 26's part.
##    Like step 36 it needs the support RPM of this tree and a live root that carries another kernel than the one
##    under test, so it is run by hand for a kernel that goes to an installed system.
log "next: scripts/26-verify-secureboot-rpms.sh (with the support RPM of scripts/30-build-support-rpm.sh built)"
