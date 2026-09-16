# Fedora Workstation Live ISO for Surface Pro 11 (Snapdragon X Elite, OLED, incl. the 5G SKU)

Builds a Fedora Workstation Live ISO (aarch64) that boots and installs on a Microsoft Surface Pro,
11th Edition with the Samsung OLED panel (Snapdragon X Elite X1E80100), using kernel
`7.2.0-jg-0sp11v23-qcom-x1e` from
[ooaklee/linux_ms_dev_kit-sp11](https://github.com/ooaklee/linux_ms_dev_kit-sp11) and the Denali
OLED device tree loaded explicitly by GRUB. The scripts read your unit's identity, Bluetooth address
and device firmware from its Windows installation, so the media they produce is tailored to that unit.

Verified on the tested unit (5G SKU `Surface_Pro_with_5G_11th_Edition_2077`): display with GPU acceleration, Wi-Fi, Bluetooth, touchscreen, pen, speakers,
microphone, keyboard/touchpad, battery, Flatpak, Windows in the GRUB menu, and Bluetooth pairings of
the Flex Keyboard and Slim Pen 2 shared with Windows. Not covered: 5G modem, cameras. In the *live*
session only, audio and battery status are unavailable because the audio DSP stays off while running
from USB-C; both work once installed.

Everything runs on the Surface itself inside WSL (Fedora aarch64): the kernel builds natively and the
device firmware is read from the Windows installation on `C:`.

## Status and scope

- Unofficial community project, not affiliated with Microsoft, Qualcomm, Fedora or ooaklee. No warranty.
- Tested only on the 5G OLED SKU. The hardware checks also accept the non-5G OLED SKUs
  (`Surface_Pro_11th_Edition_2076`, `Surface_Pro_11th_Edition_For_Business_2085`), which share the
  device tree, firmware file names and digitizer IDs, but no build from one has been reported. The
  X1P64100 LCD variant uses a different device tree and is rejected by `scripts/05-detect-hardware.sh`.
- Secure Boot must be disabled: the kernel is unsigned. FIPS is not compiled in.
- Windows must stay on the device. It provides the hardware identity, the built-in radio's Bluetooth
  address and the ADSP/CDSP/GPU firmware. Without it the build stops in steps 2 and 5, and an
  installed system would have no audio, battery reporting or GPU acceleration.
- The support RPM and the ISO you build contain proprietary Qualcomm firmware copied from your own
  Windows installation. Do not redistribute them; point other people to this repository instead.

## Build

Requirements: WSL Fedora 44 aarch64 on the Surface, `sudo` (step 7 and the verifier extract the live
root with ownership and xattrs preserved and chroot into it; make it passwordless if `build-all.sh`
should run unattended), Windows on `C:`, 40 GiB free, internet. Every step is idempotent and skips
finished work; `FORCE=1` rebuilds a step.

1. `scripts/00-setup-host.sh` installs build dependencies and checks the host.
2. `scripts/05-detect-hardware.sh` reads SKU, panel and Bluetooth address from Windows, validates
   every regex against your machine, writes `build/hardware.env`.
3. `scripts/10-fetch-sources.sh` downloads and checksum-verifies the Fedora ISO, the ooaklee kernel
   source, the FullIO v19c audio files, pinned iptsd/OE checkouts, helper sources and the runtime
   packages the live image lacks.
4. `scripts/20-build-kernel.sh` compiles the kernel natively with ooaklee's exact annotations config
   (about 15 min) into the `kernel-sp11` RPM. `KERNEL_MODE=prebuilt` repackages ooaklee's released
   `.deb` payload instead (1 min); both yield the same 7816-module set.
5. `scripts/30-build-support-rpm.sh` builds the `sp11-surface-support` RPM: ADSP/CDSP/GPU firmware
   from the Windows DriverStore, audio topology and ALSA UCM, WCN7850 `board.bin`, Bluetooth address
   service, kernel-install boot-policy plugin with the shared `sp11-grub-defaults` helper, dracut,
   sysctl and dnf policy, Windows GRUB entry, first-boot finalizer, and the `sp11-bt-import-pairings`
   and `sp11-diag` tools. The step rebuilds automatically when its `VERSION=` differs from the cached RPM.
6. `scripts/40-build-iptsd-rpm.sh` builds the `sp11-iptsd` RPM (pinned upstream iptsd plus ooaklee's
   Surface Pro 11 integration).
7. `scripts/50-build-iso.sh` remasters the live root (EROFS/LZMA with SELinux labels), installs the
   RPMs with dependency checking, builds the live initramfs for the SP11 kernel, writes the GRUB menu
   and replays the hybrid boot layout.
   Output: `build/out/Fedora-Workstation-Live-44-1.7-SP11-7.2.0-jg-0sp11v23-qcom-x1e.aarch64.iso`
   plus `.sha256`.

`scripts/build-all.sh` runs all seven steps (about 45 min after the downloads).
`scripts/60-verify-rootfs.sh` checks the remastered root: RPM dependencies, loadable binaries, an
Anaconda-style `kernel-install` in a chroot (BLS entry with the Denali DTB and the SP11 arguments), and
the Windows entry generator against a fake ESP.

### Hand-written `build/hardware.env`

Step 2 needs `powershell.exe` (WSL interop). Where that is unavailable, write `build/hardware.env`
yourself with the values Windows reports (System Information, or the PowerShell queries in
`scripts/05-detect-hardware.sh`), then re-run the step; it validates the file against the same regexes.
Example for the tested SKU:

```sh
SP11_PRODUCT="Microsoft Surface Pro with 5G, 11th Edition"    # Win32_ComputerSystem.Model
SP11_SKU="Surface_Pro_with_5G_11th_Edition_2077"               # Win32_ComputerSystem.SystemSKUNumber
SP11_FAMILY="Surface"                                          # Win32_ComputerSystem.SystemFamily
SP11_BOARD_VENDOR="Microsoft Corporation"                      # Win32_BaseBoard.Manufacturer
SP11_BOARD_NAME="Microsoft Surface Pro with 5G, 11th Edition"  # Win32_BaseBoard.Product
SP11_CPU="Snapdragon(R) X 12-core X1E80100 @ 3.40 GHz"         # Win32_Processor.Name
SP11_BIOS="<UEFI version>"                                     # Win32_BIOS.SMBIOSBIOSVersion
SP11_PANEL_VENDOR="SDC"                                        # WmiMonitorID.ManufacturerName of the built-in panel
SP11_BT_MAC="XX:XX:XX:XX:XX:XX"                                # built-in radio (Settings > Bluetooth & devices > More
                                                               #   Bluetooth settings, or DEVPKEY_Bluetooth_RadioAddress)
SP11_UCM_DMI_INFO="Microsoft Corporation-Surface-Microsoft Surface Pro with 5G, 11th Edition"  # VENDOR-FAMILY-BOARD
SP11_DTB_SELECTED="qcom/x1e80100-microsoft-denali-oled.dtb"    # must equal SP11_DTB in sp11.conf
```

## Install

1. Write the ISO to a USB stick of 16 GB or more: Rufus in **DD image** mode or Fedora Media Writer
   on Windows; on Linux `sudo dd if=<iso> of=/dev/sdX bs=4M status=progress oflag=sync` after
   confirming the target with `lsblk` (`dd` erases it).
2. In Windows, shrink `C:` to free at least 60 GB. Keep Windows: it is the firmware source.
3. Hold Volume-Up + Power to enter the Surface UEFI, disable **Secure Boot**, put USB first in the
   boot order.
4. Boot the USB and take the first GRUB entry. No kernel arguments need to be typed.
5. Run "Install to Hard Drive", choose "Install alongside", finish, reboot without the USB.
6. Log in. `sp11-first-boot.service` runs once: it enables the audio DSP, finalizes GRUB (Denali DTB,
   low resolution, Windows entry) and rebuilds the initramfs. If audio is not up yet, reboot once.

## Update an installed system

New support-RPM versions apply without reinstalling. Copy the RPM from `build/rpms/` (reachable from
Windows at `\\wsl.localhost\<distro>\<path to this clone>\build\rpms\`) to a USB stick and run on
Fedora:

```bash
sudo dnf upgrade ./sp11-surface-support-<version>.fc44.aarch64.rpm
```

The package regenerates `/boot/grub2/grub.cfg` itself. Rebuild the ISO afterwards so new installs
carry the same version. Upgrading `sp11-iptsd` restarts the running pen daemon.

Support RPM history:

- 1.1: `kernel.apparmor_restrict_unprivileged_userns=0`, so Flatpak's bwrap works.
- 1.3: Windows Boot Manager entry in GRUB, placed before UEFI Firmware Settings (1.2 had it after).
- 1.4: Bluetooth address written in the right octet order; earlier versions came up byte-reversed.
- 1.5: `sp11-bt-import-pairings` and `sp11-diag` under `/usr/libexec/sp11`.
- 1.6: `sp11-grub-defaults` as the single writer of the `/etc/default/grub` policy; dnf exclusion of the
  stock kernel packages.
- 1.7: `sp11-diag` reports every Bluetooth device BlueZ knows instead of two fixed addresses; license
  tag GPL-3.0-or-later. Confirmed on hardware 2026-09-14.
- 1.8: the stock-kernel dnf exclusion also covers `kernel-uki-*`. On aarch64 the boot kernel is owned by
  `kernel-uki-dtbloader`, not `kernel-core`, so on Fedora 45 an upgrade could still add a stock kernel
  boot entry. Found on an installed system 2026-09-16.
- 1.9: corrected the override hint in the exclusion file. dnf5 has no `--disableexcludes`; use
  `dnf --setopt=disable_excludes='*' ...`, which is also needed to *remove* an excluded stock kernel.
  The current ISO carries it.

## Bluetooth pairings from Windows (Flex Keyboard, Slim Pen 2)

BLE devices keep one bond per host address. The Linux controller uses the same address as Windows, so
copying Windows' pairing keys into BlueZ makes both systems work without re-pairing. Run in WSL:

```bash
scripts/70-export-bt-pairings.sh
```

Every run exports the registry subtree `BTHPORT\Parameters` afresh (one UAC prompt: the keys are
readable only with elevation), converts the Flex Keyboard and Slim Pen 2 bonds (selected by USB ID,
`BT_PAIRING_USB_IDS` in `sp11.conf`) into BlueZ `info` files and writes
`build/out/sp11-bt-pairings.tar.gz`. Copy the tarball to Fedora via USB and run:

```bash
tar -xzf sp11-bt-pairings.tar.gz && sudo /usr/libexec/sp11/sp11-bt-import-pairings
```

Existing Linux pairings for the same devices are backed up under `/var/lib/sp11/`. Re-pairing a device
in either OS invalidates the other side's bond; re-run the export afterwards. The tarball contains
secrets; do not share it.

## Diagnostics

`sudo /usr/libexec/sp11/sp11-diag` writes `sp11-diag-<date>.txt` into the current directory with the
kernel, touchscreen/pen (iptsd), input and Bluetooth state, including `bluetoothctl info` for every
device BlueZ knows. It changes nothing.

## What the scripts decide for you

- Kernel: ooaklee `7.2.0-jg-0sp11v23` source; config exported from
  `debian.qcom-x1e/config/annotations` and identical to the released config except
  `CONFIG_LOCALVERSION` (carries the ABI) and `CONFIG_VERSION_SIGNATURE`. FIPS is not compiled in and
  the initramfs omits the dracut `fips` modules.
- Device tree: `qcom/x1e80100-microsoft-denali-oled.dtb`, loaded explicitly everywhere (GRUB
  `devicetree` on the live media, `GRUB_DEVICETREE` in every BLS entry via
  `/usr/lib/kernel/install.d/15-sp11-surface.install`). Fedora's stubble hardware-ID database does not
  contain the 5G SKU, so automatic DTB selection cannot work on this model.
- Kernel arguments: `clk_ignore_unused pd_ignore_unused systemd.tpm2_wait=0
  soundwire_qcom.sp11_feedback_active_offset2_zero=1`. Live media adds
  `modprobe.blacklist=qcom_q6v5_pas rd.driver.blacklist=qcom_q6v5_pas`; the installed system drops them.
- GRUB: `gfxterm` at `1024x768,800x600,auto` on live media and installed system. Live menu: the SP11
  kernel, a verbose variant, and a `nomodeset` variant. Installed menu order: Fedora entries, Windows
  Boot Manager, UEFI Firmware Settings.
- Windows dual-boot: `/etc/grub.d/29_sp11_windows` finds the ESP holding
  `EFI/Microsoft/Boot/bootmgfw.efi` (a separate Windows ESP is fine) and emits a chainload entry.
  Fedora's aarch64 GRUB image lacks the `chain` module and Fedora's os-prober has no EFI Windows probe
  on aarch64, so the module is copied from `grub2-efi-aa64-modules` into `/boot/grub2/arm64-efi/`
  (loadable because Secure Boot is off).
- Flatpak and other sandboxes: ooaklee's config activates AppArmor with
  `CONFIG_SECURITY_APPARMOR_RESTRICT_USERNS=y`, and Fedora has no AppArmor profiles, so unprivileged
  user namespaces would be denied. `/usr/lib/sysctl.d/90-sp11.conf` sets
  `kernel.apparmor_restrict_unprivileged_userns = 0`. SELinux is compiled in but not active with this
  kernel; Fedora runs without MAC enforcement.
- Bluetooth address: ooaklee's helper writes the controller address byte-reversed; the RPM build patches
  the octet order so Linux and Windows use the same address (the one Windows reports for the built-in
  radio), which the shared pairings depend on.
- Audio: ooaklee FullIO v19c topology and UCM; the UCM device matcher is corrected to match the 5G SKU.
- Pen: `sp11-iptsd` links against Fedora's `spdlog`, `fmt` and `inih`, which Workstation Live does not
  all ship; the ISO build adds them (`LIVE_EXTRA_PKGS` in `sp11.conf`) and refuses RPMs with unmet
  dependencies.
- The stock Fedora kernel stays installed in the live root but hidden from Anaconda so the SP11 kernel
  is the one installed. On the installed system `/etc/dnf/libdnf5.conf.d/90-sp11.conf` excludes the
  stock kernel packages (`kernel`, `kernel-core`, `kernel-modules*`) from dnf, so an update cannot add a
  boot entry for a kernel without Surface support (`dnf --disableexcludes=all` overrides it once).
- The live initramfs carries only the GPU zap shader; the ADSP/CDSP firmware (about 26 MiB) goes into
  the installed system's initramfs, where the DSP actually runs.
- Hardware detection uses the built-in panel (WMI connection type internal) and the built-in Bluetooth
  radio's address, so an external monitor or a USB Bluetooth dongle attached during detection does not
  change the result.

## Fedora 45 or a newer kernel release

Edit `sp11.conf`: `FEDORA_RELEASE`, `FEDORA_COMPOSE` (from the release's ISO filename) and, for a new
kernel, `KERNEL_RELEASE_TAG`, `KERNEL_PKG_VERSION`, `KERNEL_UPSTREAM_VERSION`, `KERNEL_RPM_RELEASE`,
`KERNEL_SOURCE_COMMIT` (all on the ooaklee release page). Then run `FORCE=1 scripts/build-all.sh`.
Checksum-pinned downloads stay cached; the dnf-downloaded packages (`atheros-firmware`, the live-root
dependencies) are cached per Fedora release and re-downloaded with `FORCE=1`.
The ISO layout (volume id, marker file, kernel/initrd paths, font) is read from the ISO, not assumed.
The `x1e80100.conf` regex substitution in `scripts/30-build-support-rpm.sh` expects ooaklee's v19c file
and fails loudly if the file changes.

## Layout

- `sp11.conf` — all versions, URLs, regexes and boot policy.
- `scripts/` — numbered pipeline steps, `lib.sh` (helpers), `build-all.sh`, the pairing export.
- `rpm/` — spec templates for `kernel-sp11`, `sp11-surface-support`, `sp11-iptsd`.
- `files/` — payload shipped in the support RPM, the live GRUB menu template and the README inside the ISO.
- `LICENSE` — GPL-3.0-or-later for the repository's own content (see License and credits).
- `CLAUDE.md` — working notes: verified facts about the hardware, the Fedora media and pipeline pitfalls.
- `.gitattributes` — LF line endings for every file; the payload scripts break with CRLF.
- `build/` — caches, work trees, RPMs and the output ISO (git-ignored). `build/hardware.env` and
  `build/bt-pairings/` hold your unit's identity and pairing keys; keep them private.

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
- Base media: Fedora Workstation Live. Bring-up notes: rjindael/fedora-surface-pro-11.
- ADSP/CDSP/GPU firmware: proprietary Qualcomm and Microsoft files copied from your own Windows
  DriverStore at build time. Never part of this repository; see Status and scope.

Two upstream files are modified during the build and the changes are not upstream: the octet order in
`sp11-bt-set-addr.c` (see above) and the ALSA UCM device matcher in `x1e80100.conf`, which gains the
`( with 5G)?` alternative.
