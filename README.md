# Fedora Live ISO for Surface Pro 11 (Snapdragon X Elite, OLED, incl. the 5G SKU)

![Screenshot showing the About section](https://github.com/fadyackad/fedora-linux-surface-pro-11/blob/main/images/Screenshot.png)

Builds a Fedora live ISO (aarch64) that boots and installs on a Microsoft Surface Pro, 11th Edition
with the Samsung OLED panel (Snapdragon X Elite X1E80100). The ISO uses the Surface Pro 11 kernel from
[ooaklee/linux_ms_dev_kit-sp11](https://github.com/ooaklee/linux_ms_dev_kit-sp11) (release v23, based on
Linux 7.2.0) with the kernel.org 7.2.5 stable update applied and Fedora's LSM stack (SELinux) in place
of Ubuntu's, `7.2.5-jg-0sp11v23.1-qcom-x1e`, and GRUB loads the Denali OLED device tree explicitly. The
build runs on the Surface itself, in WSL (Fedora aarch64): the kernel compiles natively, and the unit's
identity, Bluetooth address and device firmware
come from its Windows installation, so every ISO is tailored to the unit that built it.

## Verified

Tested on the 5G SKU (`Surface_Pro_with_5G_11th_Edition_2077`). The first three columns are
installations from ISOs with ooaklee's unmodified 7.2.0 kernel. The last column is the Fedora 45 Beta
installation after its kernel was updated to 7.2.5 with ooaklee's config. The current default build,
`7.2.5-jg-0sp11v23.1-qcom-x1e` with Fedora's LSM stack (SELinux), was installed on that system as an update
and everything in the last column still works. That installation had been installed with SELinux disabled
(see Install below); since 2026-09-19 it runs SELinux enforcing with no denials logged.

| Feature | Fedora 44 Workstation, 7.2.0 | Fedora 45 Beta Workstation, 7.2.0 | Fedora 45 Beta Workstation, 7.2.5 |
|---|:-:|:-:|:-:|
| Boot from the internal NVMe drive | yes | yes | yes |
| Display with GPU acceleration | yes | yes | yes |
| Backlight (brightness slider) | yes | yes | yes |
| Wi-Fi | yes | yes | yes |
| Bluetooth | yes | yes | yes |
| Touchscreen | yes | yes | yes |
| Multi-touch (pinch, two-finger scroll) | yes | yes | yes |
| Pen | yes | yes | yes |
| Speakers | yes | yes | yes |
| Microphone | yes | yes | yes |
| Keyboard and touchpad | yes | yes | yes |
| Battery status | yes | yes | yes |
| Suspend and resume | yes | yes | yes |
| Flatpak | yes | yes | yes |
| Windows in the GRUB menu | yes | yes | yes |
| Flex Keyboard and Slim Pen 2 pairings shared with Windows | yes | yes | yes |
| Sensors: readings from the accelerometer, gyroscope, magnetometer/compass and ambient light sensor (`ssccli`, `monitor-sensor`), with the sensors RPMs | not reported | not reported | yes |
| Sensors: auto-rotation and automatic screen brightness on the desktop | not reported | not reported | not reported |
| 5G modem | no | no | no |
| Cameras | no | no | no |
| NPU (AI acceleration) | no | no | no |

*yes*: confirmed on the tested unit. *not reported*: not checked with that combination. *no*: not covered
by this project.

In the live session, audio and battery status are unavailable because the audio DSP stays off while
running from USB-C; both work once installed.

## Status and scope

- Unofficial community project, not affiliated with Microsoft, Qualcomm, Fedora or ooaklee. No warranty.
- Tested only on the 5G OLED SKU. The hardware checks also accept the non-5G OLED SKUs
  (`Surface_Pro_11th_Edition_2076`, `Surface_Pro_11th_Edition_For_Business_2085`), which share the
  device tree, firmware file names and digitizer IDs; no build from one has been reported. The X1P64100
  LCD variant uses a different device tree and is rejected.
- Secure Boot must be disabled: the kernel is unsigned. FIPS is not compiled in.
- Windows must stay on the device. The build reads the hardware identity, the built-in radio's
  Bluetooth address and the ADSP/CDSP/GPU firmware from it; without that firmware an installed system
  has no audio, battery reporting or GPU acceleration.
- The support RPM and the ISO contain proprietary Qualcomm firmware copied from your own Windows
  installation. Do not redistribute them; point other people to this repository instead.

## Build

Requirements: WSL with Fedora 44 aarch64 on the Surface, Windows interop (`powershell.exe`), `sudo`
(passwordless for unattended runs), 40 GiB free disk space and internet access.

```bash
scripts/build-all.sh
```

Every step is idempotent and skips finished work; `FORCE=1` rebuilds a step. Two settings in
`sp11.conf`, also accepted from the environment, select the source media:

- `FEDORA_TARGET`: `ga` (default, a released Fedora), `beta` (`releases/test/<n>_Beta/`) or `nightly`
  (`development/<n>/`, needs `FEDORA_COMPOSE=<stamp>`). A release other than the host's is fine:
  `sp11-iptsd` is then built in a `mock` buildroot, because the fmt and spdlog sonames it links against
  change between releases.
- `FEDORA_EDITION`: `Workstation` (default) or a Fedora spin, named as in its ISO file name. The kernel
  and RPMs are the same for every edition. The KDE edition has its own mirror layout and is not covered.

```bash
FEDORA_TARGET=beta scripts/build-all.sh      # Fedora 45 Beta Workstation
```

Steps:

1. `scripts/00-setup-host.sh` installs the build dependencies and checks the host.
2. `scripts/05-detect-hardware.sh` reads SKU, panel and Bluetooth address from Windows, checks them
   against the supported models and writes `build/hardware.env`.
3. `scripts/10-fetch-sources.sh` downloads and checksum-verifies the Fedora ISO, the kernel source, the
   audio files, the pinned iptsd and OE checkouts, helper sources and the runtime packages the live
   image lacks.
4. `scripts/20-build-kernel.sh` applies the stable update to ooaklee's source and compiles it with
   ooaklee's config plus the `files/kernel-sp11-fedora.config` policy (Fedora's LSM stack, no Ubuntu-only
   modules; about 45 min) into the `kernel-sp11` RPM. `KERNEL_MODE=prebuilt` repackages ooaklee's released
   7.2.0 `.deb` payload instead (1 min, without the stable update or the policy).
