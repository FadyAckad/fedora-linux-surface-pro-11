# Build

Building the ISO on the Surface itself: requirements, the pipeline and its options, the steps, the checks, and
building the sensors RPMs alone. What each step does underneath, its caches and the pitfalls are in
[`docs/pipeline.md`](../pipeline.md).

## Requirements

A Fedora aarch64 distribution in WSL on the Surface (tested with Fedora 44), Windows interop (`powershell.exe`),
`sudo` (passwordless for unattended runs), 80 GiB free disk space (the kernel's mock buildroot takes about 40) and
internet access. Step 00 checks the host and installs the build dependencies.

## Running the pipeline

Before the first ISO on a unit, export its sensor registry and calibration from Windows (one UAC prompt: the ADSP
wrote them under `DriverData\Qualcomm\fastRPC`, readable only elevated; per unit, keep them private). The media
carries them ([`docs/guide/sensors.md`](sensors.md)):

```bash
scripts/75-export-sensor-registry.sh
```

Then:

```bash
scripts/build-all.sh
```

Steps 00 to 45 skip finished work and `FORCE=1` rebuilds one; step 50 and the checks always run. The kernel build
takes about an hour after the downloads; WSL has to keep running, or it stops and starts over on the next run. Two
settings in `sp11.conf`, also accepted from the environment, select the source media:

- `FEDORA_TARGET`: `beta` (default, the Fedora 45 Beta, `releases/test/45_Beta/`), `ga` (`releases/45/`, needs
  `FEDORA_COMPOSE=<n.m>` until the 45 GA compose is pinned in `sp11.conf`) or `nightly` (`development/45/`, needs
  `FEDORA_COMPOSE=<stamp>`). Only Fedora 45 is supported: the kernel source RPM is pinned per release. A release
  other than the host's is fine: the kernel, `sp11-iptsd` and the sensors libraries are built in `mock` buildroots
  of the target release.
- `FEDORA_EDITION`: `Workstation` (default) or a Fedora spin, named as in its ISO file name. The kernel
  and RPMs are the same for every edition. The KDE edition has its own mirror layout and is not covered.

`build/rpms/` holds the RPMs of one Fedora release at a time: copy them elsewhere before building for another
release.

## Steps

1. `scripts/00-setup-host.sh` installs the build dependencies and checks the host.
2. `scripts/05-detect-hardware.sh` reads SKU, panel and Bluetooth address from Windows, checks them
   against the supported models and writes `build/hardware.env`.
3. `scripts/10-fetch-sources.sh` downloads and verifies the Fedora ISO, Fedora's kernel source RPM (checksum pinned
   in `sp11.conf`), the audio files, the SP11 patch set from the kernel fork's pinned commit (written out as a patch
   series and checked against the commit's tree), the pinned checkouts (iptsd, OE, hexagonrpc, libssc) and the
   Bluetooth helper source, and fetches with dnf, per Fedora release and again with `FORCE=1`, `atheros-firmware`,
   the runtime packages the live image may lack, the iio-sensor-proxy source RPM and the sensors' runtime
   dependencies.
