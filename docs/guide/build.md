# Build

Building the ISO on the Surface itself: the requirements, the pipeline and its options, the steps and the checks.
Building one set of RPMs alone, for a system that is already installed: [`docs/guide/build-rpms.md`](build-rpms.md).
What each step does underneath, its caches and the pitfalls: [`docs/pipeline.md`](../pipeline.md).

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
kernel build takes about an hour after the downloads; WSL has to keep running meanwhile, or the build stops and
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
2. `scripts/05-detect-hardware.sh` reads SKU, panel and Bluetooth address from Windows, checks them against the
   supported models and writes `build/hardware.env`. The SKU decides the device tree (the 5G SKU's carries its
   modem) and whether the support RPM carries the modem's files.
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
   entry, the first-boot service, `sp11-bt-import-pairings` and `sp11-diag`; on the 5G SKU also the modem's udev
   rule and the GNSS feed. The step rebuilds when its `VERSION=` or the target Fedora release changes, refuses to
   rebuild the same version from a changed payload, and then runs step 35 (see Checks) when a live root is there.
6. `scripts/40-build-iptsd-rpm.sh` builds `sp11-iptsd`: pinned upstream iptsd with ooaklee's Surface Pro 11
   integration.
7. `scripts/45-build-sensors-rpms.sh` builds the sensors stack: `hexagonrpc`, `libssc` and the SSC-enabled
   `iio-sensor-proxy` in a mock buildroot of the target release, and `sp11-sensors` from this unit's registry
   export (step 75) and the Windows sensor configuration. The step runs step 46 when a live root is there.
8. `scripts/50-build-iso.sh` builds the ISO: it replaces the live root's stock kernel packages with the SP11 build
   of the same packages, installs the support, iptsd and sensors RPMs, builds the live initramfs, adds the device
   tree, the kernel arguments and the console font to Fedora's own live GRUB menu, then assembles the ISO and
   implants the media-check checksum. The result is, for example,
   `build/out/Fedora-Workstation-Live-45_Beta-1.3-SP11-7.2.11-300.sp11.8.fc45.aarch64.iso`, plus `.sha256`.

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