5. `scripts/30-build-support-rpm.sh` builds `sp11-surface-support`: firmware from the Windows
   DriverStore, audio topology and UCM, Wi-Fi board data, Bluetooth address service, boot policy
   (kernel-install plugin, dracut, sysctl and dnf settings), the Windows GRUB entry, the first-boot
   service, the SELinux restore, `sp11-bt-import-pairings` and `sp11-diag`. It rebuilds when its `VERSION=` or the target Fedora
   release changes, and then runs `scripts/35-verify-support-rpm.sh` (see below) when a live root is there.
6. `scripts/40-build-iptsd-rpm.sh` builds `sp11-iptsd`: pinned upstream iptsd with ooaklee's Surface
   Pro 11 integration.
7. `scripts/50-build-iso.sh` installs the RPMs into the live root, builds the live initramfs, writes the
   GRUB menu and assembles the ISO, for example
   `build/out/Fedora-Workstation-Live-44-1.7-SP11-7.2.5-jg-0sp11v23.1-qcom-x1e.aarch64.iso`, plus
   `.sha256`. The file name carries the edition, so images of different editions coexist.

`build-all.sh` runs these steps (about an hour after the downloads, most of it the kernel; WSL has to keep
running, or the kernel build stops and resumes on the next run), then `scripts/35-verify-support-rpm.sh`:
in an overlay of the live root with a real ext4 `/boot`, it installs the support RPM the two ways it
reaches a machine — `dnf upgrade` over the previous version with its scriptlets, and the scriptless live
install step 7 does — and checks that every boot-policy value in `sp11.conf` arrives in
`/etc/default/grub` and in the menu grub2-mkconfig generates from it. The update path stages a deliberately
wrong policy first, so a package that installs without applying it cannot pass.
`scripts/36-verify-kernel-install.sh` (standalone, for a kernel RPM built for an existing installation)
installs the kernel RPM the way `dnf install` does — next to the kernel already there, scriptlets running —
into an overlay of the live root with a real ext4 `/boot`, then the support RPM, and checks the result: both
packages present, the boot entry with the Denali DTB, the initramfs and the kernel arguments, the new kernel as
the saved GRUB default, the menu regenerated, and that removing the new kernel puts the previous one back.
`scripts/60-verify-rootfs.sh` then
checks the root that step 7 left behind: RPM dependencies, loadable binaries, the installer, the firmware
against the device tree, the absence of the stock kernel, the boot entry and GRUB settings an installation
would get (Denali DTB, kernel arguments) and the Windows GRUB entry.

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
   GRUB the Denali DTB, low resolution and the Windows entry, and rebuilds the initramfs. If audio is not up
   yet, reboot once.

