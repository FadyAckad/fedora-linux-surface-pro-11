# Build

Building the ISO on the Surface itself: requirements, the pipeline and its options, the steps, the checks, and
building the kernel, support, pen daemon or sensors RPMs alone. What each step does underneath, its caches and the
pitfalls are in [`docs/pipeline.md`](../pipeline.md).

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
- `FEDORA_EDITION`: `Workstation` (default), `KDE-Desktop` (the KDE Plasma Desktop edition) or a Fedora spin,
  named as in its ISO file name. The kernel and RPMs are the same for every edition, and the RPMs already built are
  reused: `FEDORA_EDITION=KDE-Desktop scripts/build-all.sh` downloads the KDE image and remasters it. The KDE image
  was installed on the tested unit on 2026-09-30 ([`docs/verified.md`](../verified.md)); its installer is set to
  open in Firefox, as on Workstation, because Fedora's own viewer for KDE drew it corrupted
  ([`docs/fedora-media.md`](../fedora-media.md)). No spin has been tested, and step 50 stops on one whose image
  ships no Firefox for the installer (LXQt and SoaS in 45 Beta).

`build/rpms/` holds the RPMs of one Fedora release at a time: copy them elsewhere before building for another
release.

## Steps

1. `scripts/00-setup-host.sh` installs the build dependencies and checks the host.
2. `scripts/05-detect-hardware.sh` reads SKU, panel and Bluetooth address from Windows, checks them
   against the supported models and writes `build/hardware.env`.
3. `scripts/10-fetch-sources.sh` downloads and verifies the Fedora ISO, Fedora's kernel and iio-sensor-proxy
   source RPMs (checksums pinned in `sp11.conf`), the audio files, the SP11 patch set from the kernel fork's pinned
   commit (written out as a patch series and checked against the commit's tree), the pinned checkouts
   (iptsd, OE, hexagonrpc, libssc) and the Bluetooth helper source, and fetches with dnf, per Fedora release and
   again with `FORCE=1`, `atheros-firmware`, the runtime packages the live image may lack and the sensors' runtime
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
   `build/out/Fedora-Workstation-Live-45_Beta-1.3-SP11-7.2.8-300.sp11.10.fc45.aarch64.iso`, plus `.sha256`. The file
   name carries the edition, so images of different editions coexist.

## Checks

`build-all.sh` runs the steps above and then `scripts/35-verify-support-rpm.sh` and
`scripts/46-verify-sensors-rpms.sh`; `scripts/36-verify-kernel-install.sh` and `scripts/60-verify-rootfs.sh` run by
hand. Each works in an overlay of the live root step 50 extracts, so it
never touches the host; what each one asserts in detail is in [`docs/pipeline.md`](../pipeline.md).

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
- Step 60, optional, checks the root step 50 left behind: RPM dependencies, loadable binaries, the installer and
  the viewer it opens in (Firefox), the firmware against the device tree, the SP11 build in place of the stock
  kernel, the sensors stack, the boot entry and GRUB settings an installation would get (Denali DTB, kernel
  arguments) and the Windows GRUB entry.

## Building the kernel RPMs alone

`build-all.sh` builds them in step 20. To build only them, for a system that is already installed, once
`sp11.conf` names a newer Fedora kernel or `KERNEL_SP11_REV` than that system runs: after a full
`scripts/build-all.sh` run (host setup, the downloads, and the live root the check installs into), and with the
`FEDORA_TARGET` and `FEDORA_EDITION` of that run, since step 10 also fetches the image they name when the cache
lacks it:

```bash
scripts/10-fetch-sources.sh
```

```bash
scripts/20-build-kernel.sh
```

Step 10 fetches what the kernel pins name (Fedora's source RPM, its `kernel-core`, the SP11 patch series). Step 20
builds when `build/rpms/` holds no `kernel-core` of the configured version, which takes about an hour with WSL
running throughout, and otherwise only repeats its checks. A patch set or `payload/kernel-local` of your own needs
a new revision first: [`docs/guide/new-release.md`](new-release.md).

Then step 36 (see Checks) installs the packages next to the live root's kernel. After an ISO build the live root
already carries the support RPM of `build/rpms/`: pass it as `SUPPORT_PREVIOUS_RPM`, so that it is installed again
first and writes the GRUB menu an installed system has (the live root's own menu is Fedora's, and the menu check
fails on it):

```bash
SUPPORT_PREVIOUS_RPM=$(ls build/rpms/sp11-surface-support-*.rpm) scripts/36-verify-kernel-install.sh
```

The step ends with `kernel packages verified on an installed system next to` and the live root's kernel, which
must not be the kernel under test: after an ISO build with the new kernel it does not apply. Copy the five
packages the ISO installs (`kernel`, `kernel-core`, `kernel-modules-core`, `kernel-modules`,
`kernel-modules-extra`) from `build/rpms/` to the installed system and install them there:
[`docs/guide/update.md`](update.md).

## Building the support RPM alone

`build-all.sh` builds it in step 30. To build only it, once `VERSION=` in `scripts/30-build-support-rpm.sh` is
newer than the installed system's (bump it with every change to the payload): after a full `scripts/build-all.sh`
run, which leaves `build/hardware.env`, the downloads and the live root the check installs into (after a change to
`sp11.conf`, run step 10 first, as for the kernel):

```bash
scripts/30-build-support-rpm.sh
```

The step also reads this unit's firmware from the Windows DriverStore. It builds when `build/rpms/` holds no
support RPM of that version for the target Fedora release, and stops when the payload changed without a new
version, because `dnf upgrade` acts on the version alone. It then runs step 35 (see Checks) itself, which upgrades
from the version the live root carries. To check the upgrade the installed system will make, pass the support RPM
that system runs: a copy kept from its build (a new build removes the older RPM from `build/rpms/`) or the one on
its ISO under `/sp11/rpms`:

```bash
SUPPORT_PREVIOUS_RPM=<rpm> scripts/35-verify-support-rpm.sh
```

Copy `build/rpms/sp11-surface-support-<version>-1.fc<release>.aarch64.rpm` to the installed system and upgrade it
there: [`docs/guide/update.md`](update.md).

## Building the pen daemon RPM alone

`build-all.sh` builds `sp11-iptsd` in step 40. To build only it, once `sp11.conf` pins another iptsd commit or
`IPTSD_RPM_RELEASE`: after a full `scripts/build-all.sh` run and step 10, which moves the checkouts to the pinned
commits (with that run's `FEDORA_TARGET` and `FEDORA_EDITION`, as for the kernel):

```bash
scripts/10-fetch-sources.sh
```

```bash
scripts/40-build-iptsd-rpm.sh
```

Step 40 builds when `build/rpms/` holds no `sp11-iptsd` of the pinned version, release and commit, in a mock
buildroot of the target release when the host runs another Fedora, and refuses a result that requires the host's
`fmt` or `spdlog` libraries. Copy the RPM to the installed system; upgrading it there restarts the pen daemon:
[`docs/guide/update.md`](update.md).

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
