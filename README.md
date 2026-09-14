# Fedora Workstation Live ISO for Surface Pro 11 (Snapdragon X Elite, OLED, 5G SKU)

Builds a Fedora Workstation Live ISO (aarch64) that boots and installs on a Microsoft Surface Pro
with 5G, 11th Edition (SKU `Surface_Pro_with_5G_11th_Edition_2077`, X1E80100, Samsung OLED) with
kernel `7.2.0-jg-0sp11v23-qcom-x1e` from
[ooaklee/linux_ms_dev_kit-sp11](https://github.com/ooaklee/linux_ms_dev_kit-sp11) and the Denali
OLED device tree loaded explicitly by GRUB.

Verified on this machine: display with GPU acceleration, Wi-Fi, Bluetooth, touchscreen, pen, speakers,
microphone, keyboard/touchpad, battery, Flatpak, Windows in the GRUB menu, and Bluetooth pairings of
the Flex Keyboard and Slim Pen 2 shared with Windows. Not covered: 5G modem, cameras. In the *live*
session only, audio and battery status are unavailable because the audio DSP stays off while running
from USB-C; both work once installed.

Everything runs on the Surface itself inside WSL (Fedora aarch64): the kernel builds natively and the
device firmware is read from the Windows installation on `C:`.

## Build

Requirements: WSL Fedora 44 aarch64 on the Surface, passwordless `sudo`, Windows on `C:`, 40 GiB
free, internet. Every step is idempotent and skips finished work; `FORCE=1` rebuilds a step.

1. `scripts/00-setup-host.sh` installs build dependencies and checks the host.
2. `scripts/05-detect-hardware.sh` reads SKU, panel and Bluetooth address from Windows, validates
   every regex against this machine, writes `build/hardware.env`.
3. `scripts/10-fetch-sources.sh` downloads and checksum-verifies the Fedora ISO, the ooaklee kernel
   source, the FullIO v19c audio files, pinned iptsd/OE checkouts, helper sources and the runtime
   packages the live image lacks.
4. `scripts/20-build-kernel.sh` compiles the kernel natively with ooaklee's exact annotations config
   (about 15 min) into the `kernel-sp11` RPM. `KERNEL_MODE=prebuilt` repackages ooaklee's released
   `.deb` payload instead (1 min); both yield the same 7816-module set.
5. `scripts/30-build-support-rpm.sh` builds the `sp11-surface-support` RPM: ADSP/CDSP/GPU firmware
   from the Windows DriverStore, audio topology and ALSA UCM, WCN7850 `board.bin`, Bluetooth address
   service, kernel-install boot-policy plugin, dracut and sysctl policy, Windows GRUB entry,
   first-boot finalizer, and the `sp11-bt-import-pairings` and `sp11-diag` tools.
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

## Install

1. Write the ISO to a USB stick of 16 GB or more: Rufus in **DD image** mode or Fedora Media Writer
   on Windows; on Linux `sudo dd if=<iso> of=/dev/sdX bs=4M status=progress oflag=sync`.
2. In Windows, shrink `C:` to free at least 60 GB. Keep Windows: it is the firmware source.
3. Hold Volume-Up + Power to enter the Surface UEFI, disable **Secure Boot**, put USB first in the
   boot order.
4. Boot the USB and take the first GRUB entry. No kernel arguments need to be typed.
5. Run "Install to Hard Drive", choose "Install alongside", finish, reboot without the USB.
6. Log in. `sp11-first-boot.service` runs once: it enables the audio DSP, finalizes GRUB (Denali DTB,
   low resolution, Windows entry) and rebuilds the initramfs. If audio is not up yet, reboot once.

## Update an installed system

New support-RPM versions apply without reinstalling. Copy the RPM from `build/rpms/` (reachable from
Windows at `\\wsl.localhost\<distro>\<path to this clone>\build\rpms\`) to a
USB stick and run on Fedora:

```bash
sudo dnf upgrade ./sp11-surface-support-<version>.fc44.aarch64.rpm
```

The package regenerates `/boot/grub2/grub.cfg` itself. Rebuild the ISO afterwards so new installs
carry the same version.

## Bluetooth pairings from Windows (Flex Keyboard, Slim Pen 2)

BLE devices keep one bond per host address. The Linux controller uses the same address as Windows, so
copying Windows' pairing keys into BlueZ makes both systems work without re-pairing. Run in WSL:

```bash
scripts/70-export-bt-pairings.sh
```

It exports the registry subtree `BTHPORT\Parameters` (one UAC prompt: the keys are readable only with
elevation), converts the Flex Keyboard and Slim Pen 2 bonds (selected by USB ID, `BT_PAIRING_USB_IDS`
in `sp11.conf`) into BlueZ `info` files and writes `build/out/sp11-bt-pairings.tar.gz`. Copy the
tarball to Fedora via USB and run:

```bash
tar -xzf sp11-bt-pairings.tar.gz && sudo /usr/libexec/sp11/sp11-bt-import-pairings
```

Existing Linux pairings for the same devices are backed up under `/var/lib/sp11/`. Re-pairing a device
in either OS invalidates the other side's bond; re-run the export afterwards. The tarball contains
secrets; do not share it.

## Diagnostics

`sudo /usr/libexec/sp11/sp11-diag` writes `sp11-diag-<date>.txt` into the current directory with the
kernel, touchscreen/pen (iptsd), input and Bluetooth state. It changes nothing.

## What the scripts decide for you

- Kernel: ooaklee `7.2.0-jg-0sp11v23` source; config exported from
  `debian.qcom-x1e/config/annotations` and identical to the released config except
  `CONFIG_LOCALVERSION` (carries the ABI) and `CONFIG_VERSION_SIGNATURE`. FIPS is not compiled in and
  the initramfs omits the dracut `fips` modules.
- Device tree: `qcom/x1e80100-microsoft-denali-oled.dtb`, loaded explicitly everywhere (GRUB
  `devicetree` on the live media, `GRUB_DEVICETREE` in every BLS entry via
  `/usr/lib/kernel/install.d/15-sp11-surface.install`). Fedora's stubble hardware-ID database does not
  contain the 5G SKU, so automatic DTB selection cannot work on this machine.
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
- Bluetooth address: ooaklee's helper wrote the controller address byte-reversed; the RPM build patches
  the octet order so Linux and Windows use the same address (`AA:BB:CC:DD:EE:FF`), which the shared
  pairings depend on.
- Audio: ooaklee FullIO v19c topology and UCM; the UCM device matcher is corrected to match the 5G SKU.
- Pen: `sp11-iptsd` links against Fedora's `spdlog`, `fmt` and `inih`, which Workstation Live does not
  all ship; the ISO build adds them (`LIVE_EXTRA_PKGS` in `sp11.conf`) and refuses RPMs with unmet
  dependencies.
- The stock Fedora kernel stays installed in the live root but hidden from Anaconda so the SP11 kernel
  is the one installed.

## Fedora 45 or a newer kernel release

Edit `sp11.conf`: `FEDORA_RELEASE`, `FEDORA_COMPOSE` (from the release's ISO filename) and, for a new
kernel, `KERNEL_RELEASE_TAG`, `KERNEL_PKG_VERSION`, `KERNEL_UPSTREAM_VERSION`, `KERNEL_RPM_RELEASE`,
`KERNEL_SOURCE_COMMIT` (all on the ooaklee release page). Then run `FORCE=1 scripts/build-all.sh`.
The ISO layout (volume id, marker file, kernel/initrd paths, font) is read from the ISO, not assumed.
The `x1e80100.conf` regex substitution in `scripts/30-build-support-rpm.sh` expects ooaklee's v19c file
and fails loudly if the file changes.

## Layout

- `sp11.conf` — all versions, URLs, regexes and boot policy.
- `scripts/` — numbered pipeline steps, `lib.sh` (helpers), `build-all.sh`, the pairing export.
- `rpm/` — spec templates for `kernel-sp11`, `sp11-surface-support`, `sp11-iptsd`.
- `files/` — payload shipped in the support RPM and the live GRUB menu template.
- `build/` — caches, work trees, RPMs and the output ISO (git-ignored).

The support RPM contains proprietary Qualcomm firmware copied from this device's Windows installation.
Do not redistribute the RPM or the ISO.