## Update an installed system

New support-RPM versions install over the old one. Copy the RPM from `build/rpms/` to Fedora and run:

```bash
sudo dnf upgrade ./sp11-surface-support-<version>.fc<release>.aarch64.rpm
```

The package regenerates the GRUB menu itself; upgrading `sp11-iptsd` restarts the pen daemon. Rebuild
the ISO afterwards so new installations get the same version. `build/rpms/` holds the RPMs of one Fedora
release at a time: copy them elsewhere before building for another release.

A new `kernel-sp11` installs next to the current one, like Fedora's own kernels:

```bash
sudo dnf install ./kernel-sp11-<version>.fc<release>.aarch64.rpm
```

It gets its own boot entry with the Denali DTB and the kernel arguments and becomes the default; the
previous kernel stays in the GRUB menu. Kernel RPMs built before 2026-09-17, such as the 7.2.0 one on
existing installations, leave their boot entry behind when removed while another SP11 kernel stays, so run
`sudo kernel-install remove 7.2.0-jg-0sp11v23-qcom-x1e` before `sudo dnf remove kernel-sp11-7.2.0`.

A kernel with Fedora's LSM stack (`7.2.5-jg-0sp11v23.1-qcom-x1e` and later) can run SELinux, which the
earlier SP11 kernels left inactive. Systems installed from media with those earlier kernels were installed
with SELinux *disabled*: the live installer saw no SELinux and passed `--noselinux` to Anaconda, which put
`selinux=0` into the boot arguments and `SELINUX=disabled` into `/etc/selinux/config`. Support RPM 2.5
undoes that by itself when the SELinux kernel is installed, or on a later support upgrade: it removes the
argument, sets `SELINUX=enforcing` again and marks the filesystem for relabeling; the next boot relabels and
reboots once, and the system runs enforcing from then on. It acts only when both installer marks are
present, so a system where SELinux was disabled by hand is left alone. The manual equivalent is
`sudo grubby --update-kernel=ALL --remove-args=selinux=0`, `SELINUX=enforcing` in `/etc/selinux/config`,
`sudo touch /.autorelabel` and a reboot. Booting an earlier SP11 kernel again afterwards creates unlabeled
files, and the next SELinux boot relabels again. Done by hand on the tested unit on 2026-09-19 (permissive
first as a precaution, then enforcing): the relabel boot happened and the system has run enforcing since,
with pen, Bluetooth and audio working; the automatic path was confirmed on the tested unit the same day.

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
- 2.2: the stock-kernel cleanup accepts every installed `kernel-sp11` version as the running SP11 kernel,
  so it also works with several SP11 kernels installed side by side. Tested in a chroot, not yet on the
  device; systems where the cleanup already ran gain nothing from it.
- 2.3: the ISO build removes the stock kernel packages, so `sp11-remove-stock-kernels` is gone. Only the
  five firmware files the device tree loads are shipped. Tested in a chroot, not yet on the device. A
  system that never ran the stock-kernel cleanup (older than 2.1) needs 2.1 or 2.2 and one reboot before
  this update.
