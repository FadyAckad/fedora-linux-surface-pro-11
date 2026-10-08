# Build

Building the ISO on the Surface itself: the requirements, the pipeline and its options, the steps and the checks.
Also building the kernel, support, pen daemon or sensors RPMs alone. What each step does underneath, its caches and
the pitfalls are in [`docs/pipeline.md`](../pipeline.md).

## Requirements

- A Fedora aarch64 distribution in WSL on the Surface (tested with Fedora 44).
- Windows interop (`powershell.exe`).
- `sudo`, passwordless for unattended runs.
- 80 GiB free disk space (the kernel's mock buildroot takes about 40).
- Internet access.

Step 00 checks the host and installs the build dependencies.

## Running the pipeline

Before the first ISO on a unit, export its sensor registry and calibration from Windows. The ADSP wrote them under
`DriverData\Qualcomm\fastRPC`, readable only elevated, so the export asks for one UAC prompt. They belong to this
unit; keep them private ([`docs/guide/sensors.md`](sensors.md)):

```bash
scripts/75-export-sensor-registry.sh
```

Then:

```bash
scripts/build-all.sh
```

Steps 00 to 45 skip finished work, and `FORCE=1` rebuilds one of them. Step 50 and the checks always run. The
kernel build takes about an hour after the downloads. WSL has to keep running meanwhile, or the build stops and
starts over on the next run. Two settings in `sp11.conf`, also accepted from the environment, select the source
media:

- `FEDORA_TARGET`: which Fedora 45 media to build from.
  - `beta` (default): the Fedora 45 Beta, `releases/test/45_Beta/`.
  - `ga`: `releases/45/`. It needs `FEDORA_COMPOSE=<n.m>` until the 45 GA compose is pinned in `sp11.conf`.
  - `nightly`: `development/45/`. It needs `FEDORA_COMPOSE=<stamp>`.

  Only Fedora 45 is supported: the kernel source RPM is pinned per release. A release other than the host's is
  fine: the kernel, `sp11-iptsd` and the sensors libraries are built in `mock` buildroots of the target release.
- `FEDORA_EDITION`: `Workstation` (default), `KDE-Desktop` (the KDE Plasma Desktop edition) or a Fedora spin,
  named as in its ISO file name. The kernel and RPMs are the same for every edition and are reused:
  `FEDORA_EDITION=KDE-Desktop scripts/build-all.sh` downloads the KDE image and remasters it. The KDE image was
  installed on the tested unit on 2026-09-30 ([`docs/verified.md`](../verified.md)). No spin has been tested; step
  50 stops on a spin whose image ships no Firefox for the installer (LXQt and SoaS in 45 Beta,
  [`docs/fedora-media.md`](../fedora-media.md)).

`build/rpms/` holds the RPMs of one Fedora release at a time: copy them elsewhere before building for another
release.

## Steps

1. `scripts/00-setup-host.sh` installs the build dependencies and checks the host.
2. `scripts/05-detect-hardware.sh` reads SKU, panel and Bluetooth address from Windows, checks them
   against the supported models and writes `build/hardware.env`.
3. `scripts/10-fetch-sources.sh` downloads and verifies the sources: the Fedora ISO, Fedora's kernel and
   iio-sensor-proxy source RPMs (checksums pinned in `sp11.conf`), the audio files, the SP11 patch set from the
   kernel fork's pinned commit, the pinned checkouts (iptsd, OE, hexagonrpc, libssc) and the Bluetooth helper
   source, plus the runtime packages the live root and the sensors stack need, with dnf.
4. `scripts/20-build-kernel.sh` rebuilds Fedora's kernel source RPM into Fedora's kernel packages, in a mock
   buildroot of the target release, with the patch set, `payload/kernel-local` and the buildid `.sp11.<revision>`.
   `sp11.conf` pins the content of the declared revision (`KERNEL_SP11_REV_SHA256`): a changed patch set or
   `kernel-local` without a new revision stops the step.
5. `scripts/30-build-support-rpm.sh` builds `sp11-surface-support`: the firmware from the Windows DriverStore, the
   audio topology and UCM, the Wi-Fi board data, the Bluetooth address service, the boot policy (kernel-install
   plugin, dracut and module settings, the dnf override that keeps stock kernels off the system), the Windows GRUB
   entry, the first-boot service, `sp11-bt-import-pairings` and `sp11-diag`. The step rebuilds when its `VERSION=`
   or the target Fedora release changes, refuses to rebuild the same version from a changed payload, and then runs
   `scripts/35-verify-support-rpm.sh` (see Checks) when a live root is there.
6. `scripts/40-build-iptsd-rpm.sh` builds `sp11-iptsd`: pinned upstream iptsd with ooaklee's Surface
   Pro 11 integration.
7. `scripts/45-build-sensors-rpms.sh` builds the sensors stack: `hexagonrpc`, `libssc` and the SSC-enabled
   `iio-sensor-proxy` in a mock buildroot of the target release, and `sp11-sensors` from this unit's registry
   export (step 75) and the Windows sensor configuration. The step runs `scripts/46-verify-sensors-rpms.sh` when a
   live root is there.
8. `scripts/50-build-iso.sh` builds the ISO: it replaces the live root's stock kernel packages with the SP11 build
   of the same packages, installs the support, iptsd and sensors RPMs, builds the live initramfs, adds the device
   tree, the kernel arguments and the console font to Fedora's own live GRUB menu, then assembles the ISO and
   implants the media-check checksum. The result is, for example,
   `build/out/Fedora-Workstation-Live-45_Beta-1.3-SP11-7.2.9-300.sp11.11.fc45.aarch64.iso`, plus `.sha256`.

## Checks

`build-all.sh` runs the steps above and then `scripts/35-verify-support-rpm.sh` and
`scripts/46-verify-sensors-rpms.sh`. `scripts/36-verify-kernel-install.sh` and `scripts/60-verify-rootfs.sh` run by
hand. Each check works in an overlay of the live root that step 50 extracts, so it never touches the host. What
each one installs and asserts is in [`docs/pipeline.md`](../pipeline.md).

- Step 35 installs the support RPM the two ways it reaches a machine, with its scriptlets over the version the live
  root carries, as `dnf upgrade` does, and without them, as step 50 does, and checks the GRUB policy and the
  repository override on the result. `SUPPORT_PREVIOUS_RPM=<rpm>` first installs an earlier build, for a real
  upgrade.
- Step 46 installs the sensors RPMs with their scriptlets and checks the result. `SENSORS_PREVIOUS_RPMS=<rpms>`
  adds an upgrade from an earlier release.
- Step 36 is for kernel RPMs built for an existing installation. It installs them next to the live root's kernel as
  `dnf install` does, then the support RPM, and checks the boot entries, the initramfs, the GRUB default and menu,
  and that removing the new kernel puts the previous one back.
- Step 60 is optional and checks the root that step 50 left behind: packages and binaries, the installer and its
  viewer, the firmware, the SP11 kernel in place of the stock one, the sensors stack and the boot configuration an
  installation would get.

## Building the kernel RPMs alone

`build-all.sh` builds them in step 20. Build only them for a system that is already installed, once `sp11.conf`
names a newer Fedora kernel or `KERNEL_SP11_REV` than that system runs. A full `scripts/build-all.sh` run has to
come first: it provides the host setup, the downloads and the live root the check installs into. Use its
`FEDORA_TARGET` and `FEDORA_EDITION`, since step 10 also fetches the image they name when the cache lacks it:

```bash
scripts/10-fetch-sources.sh
```

```bash
scripts/20-build-kernel.sh
```

Step 20 builds when `build/rpms/` holds no `kernel-core` of the configured version (about an hour, with WSL running
throughout); otherwise it only repeats its checks. A patch set or `payload/kernel-local` of your own needs a new
revision first: [`docs/guide/new-release.md`](new-release.md).

Then step 36 (see Checks) installs the packages next to the live root's kernel. Pass the support RPM of
`build/rpms/` as `SUPPORT_PREVIOUS_RPM`, so that it is installed first and writes the GRUB menu an installed system
has; the live root's own menu, Fedora's, fails the menu check:

```bash
SUPPORT_PREVIOUS_RPM=$(ls build/rpms/sp11-surface-support-*.rpm) scripts/36-verify-kernel-install.sh
```

The step ends with `kernel packages verified on an installed system next to` and the live root's kernel. That
kernel must not be the kernel under test, so after an ISO build with the new kernel the step does not apply. Copy
the five packages the ISO installs (`kernel`, `kernel-core`, `kernel-modules-core`, `kernel-modules`,
`kernel-modules-extra`) from `build/rpms/` to the installed system and install them there:
[`docs/guide/update.md`](update.md).

## Building the support RPM alone

`build-all.sh` builds it in step 30. Build only it once `VERSION=` in `scripts/30-build-support-rpm.sh` is newer
than the installed system's; bump it with every change to the payload, because `dnf upgrade` acts on the version
alone. A full `scripts/build-all.sh` run has to come first, as for the kernel, and step 10 after a change to
`sp11.conf`:

```bash
scripts/30-build-support-rpm.sh
```

The step builds when `build/rpms/` holds no support RPM of that version for the target Fedora release, stops when
the payload changed without a new version, and then runs step 35 (see Checks). To check the upgrade the installed
system will make, pass the support RPM that system runs: a copy kept from its build (a new build removes the older
RPM from `build/rpms/`) or the one on its ISO under `/sp11/rpms`:

```bash
SUPPORT_PREVIOUS_RPM=<rpm> scripts/35-verify-support-rpm.sh
```

Copy `build/rpms/sp11-surface-support-<version>-1.fc<release>.aarch64.rpm` to the installed system and upgrade it
there: [`docs/guide/update.md`](update.md).

## Building the pen daemon RPM alone

`build-all.sh` builds `sp11-iptsd` in step 40. Build only it once `sp11.conf` pins another iptsd commit or
`IPTSD_RPM_RELEASE`. A full `scripts/build-all.sh` run has to come first, then step 10, which moves the checkouts
to the pinned commits. Use that run's `FEDORA_TARGET` and `FEDORA_EDITION`, as for the kernel:

```bash
scripts/10-fetch-sources.sh
```

```bash
scripts/40-build-iptsd-rpm.sh
```

Step 40 builds when `build/rpms/` holds no `sp11-iptsd` of the pinned version, release and commit, in a mock
buildroot of the target release when the host runs another Fedora. Copy the RPM to the installed system; upgrading
it there restarts the pen daemon: [`docs/guide/update.md`](update.md).

## Building the sensors RPMs alone

`build-all.sh` builds them in step 45. Rebuild only them after a full `scripts/build-all.sh` run, with the
`FEDORA_TARGET` of the installed system. The library RPMs are built in a mock buildroot of that release, so the
first run takes a while:

```bash
FEDORA_TARGET=beta scripts/45-build-sensors-rpms.sh
```

This builds `hexagonrpc` (from this project's fork, see [`docs/guide/credits.md`](credits.md)), `libssc`,
`iio-sensor-proxy` (Fedora's own source RPM with `-Dssc-support=enabled` and this project's sleep patch) and
`sp11-sensors`, and verifies them in the extracted live root. `SENSORS_VERSION` in `sp11.conf` versions
`sp11-sensors`; a changed payload at the same version stops the step, as does a change in Fedora's iio-sensor-proxy
spec until the template is refreshed.
Installing them: [`docs/guide/sensors.md`](sensors.md).