4. `scripts/20-build-kernel.sh` rebuilds Fedora's kernel source RPM with that patch series (the spec's
   `linux-kernel-test.patch`), `payload/kernel-local` (the spec's `kernel-local`) and the buildid
   `.sp11.<revision>`, in a mock buildroot of the target release, into Fedora's kernel packages, and checks that the
   configuration is Fedora's plus exactly `kernel-local`. `sp11.conf` pins the content of the declared revision
   (`KERNEL_SP11_REV_SHA256`); a changed patch set or `kernel-local` without a new revision stops the step.
5. `scripts/30-build-support-rpm.sh` builds `sp11-surface-support`: firmware from the Windows DriverStore, audio
   topology and UCM, Wi-Fi board data, Bluetooth address service, boot policy (kernel-install plugin, dracut and
   `modules-load.d` settings, the dnf repository override that keeps stock kernels off the system), the Windows GRUB
   entry, the first-boot service, `sp11-bt-import-pairings` and `sp11-diag`. It rebuilds when its `VERSION=` or the
   target Fedora release changes, refuses to rebuild the same version from a changed payload (the payload's hash is
   recorded in the RPM), and then runs `scripts/35-verify-support-rpm.sh` (see Checks) when a live root is there.
6. `scripts/40-build-iptsd-rpm.sh` builds `sp11-iptsd`: pinned upstream iptsd with ooaklee's Surface
   Pro 11 integration.
7. `scripts/45-build-sensors-rpms.sh` builds the sensors stack: `hexagonrpc`, `libssc` and the SSC-enabled
   `iio-sensor-proxy` in a mock buildroot of the target release, and `sp11-sensors` from this unit's registry
   export (step 75) and the Windows sensor configuration; it runs `scripts/46-verify-sensors-rpms.sh` when a
   live root is there.
8. `scripts/50-build-iso.sh` replaces the live root's stock kernel packages with the SP11 build of the same
   packages, installs the support, iptsd and sensors RPMs (the sensors stack stays inert on the live media), builds
   the live initramfs, adds the device tree, the kernel arguments and the console font to Fedora's own live GRUB
   menu, assembles the ISO and implants the media-check checksum, for example
   `build/out/Fedora-Workstation-Live-45_Beta-1.3-SP11-7.2.7-300.sp11.5.fc45.aarch64.iso`, plus `.sha256`. The file
   name carries the edition, so images of different editions coexist.

## Checks

`build-all.sh` runs the steps above and then `scripts/35-verify-support-rpm.sh` and
`scripts/46-verify-sensors-rpms.sh`; `scripts/36-verify-kernel-install.sh` and `scripts/60-verify-rootfs.sh` run by
hand. Each works in an overlay of the live root step 50 extracts, so it never touches the host; what each one
asserts in detail is in [`docs/pipeline.md`](../pipeline.md).

- Step 35 installs the support RPM the two ways it reaches a machine: with its scriptlets over the version the live
  root carries, as `dnf upgrade` does (after step 50 that is the same version, installed again;
  `SUPPORT_PREVIOUS_RPM=<rpm>` first installs an earlier build for a real upgrade), and without scriptlets, as step
  50 does. It checks that the GRUB policy values in `sp11.conf` reach `/etc/default/grub` and the generated menu (a
  deliberately wrong policy is staged first, so a package that installs without applying it cannot pass), and that
  the repository override hides a stock kernel from repositories but not from a local RPM.
- Step 46 installs the sensors RPMs with their scriptlets and checks linkage, units, rules, the policy module, the
  working directory and the payload; `SENSORS_PREVIOUS_RPMS=<rpms>` adds an upgrade from an earlier release.
- Step 36, for kernel RPMs built for an existing installation, installs the kernel packages the way `dnf install`
  does, next to the kernel already there and with their scriptlets, then the support RPM, and checks both packages,
  the boot entry with the Denali DTB, the initramfs and the kernel arguments, the new kernel as the saved GRUB
  default, the regenerated menu, and that removing the new kernel puts the previous one back.
- Step 60, optional, checks the root step 50 left behind: RPM dependencies, loadable binaries, the installer, the
  firmware against the device tree, the SP11 build in place of the stock kernel, the sensors stack, the boot entry
  and GRUB settings an installation would get (Denali DTB, kernel arguments) and the Windows GRUB entry.

## Building the sensors RPMs alone

`build-all.sh` builds them in step 45. To rebuild only them, after a full `scripts/build-all.sh` run with the same
`FEDORA_TARGET` (host setup, the downloads for that release, and the live root the verification installs into) and
with the `FEDORA_TARGET` of the installed system (the library RPMs are built in a mock buildroot of that release, so
the first run takes a while):

```bash
FEDORA_TARGET=beta scripts/45-build-sensors-rpms.sh
```

This builds `hexagonrpc` (from this project's fork, see [`docs/guide/credits.md`](credits.md)), `libssc`,
`iio-sensor-proxy` (Fedora's own source RPM with `-Dssc-support=enabled`) and `sp11-sensors` (the Windows sensor
configuration, the registry, the platform identity, and the udev, systemd, SELinux and dnf files) and verifies them
in the extracted live root. `SENSORS_VERSION` in `sp11.conf` versions `sp11-sensors`; a changed payload at the same
version stops the step, and a change in Fedora's iio-sensor-proxy spec stops it until the template is refreshed.
Installing them: [`docs/guide/sensors.md`](sensors.md).