- 2.4: `%posttrans` applies the GRUB policy before regenerating the menu, so an upgrade that changes a
  policy value takes effect; `scripts/35-verify-support-rpm.sh` checks both install paths.
- 2.5: the user-namespace sysctl is limited to the earlier AppArmor kernels (`-` prefix, ignored where the
  key does not exist); `sp11-diag` reports the active LSMs, `getenforce` and AVC denials. Installed together
  with the SELinux kernel `7.2.5-jg-0sp11v23.1-qcom-x1e` as an update; nothing broke (SELinux was still
  disabled by the installation's `selinux=0` boot argument). Rebuilt under the same version on 2026-09-19 with
  `sp11-selinux-restore`, which re-enables SELinux on installations the live installer disabled it on;
  confirmed on the tested unit.
- 2.6: `sp11-diag` runs `sp11-sensors-check` when the sensors stack is installed. Tested in a chroot, not yet on
  the device.

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
running inside the ADSP firmware, and Windows reads them through a QMI client. The same path works on Linux with
free software, and it needs no kernel change: `hexagonrpcd` serves the framework its configuration and registry
over FastRPC, `libssc` talks to it over QRTR, and upstream `iio-sensor-proxy` 3.9 has drivers for it that Fedora
builds out only because `libssc` is not packaged in Fedora. The stack is packaged separately from the ISO and is
for the installed system only (the live session runs without the ADSP). Not yet confirmed on the tested unit.

Build the four RPMs (the same `FEDORA_TARGET` as the installed system; the library RPMs are built in a mock
buildroot of that release, so the first run takes a while):

```bash
scripts/75-export-sensor-registry.sh
```

exports this unit's sensor registry from Windows (one UAC prompt: the ADSP wrote it under
`DriverData\Qualcomm\fastRPC`, readable only elevated; per unit, keep it private), then

```bash
FEDORA_TARGET=beta scripts/45-build-sensors-rpms.sh
```

builds `hexagonrpc`, `libssc`, `iio-sensor-proxy` (Fedora's own source RPM with `-Dssc-support=enabled`) and
`sp11-sensors` (the Windows sensor configuration, the registry, the platform identity, and the udev, systemd,
SELinux, dracut and dnf glue) and verifies them in the extracted live root. On Fedora, from the directory holding
the RPMs:

```bash
sudo dnf install ./hexagonrpc-*.rpm ./libssc-0*.rpm ./iio-sensor-proxy-*.rpm ./sp11-sensors-*.rpm
```

The framework re-reads its registry every time the file server attaches and writes into it while doing so, so
`hexagonrpcd` is built from this project's fork, which serves those writes (upstream refuses them, and this
firmware then aborts the ADSP) into a copy of the registry under `/var/lib/sp11/hexagonrpc/sensors/persist`; `sudo
sp11-sensors-reset` rebuilds that copy from the package. The framework compares the modification time of every
configuration file with the stamp it recorded when it parsed the file, so the package ships the files with
Windows' times. A guard on the daemon's unit stops it from attaching again after an ADSP
crash in the same boot, so a failure costs one recoverable crash and a log rather than a loop. Reboot after
installing. Then `sudo /usr/libexec/sp11/sp11-sensors-check`
shows the daemon, the QRTR service, one reading per sensor (`ssccli`) and what iio-sensor-proxy sees
(`monitor-sensor`); GNOME's auto-rotate quick setting and automatic screen brightness follow from the latter. The
gyroscope and magnetometer have no desktop consumer and are read with `ssccli --sensor gyroscope` /
`--sensor magnetometer`. `sp11-sensors` excludes `iio-sensor-proxy` from dnf updates, since a later Fedora build
would replace the SSC-enabled one without a word. The exclusion also covers a local RPM of that package, so
install the four in one command as above, and install a later SP11 build of it with
`sudo dnf --setopt=disable_excludes='*' install ./iio-sensor-proxy-<version>.rpm`, the same override as for the
kernel packages. Never stop or restart the ADSP through `/sys/class/remoteproc` to "reset" the sensors: that
resets the SoC. Reference implementation: denisix/ubuntu-surface-pro-11 (`SENSORS.md`), which reports all 13
sensors of the framework working on a Surface Pro 11 with this approach.

