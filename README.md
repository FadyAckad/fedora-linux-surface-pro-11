# Fedora Live ISO for Surface Pro 11 (Snapdragon X Elite, OLED, incl. the 5G SKU)

![Screenshot showing the About section](https://github.com/fadyackad/fedora-linux-surface-pro-11/blob/main/images/Screenshot.png)

Builds a Fedora 45 live ISO (aarch64) that boots and installs on a Microsoft Surface Pro, 11th Edition with the
Samsung OLED panel (Snapdragon X Elite X1E80100). The kernel is Fedora's own kernel package
(`kernel-7.2.5-300.fc45`) with Fedora's configuration, rebuilt with the Surface Pro 11 patch set (touchscreen and
pen, audio, device tree, and fixes for display, USB-C, suspend and the tablet-mode switch, extracted from
[ooaklee/linux_ms_dev_kit-sp11](https://github.com/ooaklee/linux_ms_dev_kit-sp11) and the upstream work it carries,
kept as a branch of the project's kernel fork; see `docs/kernel-patches.md`) and three drivers added to Fedora's
configuration (`files/kernel-local`): `7.2.5-300.sp11.4.fc45.aarch64`, installed as Fedora's usual `kernel`,
`kernel-core` and `kernel-modules*` packages. GRUB loads the Denali OLED device tree. The build runs on the Surface
itself, in WSL (Fedora aarch64): the kernel builds natively in a mock buildroot of the target release, and the
unit's identity, Bluetooth address and device firmware come from its Windows installation, so every ISO is tailored
to the unit that built it.

## Verified

Tested on the 5G SKU (`Surface_Pro_with_5G_11th_Edition_2077`) with the Fedora-based kernel above in its current
revision 4 (`7.2.5-300.sp11.4.fc45.aarch64`) and support RPM 3.2, installed fresh from the ISO built on 2026-09-24.
`docs/verified.md` has the details and what was confirmed with earlier kernels, including ooaklee's v23 tree the
project built until 2026-09-22.

| Feature | Fedora 45 Beta Workstation, Fedora's 7.2.5-300 (sp11.4) |
|---|:-:|
| Boot from the internal NVMe drive | yes |
| Display with GPU acceleration | yes |
| Backlight (brightness slider) | yes |
| Wi-Fi | yes |
| Bluetooth | yes |
| Touchscreen | yes |
| Multi-touch (pinch, two-finger scroll) | yes |
| Pen | yes |
| Speakers | yes |
| Microphone | yes |
| Keyboard and touchpad | yes |
| Battery status | yes |
| Power profiles (GNOME's Power Mode sets the Surface's platform profile) | yes |
| USB-C charging and data | yes |
| Suspend and resume | yes |
| Flatpak | yes |
| Windows in the GRUB menu | yes |
| Flex Keyboard and Slim Pen 2 pairings shared with Windows | yes |
| Sensors: readings from the accelerometer, gyroscope, magnetometer/compass and ambient light sensor (`ssccli`, `monitor-sensor`), with the sensors RPMs | yes |
| Sensors: auto-rotation on the desktop with the keyboard folded back or detached (GNOME's auto-rotate button), with the sensors RPMs | yes |
| Tablet mode: keyboard and touchpad off while the keyboard is folded back | yes |
| Sensors: automatic screen brightness | yes |
| 5G modem | no |
| Cameras | no |
| NPU (AI acceleration) | no |

*yes*: confirmed on the tested unit. *no*: not covered by this project.

In the live session, audio and battery status are unavailable because the audio DSP stays off while
running from USB-C; both work once installed.

## Status and scope

- Unofficial community project, not affiliated with Microsoft, Qualcomm, Fedora or ooaklee. No warranty.
- Tested only on the 5G OLED SKU. The hardware checks also accept the non-5G OLED SKUs
  (`Surface_Pro_11th_Edition_2076`, `Surface_Pro_11th_Edition_For_Business_2085`), which share the
  device tree, firmware file names and digitizer IDs; no build from one has been reported. The X1P64100
  LCD variant uses a different device tree and is rejected.
- Secure Boot must be disabled: the kernel is a local build of Fedora's kernel package and is not signed.
- Windows must stay on the device. The build reads the hardware identity, the built-in radio's Bluetooth
  address and the ADSP/CDSP/GPU firmware from it; without that firmware an installed system has no audio,
  battery reporting or GPU acceleration. The sensors packages also take the sensor configuration and this
  unit's sensor registry from it.
- The support RPM and the ISO contain proprietary Qualcomm firmware copied from your own Windows
  installation. Do not redistribute them; point other people to this repository instead.

## Build

Requirements: WSL with Fedora 44 aarch64 on the Surface, Windows interop (`powershell.exe`), `sudo`
(passwordless for unattended runs), 80 GiB free disk space (the kernel's mock buildroot takes about 40) and internet
access.

```bash
scripts/build-all.sh
```

Steps 1–7 skip finished work and `FORCE=1` rebuilds one; step 8 and the checks always run. Before the first ISO
on a unit, run `scripts/75-export-sensor-registry.sh` once (one UAC prompt: the sensor registry the media
carries). Two settings in
`sp11.conf`, also accepted from the environment, select the source media:

- `FEDORA_TARGET`: `beta` (default, the Fedora 45 Beta, `releases/test/45_Beta/`), `ga` (`releases/45/`, needs
  `FEDORA_COMPOSE=<n.m>` until the 45 GA compose is pinned in `sp11.conf`) or `nightly` (`development/45/`, needs
  `FEDORA_COMPOSE=<stamp>`). Only Fedora 45 is supported: the kernel source RPM is pinned per release. A release
  other than the host's is fine: the kernel, `sp11-iptsd` and the sensors libraries are built in `mock` buildroots
  of the target release.
- `FEDORA_EDITION`: `Workstation` (default) or a Fedora spin, named as in its ISO file name. The kernel
  and RPMs are the same for every edition. The KDE edition has its own mirror layout and is not covered.

Steps:

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
   `linux-kernel-test.patch`), `files/kernel-local` (the spec's `kernel-local`) and the buildid `.sp11.<revision>`,
   in a mock buildroot of the target release, into Fedora's kernel packages, and checks that the configuration is
   Fedora's plus exactly `kernel-local`. `sp11.conf` pins the content of the declared revision
   (`KERNEL_SP11_REV_SHA256`); a changed patch set or `kernel-local` without a new revision stops the step.
5. `scripts/30-build-support-rpm.sh` builds `sp11-surface-support`: firmware from the Windows DriverStore, audio
   topology and UCM, Wi-Fi board data, Bluetooth address service, boot policy (kernel-install plugin, dracut and
   `modules-load.d` settings, the dnf repository override that keeps stock kernels off the system), the Windows GRUB
   entry, the first-boot service, `sp11-bt-import-pairings` and `sp11-diag`. It rebuilds when its `VERSION=` or the
   target Fedora release changes, refuses to rebuild the same version from a changed payload (the payload's hash is
   recorded in the RPM), and then runs `scripts/35-verify-support-rpm.sh` (see below) when a live root is there.
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
   `build/out/Fedora-Workstation-Live-45_Beta-1.3-SP11-7.2.5-300.sp11.4.fc45.aarch64.iso`, plus `.sha256`. The file
   name carries the edition, so images of different editions coexist.

`build-all.sh` runs these steps (the kernel build takes about an hour after the downloads; WSL has to
keep running, or it stops and starts over on the next run), then `scripts/35-verify-support-rpm.sh`: in an overlay
of the live root with a real ext4 `/boot`, it installs the support RPM the two ways it reaches a machine — with its
scriptlets over the version the live root carries, as `dnf upgrade` does (after step 8 that is the same version,
installed again with `--replacepkgs`; `SUPPORT_PREVIOUS_RPM=<rpm>` first installs an earlier build for a real
upgrade), and the scriptless live install step 8 does — and checks that the GRUB policy values in `sp11.conf`
(device tree, mode, terminal, timeout, font) arrive in `/etc/default/grub` and, on the update path, in the menu
grub2-mkconfig generates from it; the update path stages a deliberately wrong policy first, so a package that
installs without applying it cannot pass; it also checks with dnf in the live root that the repository override
hides a stock kernel from repositories but not from a local RPM. `scripts/46-verify-sensors-rpms.sh` installs the
sensors RPMs into an overlay of that root with their scriptlets (a reinstall after step 8) and checks linkage,
units, rules, the policy module, the working directory and the payload; `SENSORS_PREVIOUS_RPMS=<rpms>` adds an
upgrade from an earlier release. `scripts/36-verify-kernel-install.sh` (standalone, for kernel RPMs built for an
existing installation) installs the kernel packages the way `dnf install` does, next to the kernel already there and
with their scriptlets, then the support RPM (left out when the live root already carries that version, as dnf leaves
an installed package out), and checks both packages, the boot entry with the Denali DTB, the initramfs and the
kernel arguments, the new kernel as the saved GRUB default, the regenerated menu, and that removing the new kernel
puts the previous one back. `scripts/60-verify-rootfs.sh` (optional, not run by `build-all.sh`) checks the root step
8 left behind: RPM dependencies, loadable binaries, the installer, the firmware against the device tree, the SP11
build in place of the stock kernel, the sensors stack, the boot entry and GRUB settings an installation would get
(Denali DTB, kernel arguments) and the Windows GRUB entry.

## Install

1. Write the ISO to a USB stick of 16 GB or more: Rufus in DD image mode or Fedora Media Writer on
   Windows, or `sudo dd if=<iso> of=/dev/sdX bs=4M status=progress oflag=sync` on Linux after checking
   the target with `lsblk` (`dd` erases it).
2. In Windows, shrink `C:` to free at least 60 GB. Keep Windows (see Status and scope).
3. Enter the Surface UEFI (hold Volume-Up + Power), disable Secure Boot and put USB first in the boot
   order.
4. Boot the USB and take the first GRUB entry.
5. Run "Install to Hard Drive" and choose "Share disk with other operating systems". Keep a single
   Fedora installation on the machine: a second one takes over the GRUB menu and hides the first.
6. Reboot without the USB and log in. On the first boot, a one-shot service enables the audio DSP, gives
   GRUB the Denali DTB, its display settings and the Windows entry, and rebuilds the initramfs. If audio is
   not up yet, reboot once. The sensors stack comes up with the DSP (auto-rotation, ambient light, compass).

## Update an installed system

New support-RPM versions install over the old one. Copy the RPM from `build/rpms/` to Fedora and run:

```bash
sudo dnf upgrade ./sp11-surface-support-<version>-1.fc<release>.aarch64.rpm
```

The package regenerates the GRUB menu itself; upgrading `sp11-iptsd` restarts the pen daemon. Rebuild
the ISO afterwards so new installations get the same version. `build/rpms/` holds the RPMs of one Fedora
release at a time: copy them elsewhere before building for another release.

A new SP11 kernel installs next to the current one, like Fedora's own kernels, from the directory holding its
packages (support RPM 3.0 or later; with an earlier support RPM, whose dnf exclusion also hides local kernel RPMs,
add `--setopt=disable_excludes='*'`):

```bash
sudo dnf install ./kernel{,-core,-modules-core,-modules,-modules-extra}-<version>-<release>.sp11.<revision>.fc45.aarch64.rpm
```

It gets its own boot entry with the Denali DTB and the kernel arguments and becomes the default; the
previous kernel stays in the GRUB menu. Kernels of the earlier `kernel-sp11` package stay installed next to it
until removed with `sudo dnf remove kernel-sp11-<version>`; `kernel-sp11` RPMs built before 2026-09-17, such as the
7.2.0 one, leave their boot entry behind when removed while another kernel stays, so run
`sudo kernel-install remove 7.2.0-jg-0sp11v23-qcom-x1e` first (`ls /boot/loader/entries` shows a leftover entry;
the same command cleans it up after the fact). dnf keeps at most three kernels per package name
(`installonly_limit`) and removes the oldest one in the transaction that installs a fourth (never the running one).
Check `df -h /boot` before installing another kernel, because a dracut failure inside the install leaves the new
kernel without a boot entry and only the transaction's output says so. Stock Fedora kernels are hidden from every
configured repository (support RPM 3.0), since they lack the SP11 patch set; `dnf upgrade` leaves the kernel alone
until an SP11 build of a newer Fedora kernel is installed from local RPMs.

Installations made from ISOs built before 2026-09-22 carry the ISO's build date as the modification time of
every file the installer copied (the remaster stamped the live image that way; `ls -l /usr/bin/bash` shows
it). It costs a bytecode recompile at every Python start and `rpm -V` flags the times; nothing malfunctions,
and updated packages and the next installation carry proper times.

Systems installed from ISOs built before 2026-09-22 (the earlier kernels had AppArmor as their active security
module) were installed with SELinux *disabled*: the live installer saw no SELinux and passed `--noselinux` to
Anaconda, which put `selinux=0` into the boot arguments and `SELINUX=disabled` into `/etc/selinux/config`. Support
RPMs 2.5 to 2.7 undid that by themselves; 3.0 no longer does, so such a system needs it once by hand:
`sudo grubby --update-kernel=ALL --remove-args=selinux=0`, `SELINUX=enforcing` in `/etc/selinux/config`,
`sudo touch /.autorelabel` and a reboot (the next boot relabels and reboots once). Confirmed on the tested unit on
2026-09-19; it was reinstalled from SELinux media on 2026-09-22.

Support RPM history (1.1 to 2.1 and 2.5 confirmed on the tested unit):

- 1.1: Flatpak works (`kernel.apparmor_restrict_unprivileged_userns=0`).
- 1.3: Windows Boot Manager entry in GRUB, before UEFI Firmware Settings.
- 1.4: Bluetooth address in the right octet order; earlier versions set it byte-reversed.
- 1.5: `sp11-bt-import-pairings` and `sp11-diag` under `/usr/libexec/sp11`.
- 1.6: `sp11-grub-defaults` as the single writer of the `/etc/default/grub` policy; dnf excludes the
  stock kernel packages.
- 1.7: `sp11-diag` lists every Bluetooth device BlueZ knows; license tag GPL-3.0-or-later.
- 1.8: the dnf exclusion also covers `kernel-uki-*`, which owns the boot kernel on aarch64; without it an
  upgrade could add a stock kernel boot entry.
- 1.9: corrected override hint in the exclusion file: dnf5 has no `--disableexcludes`, the override is
  `dnf --setopt=disable_excludes='*' ...`.
- 2.0: the Adreno microcode (`gen70500_sqe.fw`, `gen70500_gmu.bin`) goes into the initramfs, so early
  boot no longer logs `failed to load gen70500_sqe.fw`; the package requires `qcom-firmware`.
- 2.1: `sp11-remove-stock-kernels.service` removes the hidden stock kernel once, on new installations
  and on systems upgraded from an earlier version. `dracut --regenerate-all` no longer fails with
  `Can't write to /boot/efi/...`, and boot entries whose kernel image is missing are removed.
- 2.2: the stock-kernel cleanup accepts every installed `kernel-sp11` version as the running SP11 kernel, so
  it also works with several SP11 kernels installed side by side (tested in a chroot; systems where the
  cleanup already ran gain nothing from it).
- 2.3: the ISO build removes the stock kernel packages, so `sp11-remove-stock-kernels` is gone, and only the
  five firmware files the device tree loads are shipped. A system that never ran the stock-kernel cleanup
  (older than 2.1) needs 2.1 or 2.2 and one reboot before this update.
- 2.4: GRUB at the panel's native 2880x1920 with a 40 pt console font; `%posttrans` applies the GRUB policy
  before regenerating the menu, so an upgrade that changes a policy value takes effect;
  `scripts/35-verify-support-rpm.sh` checks both install paths.
- 2.5: the user-namespace sysctl is limited to the earlier AppArmor kernels (`-` prefix, ignored where the
  key does not exist); `sp11-diag` reports the active LSMs, `getenforce` and AVC denials;
  `sp11-selinux-restore` re-enables SELinux on installations the live installer disabled it on (see above).
  Installed together with the SELinux kernel `7.2.5-jg-0sp11v23.1-qcom-x1e`.
- 2.6: `sp11-diag` runs `sp11-sensors-check` when the sensors stack is installed.
- 2.7: the internal microphone's decimator gain (`UCM_MIC_GAIN`, +16 dB) in the UCM Mic device; `sp11-diag`
  reports the audio controls and the PipeWire source. Not yet tested on the device.
- 3.0: for the Fedora-based kernel: the stock-kernel exclusion becomes a dnf repository override (local kernel RPMs
  install without an override flag), `scmi-cpufreq` is loaded at boot, the FIPS dracut omission and the AppArmor-era
  sysctl and SELinux restore are gone, and `sp11-diag` gains a section that diffs cleanly between two kernels
  (drivers bound, modules, remoteprocs, cpufreq, power supplies, hwmon, platform profile) and records
  `systemd-analyze chid`. Verified in a chroot on both install paths (over 2.6 and 2.7) and installed on the device
  on 2026-09-23 as an upgrade (`scmi` cpufreq on the Fedora-based kernel).
- 3.1: `sp11-diag` reads the audio controls through the card's raw control interface (`amixer -D hw:N`); through
  `amixer -c N` (`sysdefault`, which the UCM's control remap replaces) it found none of them on the device.
  `sp11-cdsp-check.service` restarted the compute DSP once at boot when it ran without answering. Verified in a
  chroot on both install paths (over 2.6 and 3.0) and installed on the device on 2026-09-23.
- 3.2: `sp11-cdsp-check` is gone (kernel revision 3 lets the compute DSP wake; the restart had only lasted until its
  next sleep). `sp11-diag` lists the power-domain and interconnect providers still holding their boot-time votes and
  the devices they wait for. Verified in a chroot on both install paths (over 2.6 and 3.1) and on the device from a
  fresh installation on 2026-09-24.

## Bluetooth pairings shared with Windows (Flex Keyboard, Slim Pen 2)

A BLE device keeps one bond per host address, and Linux uses the same controller address as Windows,
so importing the Windows pairing keys lets both systems use the keyboard and pen without pairing again.
In WSL:

```bash
scripts/70-export-bt-pairings.sh
```

The script asks for elevation once (UAC; the keys are readable only elevated), converts the Flex
Keyboard and Slim Pen 2 bonds (`BT_PAIRING_USB_IDS` in `sp11.conf`) and writes
`build/out/sp11-bt-pairings.tar.gz`. Copy the tarball to Fedora and run:

```bash
tar -xzf sp11-bt-pairings.tar.gz && sudo /usr/libexec/sp11/sp11-bt-import-pairings
```

Existing Linux pairings for these devices are backed up under `/var/lib/sp11/`. Pairing a device again in
either system invalidates the other system's bond; export and import again afterwards. The tarball
contains secret keys: do not share it.

## Sensors (accelerometer, gyroscope, magnetometer, ambient light)

The sensors are not on any bus Linux can see: they hang off the Snapdragon Sensor Core, the sensor framework
running inside the ADSP firmware, and Windows reads them through a QMI client. The same path works on Linux
with free software: `hexagonrpcd` serves the framework its configuration and registry over FastRPC, `libssc`
talks to it over QRTR, and upstream `iio-sensor-proxy` 3.9 has drivers for it that Fedora builds out only
because `libssc` is not packaged in Fedora. The readings need no kernel change; GNOME's auto-rotation also
needs the tablet-mode switch fix, the last patch of the SP11 patch set. The ISO carries the stack (inert on the
live media, which runs without the ADSP; active on the installed system from its first boot) and its four RPMs
under `/sp11/rpms`; the steps below build it and add or update it on an existing installation. Confirmed on
the tested unit: readings from the light sensor, accelerometer, gyroscope, magnetometer and compass, the
orientation and the compass in iio-sensor-proxy, and auto-rotation on the desktop.

The steps build on a full `scripts/build-all.sh` run with the same `FEDORA_TARGET` (host setup, the downloads
for that release, and the live root the verification installs into). Export this unit's sensor registry and
calibration from Windows (one UAC prompt: the ADSP wrote them under `DriverData\Qualcomm\fastRPC`, readable
only elevated; per unit, keep them private):

```bash
scripts/75-export-sensor-registry.sh
```

Build the four RPMs with the same `FEDORA_TARGET` as the installed system (the library RPMs are built in a
mock buildroot of that release, so the first run takes a while):

```bash
FEDORA_TARGET=beta scripts/45-build-sensors-rpms.sh
```

This builds `hexagonrpc` (from this project's fork, see License and credits), `libssc`, `iio-sensor-proxy`
(Fedora's own source RPM with `-Dssc-support=enabled`) and `sp11-sensors` (the Windows sensor configuration,
the registry, the platform identity, and the udev, systemd, SELinux and dnf files) and verifies them in the
extracted live root. `SENSORS_VERSION` in `sp11.conf` versions `sp11-sensors`; a changed payload at the same
version stops the step, and a change in Fedora's iio-sensor-proxy spec stops it until the template is
refreshed. On an installed system that lacks the stack or runs an older build, from the directory holding
the RPMs:

```bash
sudo dnf install ./hexagonrpc-*.rpm ./libssc-0*.rpm ./iio-sensor-proxy-*.rpm ./sp11-sensors-*.rpm
```

Reboot after installing. The framework reads its registry when the file server first attaches after the ADSP
has booted, and writes into it while doing so; the fork serves those writes (upstream refuses them, and this
firmware then aborts the ADSP) into a copy of the registry under `/var/lib/sp11/hexagonrpc/sensors/persist`.
`sudo /usr/libexec/sp11/sp11-sensors-reset` rebuilds that copy from the package, effective at the next boot.
The framework compares the modification time of every configuration file with the stamp it recorded when it
parsed the file, so the package ships the files with Windows' times. A guard on the daemon's unit stops it
from attaching again after an ADSP crash in the same boot, so a failure costs one recoverable crash and a
log rather than a loop.

`sudo /usr/libexec/sp11/sp11-sensors-check`, run from a terminal in the desktop, shows the boot timeline,
the daemon and what the framework wrote, one reading per sensor (`ssccli`), what iio-sensor-proxy sees
(`monitor-sensor`) and the tablet-mode state GNOME uses. GNOME offers its auto-rotate button while the
keyboard is folded back or detached. Its automatic screen brightness uses the same light sensor
(confirmed on 2026-09-24). The gyroscope and magnetometer have no desktop consumer and are read with
`ssccli --sensor gyroscope` / `--sensor magnetometer`.

`sp11-sensors` excludes `iio-sensor-proxy` from dnf updates, since a later Fedora build would replace the
SSC-enabled one without a word. The exclusion also covers a local RPM of that package, so install the four
in one command as above, and install a later SP11 build of it with
`sudo dnf --setopt=disable_excludes='*' install ./iio-sensor-proxy-<version>.rpm`, the same override as for
the kernel packages. Never stop or restart the ADSP through `/sys/class/remoteproc` to "reset" the sensors:
that resets the SoC. Reference implementation: denisix/ubuntu-surface-pro-11 (`SENSORS.md`), which reports
all 13 sensors of the framework working on a Surface Pro 11 with this approach.

## Diagnostics

`sudo /usr/libexec/sp11/sp11-diag` writes `sp11-diag-<date>.txt` to the current directory: kernel,
touchscreen and pen (iptsd), input devices and Bluetooth state, including `bluetoothctl info` for every
device BlueZ knows, and the sensors stack when `sp11-sensors` is installed. It changes nothing.

## What the scripts decide for you

- Kernel: Fedora's `kernel-7.2.5-300.fc45` source RPM with Fedora's configuration, rebuilt with the 61 patches of
  the branch `sp11/7.2.5` of the project's kernel fork, on top of the stable tag `v7.2.5` and pinned by commit
  (`KERNEL_PATCH_COMMIT`; SP11 revision 4, `KERNEL_SP11_REV`; `docs/kernel-patches.md` lists each patch, its authors
  and what it is needed for) and `files/kernel-local`: `CONFIG_TOUCHSCREEN_MSHW0485=m` for the patch set's touch
  driver, and the video clock controller and crypto engine drivers Fedora's configuration leaves out, without which
  Linux never lowers the power-rail and bus votes it takes at boot and the compute DSP never wakes from sleep
  (`docs/kernel.md`). The result is Fedora's `kernel`, `kernel-core` and `kernel-modules*` packages with the buildid
  `.sp11.4`. The patches come from the kernel the project verified before (ooaklee's linux_ms_dev_kit-sp11 v23):
  ooaklee's touchscreen, pen, audio and device-tree work, the X1E fixes from jglathe's tree that act on this
  machine, and this repository's tablet-mode switch; that tree's Ubuntu packaging, configuration and SAUCE patches,
  its camera stack and its ADSP attach series are not carried (see the manifest for what each left-out part means
  for the device).
- Device tree: `qcom/x1e80100-microsoft-denali-oled.dtb` from the kernel package, loaded explicitly everywhere: GRUB
  `devicetree` on the live media, `GRUB_DEVICETREE` in every boot entry through
  `/usr/lib/kernel/install.d/15-sp11-surface.install` (Fedora's `20-grub.install` writes the line). Fedora's
  automatic selection (`kernel-uki-dtbloader`) matches none of this SKU's SMBIOS hardware IDs; whether its
  EDID-based IDs match is not verified yet.
- Kernel arguments: `clk_ignore_unused pd_ignore_unused systemd.tpm2_wait=0` (what Fedora's "Snapdragon WoA
  Laptop Install" page prescribes for X1E laptops) and `soundwire_qcom.sp11_feedback_active_offset2_zero=1` (the
  SP11 audio patches). The live media adds `modprobe.blacklist=qcom_q6v5_pas rd.driver.blacklist=qcom_q6v5_pas`
  (the same page's advice for booting from USB-C: restarting the ADSP resets the port); the installed system drops
  them.
- GRUB: `gfxterm` at the panel's native `2880x1920,auto`. GRUB has no text-scale setting and sizes its
  character cell from the loaded font, so legibility comes from a 40 pt DejaVu Sans Mono PF2 font built
  with `grub2-mkfont` and shipped in the support RPM (`/usr/share/sp11/fonts/sp11-console.pf2`, copied to
  `/boot/grub2/fonts/` and named by `GRUB_FONT`): a 24x48 px cell, 120x40 characters. The live menu falls
  back to Fedora's `unicode.pf2` at `1024x768` if that font fails to load. The live menu is Fedora's own (start,
  test this media and start — the default, verified against the checksum the build implants — and basic graphics),
  with the device tree and the kernel arguments added to each entry. Installed menu order: Fedora entries, Windows
  Boot Manager, UEFI Firmware Settings.
- Windows dual-boot: `/etc/grub.d/29_sp11_windows` finds the ESP holding
  `EFI/Microsoft/Boot/bootmgfw.efi` (a separate Windows ESP is fine) and adds a chainload entry.
  Fedora's aarch64 GRUB image lacks the `chain` module and Fedora's os-prober cannot find Windows on
  aarch64, so the module is copied from `grub2-efi-aa64-modules` to `/boot/grub2/arm64-efi/` (loadable
  because Secure Boot is off).
- SELinux, sandboxes and CPU frequency: Fedora's kernel configuration, so SELinux runs enforcing with Fedora's
  targeted policy and unprivileged user namespaces (Flatpak's bwrap, browser sandboxes) work as on any Fedora.
  Fedora builds `scmi-cpufreq` as a module that does not load on its own on these laptops; the support RPM loads it
  (`/usr/lib/modules-load.d/sp11-scmi-cpufreq.conf`, Fedora's documented fix).
- Bluetooth address: ooaklee's helper sets the controller address byte-reversed; the RPM build fixes the
  octet order, so Linux uses the address Windows reports for the built-in radio, which the shared
  pairings depend on.
- Audio: ooaklee's FullIO v19c topology and UCM, with the UCM device matcher extended to the 5G SKU.
- Pen: `sp11-iptsd` links against Fedora's `spdlog`, `fmt` and `inih`. The ISO build installs whichever
  of them the live image lacks (`LIVE_EXTRA_PKGS`; Workstation lacks `spdlog`) and refuses RPMs with
  unmet dependencies.
- Stock kernel: the ISO build replaces the live root's stock kernel packages with the SP11 build of the same
  packages, so the installer installs only the SP11 kernel, and the dnf repository override
  `/usr/share/dnf5/repos.override.d/90-sp11-kernel.repo` hides the stock ones (`kernel`, `kernel-core`,
  `kernel-modules`, `kernel-modules-core`, `kernel-modules-extra`, `kernel-modules-internal`, `kernel-uki-*`) in
  every configured repository, while SP11 kernel RPMs install from local files as they are;
  `dnf --setopt=disable_excludes='*' ...` overrides it.
- Firmware: only the five files the Denali device tree requests (ADSP and CDSP images with their
  device-tree blobs, GPU zap shader), under the names it requests them by.
- Initramfs: the live one carries only the GPU zap shader; the ADSP/CDSP firmware (about 24 MiB) and the
  Adreno microcode go into the installed system's initramfs. No rescue image: Fedora's rescue entry would name a
  device-tree directory that does not exist.
- Live image: repacked as LZMA EROFS with the source image's file times (`mkfs.erofs --mkfs-time`; `-T` alone
  stamps every file with the build time, which the installer then copies onto the installed system).
- Sensors: the four RPMs of the stack are installed into the live root with their scriptlet effects applied
  by the build (the `fastrpc` user, the SELinux module, the registry copy under `/var/lib/sp11/hexagonrpc`).
  The live session never starts them (no FastRPC node while the ADSP is off); the installed system does on
  its first boot.
- Hardware detection uses the built-in panel (WMI connection type internal) and the built-in Bluetooth
  radio, so an external monitor or a USB Bluetooth dongle does not change the result.
- Tablet mode: mainline gives the Surface Pro 11 the Surface Aggregator's KIP cover switch, whose change event this
  firmware never sends, so the kernel always reported laptop mode. The last patch of the SP11 patch set registers
  the POS posture switch instead, which follows the keyboard: tablet mode while it is detached or folded back. GNOME
  then offers auto-rotation (with the sensors packages), and libinput switches the keyboard and touchpad off while
  the keyboard is folded back.

## New Fedora compose or kernel

Edit `sp11.conf`: `FEDORA_COMPOSE` (from the ISO file name) in the `FEDORA_TARGET` branch you build and, for a new
Fedora kernel, `KERNEL_FEDORA_VERSION`, `KERNEL_FEDORA_RELEASE` and the source RPM's checksum in the
`KERNEL_SRPM_SHA256` case table (the source RPM is on Koji: `kojipkgs.fedoraproject.org/packages/kernel/`). Then run
`FORCE=1 scripts/build-all.sh`. Checksum-pinned downloads stay cached; the packages downloaded with dnf
(`atheros-firmware`, the live-root dependencies, the sensors sources) are cached per Fedora release and fetched
again with `FORCE=1`. The ISO layout (volume id, marker file, kernel and initrd paths, font, live menu) is read from
each ISO. Other values a new release can touch, each of which stops the build rather than guessing:

- a new kernel: the patch set has to be rebased onto its stable tag on a new branch of the kernel fork, and
  `KERNEL_PATCH_BASE_COMMIT` and `KERNEL_PATCH_COMMIT` set to the new commits (how, and the conflicts known for
  7.2.6 and 7.2.7, is in `docs/kernel.md`), and a new symbol has to be set in `files/kernel-local` (Fedora's
  configuration checks refuse an unset one);
- a new Fedora: `rpm/iio-sensor-proxy.spec.in`, a copy of Fedora's spec whose source is pinned by
  `IIO_SENSOR_PROXY_BASE_SPEC_SHA256` (refresh the template, then the pin), the package names in
  `LIVE_EXTRA_PKGS` and `SENSORS_DEPS_PKGS`, the dracut module names in `LIVE_DRACUT_OMIT`
  (`scripts/50-build-iso.sh`, Fedora 45's), the version floors in `rpm/sp11-sensors.spec.in`, and the UCM
  matcher patch in `scripts/30-build-support-rpm.sh`, which expects ooaklee's v19c `x1e80100.conf` matcher
  line.

`KERNEL_SP11_REV` (default 4) is everything the project changes in Fedora's kernel: the patch set's pinned commit
and `files/kernel-local`. It becomes the buildid `.sp11.<revision>`, so the result is, for example,
`kernel-7.2.5-300.sp11.1.fc45` with the kernel version `7.2.5-300.sp11.1.fc45.aarch64`. The kernel packages are
install-only, and a rebuild with the same version would own the same `/boot` and module paths as the installed one,
so bump the revision with every change to the pinned commit or to `kernel-local`: `sp11.conf` pins each revision's
content (`KERNEL_SP11_REV_SHA256`: the revision number, `kernel-local`'s effective lines and the two pinned
commits), and step 4 stops when they and the revision disagree, printing the value for the new revision.

## Layout

- `sp11.conf`: versions (the support RPM's is `VERSION=` in `scripts/30-build-support-rpm.sh`), URLs, regexes,
  boot policy and the content pins.
- `scripts/`: numbered pipeline steps, `lib.sh` (helpers), `build-all.sh`, the pairing export, and the sensors
  stack outside the pipeline (`45`/`46` build and verify its RPMs, `75` exports the registry from Windows).
- `rpm/`: spec templates for `sp11-surface-support`, `sp11-iptsd`, and for the sensors stack (`hexagonrpc`,
  `libssc`, `iio-sensor-proxy`, `sp11-sensors`); the kernel uses Fedora's own `kernel.spec`.
- `files/`: payload of the support RPM, the kernel's configuration additions (`files/kernel-local`), the README
  inside the ISO, and `files/sensors/` (the files and helper scripts of `sp11-sensors`, hexagonrpc's sysusers entry
  and udev rule, and `sp11-sam-posture`, an unpackaged probe of the Surface Aggregator's cover and posture state).
- `images/`: the screenshot above.
- `LICENSE`: GPL-3.0-or-later for the repository's content (see License and credits).
- `CLAUDE.md`: entry point of the working notes (the index of `docs/`, rules for every session, references).
- `docs/`: the working notes by topic (`pipeline.md`, `hardware.md`, `kernel.md`, `kernel-patches.md`,
  `fedora-media.md`, `sensors.md`, `verified.md`): verified facts about the hardware, the Fedora media and the
  pipeline, its pitfalls, and what has been confirmed on the device, by date.
- `.gitattributes`: LF line endings for every file; the payload scripts break with CRLF.
- `build/`: caches, work trees, RPMs and output ISOs (git-ignored). `build/hardware.env`,
  `build/bt-pairings/` and `build/sensors/` hold your unit's identity, pairing keys and sensor calibration;
  keep them private.

## License and credits

The scripts, templates and documentation in this repository are licensed under the GNU General Public License,
version 3 or later (`LICENSE`). Everything third-party is downloaded and packaged at build time:

- Kernel: Fedora's `kernel` source RPM (GPL-2.0), rebuilt with the patch set (the project's kernel fork, GPL-2.0
  like the kernel; each commit names its author), which was extracted from
  [ooaklee/linux_ms_dev_kit-sp11](https://github.com/ooaklee/linux_ms_dev_kit-sp11) (release v23): ooaklee's Surface
  Pro 11 work (touchscreen and pen after x1e-nixos's QSPI port, the audio work of geocausa's SP11X1e-audio as ported
  by Leon Silcott, device tree, platform profile, with Justin White, Jérôme de Bretagne and Oliver White), and the
  X1E fixes it carries from [jglathe/linux_ms_dev_kit](https://github.com/jglathe/linux_ms_dev_kit) and upstream
  developers (Stephan Gerhold, Abel Vesa, Akhil P Oommen, Konrad Dybcio, Johan Hovold, Dale Whinham and others;
  `docs/kernel-patches.md` lists them). ooaklee's releases are published through
  [ooaklee/linux-surface-pro-11-oe](https://github.com/ooaklee/linux-surface-pro-11-oe), which also provides the
  FullIO audio topology and UCM files, the iptsd integration templates (MIT,
  `userspace/iptsd-sp11/LICENSE.integration`) and `sp11-bt-set-addr.c`. That repository has no top-level license;
  the audio files and the helper carry no license statement, and the release notes say the topology contains
  vendor-derived bytes that must stay outside kernel packages.
- Pen daemon: [linux-surface/iptsd](https://github.com/linux-surface/iptsd) (GPL-2.0-or-later and MIT),
  unmodified.
- Wi-Fi board data: `board-2.bin` from Fedora's `atheros-firmware`, extracted with `ath12k-bdencoder`
  from [qca/qca-swiss-army-knife](https://github.com/qca/qca-swiss-army-knife).
- Sensors: [linux-msm/hexagonrpc](https://github.com/linux-msm/hexagonrpc) (GPL-3.0-or-later), built from
  [this project's fork](https://github.com/FadyAckad/hexagonrpc), branch `sp11-sensors`: upstream plus five
  commits (the sensor framework's registry writes, requests longer than 256 bytes, the registry's parent
  directory, and the fixes those write paths needed; meant for upstream, see hexagonrpc's issue #19 and
  pull request #21),
  [DylanVanAssche/libssc](https://codeberg.org/DylanVanAssche/libssc) (GPL-3.0-or-later) and Fedora's
  `iio-sensor-proxy` source RPM (GPL-3.0-or-later), the latter two unmodified; the approach follows
  [denisix/ubuntu-surface-pro-11](https://github.com/denisix/ubuntu-surface-pro-11). The sensor configuration
  and registry that `sp11-sensors` carries are proprietary Microsoft and Qualcomm files copied from your own
  Windows installation at build time, like the firmware below.
- Base media: Fedora Workstation live images, or a spin (`FEDORA_EDITION`). Bring-up notes:
  rjindael/fedora-surface-pro-11.
- ADSP/CDSP/GPU firmware: proprietary Qualcomm and Microsoft files copied from your own Windows
  DriverStore at build time. Never part of this repository; see Status and scope.

Upstream files modified during the build, with changes that are not upstream: the octet order in
`sp11-bt-set-addr.c` (see above), the ALSA UCM device matcher in `x1e80100.conf`, which gains the `( with 5G)?`
alternative, and the Mic device in `SP11-HiFi.conf`, which gains the microphone gain; in the kernel, everything the
SP11 patch set changes (none of it is in Linux 7.2.5; `docs/kernel-patches.md` lists where each patch comes from).