## Diagnostics

`sudo /usr/libexec/sp11/sp11-diag` writes `sp11-diag-<date>.txt` to the current directory: kernel,
touchscreen and pen (iptsd), input devices and Bluetooth state, including `bluetoothctl info` for every
device BlueZ knows, and the sensors stack when `sp11-sensors` is installed. It changes nothing.

## What the scripts decide for you

- Kernel: ooaklee's `7.2.0-jg-0sp11v23` source plus the kernel.org 7.2.5 stable update
  (`KERNEL_STABLE_VERSION`), with the config exported from `debian.qcom-x1e/config/annotations` and
  `files/kernel-sp11-fedora.config` merged on top (`KERNEL_CONFIG_REV`): Fedora's LSM order
  `lockdown,yama,integrity,selinux,bpf,landlock,ipe` with SELinux as the default, AppArmor and Ubuntu's
  out-of-tree IgH EtherCAT module off. Everything else is ooaklee's config: compared with the released
  7.2.0 one, only that policy, `CONFIG_LOCALVERSION` (carries the ABI), `CONFIG_VERSION_SIGNATURE` and two
  Allwinner crypto options that 7.2.5 removes differ. FIPS is not compiled in, and the initramfs omits the
  dracut `fips` modules.
- Device tree: `qcom/x1e80100-microsoft-denali-oled.dtb`, loaded explicitly everywhere: GRUB
  `devicetree` on the live media, `GRUB_DEVICETREE` in every boot entry through
  `/usr/lib/kernel/install.d/15-sp11-surface.install`. Fedora's stubble hardware-ID database does not
  know the 5G SKU, so automatic DTB selection cannot work on this model.
- Kernel arguments: `clk_ignore_unused pd_ignore_unused systemd.tpm2_wait=0
  soundwire_qcom.sp11_feedback_active_offset2_zero=1`. The live media adds
  `modprobe.blacklist=qcom_q6v5_pas rd.driver.blacklist=qcom_q6v5_pas`; the installed system drops them.
- GRUB: `gfxterm` at the panel's native `2880x1920,auto`. GRUB has no text-scale setting and sizes its
  character cell from the loaded font, so legibility comes from a 40 pt DejaVu Sans Mono PF2 font built
  with `grub2-mkfont` and shipped in the support RPM (`/usr/share/sp11/fonts/sp11-console.pf2`, copied to
  `/boot/grub2/fonts/` and named by `GRUB_FONT`): a 24x48 px cell, 120x40 characters. The live menu falls
  back to Fedora's `unicode.pf2` at `1024x768` if that font fails to load. Live menu entries: the SP11
  kernel, a verbose variant and a `nomodeset` variant. Installed menu order: Fedora entries, Windows Boot
  Manager, UEFI Firmware Settings.
- Windows dual-boot: `/etc/grub.d/29_sp11_windows` finds the ESP holding
  `EFI/Microsoft/Boot/bootmgfw.efi` (a separate Windows ESP is fine) and adds a chainload entry.
  Fedora's aarch64 GRUB image lacks the `chain` module and Fedora's os-prober cannot find Windows on
  aarch64, so the module is copied from `grub2-efi-aa64-modules` to `/boot/grub2/arm64-efi/` (loadable
  because Secure Boot is off).
- SELinux and sandboxes: ooaklee's config makes AppArmor the active LSM with
  `CONFIG_SECURITY_APPARMOR_RESTRICT_USERNS=y`; Fedora has no AppArmor profiles, so unprivileged user
  namespaces (Flatpak's bwrap, browser sandboxes) would be denied, and SELinux, although compiled in, never
  starts, so Fedora runs without MAC enforcement. The config policy replaces the LSM stack with Fedora's:
  SELinux is active with Fedora's targeted policy and the restriction is gone.
  `/usr/lib/sysctl.d/90-sp11.conf` keeps `-kernel.apparmor_restrict_unprivileged_userns = 0` for the
  earlier AppArmor kernels that stay installed; the `-` prefix makes systemd-sysctl ignore the missing key
  on the others.
- Bluetooth address: ooaklee's helper sets the controller address byte-reversed; the RPM build fixes the
  octet order, so Linux uses the address Windows reports for the built-in radio, which the shared
  pairings depend on.
- Audio: ooaklee's FullIO v19c topology and UCM, with the UCM device matcher extended to the 5G SKU.
- Pen: `sp11-iptsd` links against Fedora's `spdlog`, `fmt` and `inih`. The ISO build installs whichever
  of them the live image lacks (`LIVE_EXTRA_PKGS`; Workstation lacks `spdlog`) and refuses RPMs with
  unmet dependencies.
- Stock kernel: the ISO build removes its packages from the live root, so the installer installs only
  the SP11 kernel, and `/etc/dnf/libdnf5.conf.d/90-sp11.conf` keeps dnf from bringing a stock kernel
  back (`kernel`, `kernel-core`, `kernel-modules*`, `kernel-uki-*`;
  `dnf --setopt=disable_excludes='*' ...` overrides it).
- Firmware: only the five files the Denali device tree requests (ADSP and CDSP images with their
  device-tree blobs, GPU zap shader), under the names it requests them by.
- Initramfs: the live one carries only the GPU zap shader; the ADSP/CDSP firmware (about 24 MiB) and the
  Adreno microcode go into the installed system's initramfs.
- Hardware detection uses the built-in panel (WMI connection type internal) and the built-in Bluetooth
  radio, so an external monitor or a USB Bluetooth dongle does not change the result.

## New Fedora or kernel release

Edit `sp11.conf`: `FEDORA_RELEASE` and `FEDORA_COMPOSE` (from the ISO file name) in the `FEDORA_TARGET`
branch you build and, for a new kernel, `KERNEL_RELEASE_TAG`, `KERNEL_PKG_VERSION`,
`KERNEL_UPSTREAM_VERSION`, `KERNEL_RPM_RELEASE` and `KERNEL_SOURCE_COMMIT` (all on the ooaklee release
page). Then run `FORCE=1 scripts/build-all.sh`. Checksum-pinned downloads stay cached; the packages
downloaded with dnf (`atheros-firmware`, the live-root dependencies) are cached per Fedora release and
fetched again with `FORCE=1`. The ISO layout (volume id, marker file, kernel and initrd paths, font) is
read from each ISO. The UCM matcher patch in `scripts/30-build-support-rpm.sh` expects ooaklee's v19c
`x1e80100.conf` and stops the build if that file changes.

`KERNEL_STABLE_VERSION` (default 7.2.5) applies a kernel.org stable update on top of ooaklee's release in
source builds; `sp11.conf` pins the checksum of each accepted version. The patched source gets a tree of
its own. `KERNEL_CONFIG_REV` (default 1) merges `files/kernel-sp11-fedora.config` into ooaklee's config
and adds `.1` to the kernel version and the RPM release, so the result is `kernel-sp11-7.2.5-sp11v23.1`
with the kernel version `7.2.5-jg-0sp11v23.1-qcom-x1e`. `kernel-sp11` is an install-only package, and a
rebuild with the same version would own the same `/boot` and module paths as the installed one, so bump
the revision with every change to the fragment. To build ooaklee's release unchanged
(`7.2.0-jg-0sp11v23-qcom-x1e`, AppArmor):

```bash
KERNEL_STABLE_VERSION= KERNEL_CONFIG_REV= scripts/build-all.sh
```

The 7.2.5 update applies to ooaklee's v23 source unchanged. 7.2.6 does not: it changes the same lines as
v23's own audio DSP, touch controller, audio and AppArmor code and would need a manual merge. A stable
update only fits the `X.Y.0` release it was made for, so a new ooaklee release on another base stops the
build until you set a matching `KERNEL_STABLE_VERSION` default in `sp11.conf` (with its checksum from
kernel.org's `sha256sums.asc`) or clear it.

## Layout

- `sp11.conf`: all versions, URLs, regexes and boot policy.
- `scripts/`: numbered pipeline steps, `lib.sh` (helpers), `build-all.sh`, the pairing export, and the sensors
  stack outside the pipeline (`45`/`46` build and verify its RPMs, `75` exports the registry from Windows).
- `rpm/`: spec templates for `kernel-sp11`, `sp11-surface-support`, `sp11-iptsd`, and for the sensors stack
  (`hexagonrpc`, `libssc`, `iio-sensor-proxy`, `sp11-sensors`).
- `files/`: payload of the support RPM, the kernel config policy fragment, the live GRUB menu template, the
  README inside the ISO, and `files/sensors/` (udev, systemd, SELinux and dnf glue of `sp11-sensors`).
- `LICENSE`: GPL-3.0-or-later for the repository's own content (see License and credits).
- `CLAUDE.md`: working notes with verified facts about the hardware, the Fedora media and pipeline
  pitfalls.
- `.gitattributes`: LF line endings for every file; the payload scripts break with CRLF.
- `build/`: caches, work trees, RPMs and output ISOs (git-ignored). `build/hardware.env`,
  `build/bt-pairings/` and `build/sensors/` hold your unit's identity, pairing keys and sensor calibration;
  keep them private.

## License and credits

The scripts, templates and documentation in this repository are licensed under the GNU General Public
License, version 3 or later (`LICENSE`). They download and package third-party work at build time;
nothing third-party is stored in the repository:

- Kernel: [ooaklee/linux_ms_dev_kit-sp11](https://github.com/ooaklee/linux_ms_dev_kit-sp11) (GPL-2.0),
  released through [ooaklee/linux-surface-pro-11-oe](https://github.com/ooaklee/linux-surface-pro-11-oe),
  which also provides the FullIO audio topology and UCM files, the iptsd integration templates (MIT,
  `userspace/iptsd-sp11/LICENSE.integration`) and `sp11-bt-set-addr.c`. That repository has no
  top-level license; the audio files and the helper carry no license statement, and the release notes
  say the topology contains vendor-derived bytes that must stay outside kernel packages.
- Pen daemon: [linux-surface/iptsd](https://github.com/linux-surface/iptsd) (GPL-2.0-or-later and MIT),
  unmodified.
- Wi-Fi board data: `board-2.bin` from Fedora's `atheros-firmware`, extracted with `ath12k-bdencoder`
  from [qca/qca-swiss-army-knife](https://github.com/qca/qca-swiss-army-knife).
- Sensors: [linux-msm/hexagonrpc](https://github.com/linux-msm/hexagonrpc) (GPL-3.0-or-later), built from
  [this project's fork](https://github.com/FadyAckad/hexagonrpc), branch `sp11-sensors`: upstream plus five
  commits (the sensor framework's registry writes, requests longer than 256 bytes, the registry's parent
  directory, and the fixes those write paths needed; meant for upstream, see its issue #19 and pull
  request #21),
  [DylanVanAssche/libssc](https://codeberg.org/DylanVanAssche/libssc) (GPL-3.0-or-later) and Fedora's
  `iio-sensor-proxy` source RPM (GPL-3.0-or-later), the latter two unmodified; the approach follows
  [denisix/ubuntu-surface-pro-11](https://github.com/denisix/ubuntu-surface-pro-11). The sensor configuration
  and registry that `sp11-sensors` carries are proprietary Microsoft and Qualcomm files copied from your own
  Windows installation at build time, like the firmware below.
- Base media: Fedora Workstation live images. Bring-up notes: rjindael/fedora-surface-pro-11.
- ADSP/CDSP/GPU firmware: proprietary Qualcomm and Microsoft files copied from your own Windows
  DriverStore at build time. Never part of this repository; see Status and scope.

Two upstream files are modified during the build, and the changes are not upstream: the octet order in
`sp11-bt-set-addr.c` (see above) and the ALSA UCM device matcher in `x1e80100.conf`, which gains the
`( with 5G)?` alternative.
