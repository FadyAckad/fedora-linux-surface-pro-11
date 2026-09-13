# Fedora Workstation Live ISO for Surface Pro 11 (Snapdragon X Elite, OLED, 5G SKU)

Builds a Fedora Workstation Live ISO (aarch64) that boots and installs on a
Microsoft Surface Pro with 5G, 11th Edition (SKU `Surface_Pro_with_5G_11th_Edition_2077`,
X1E80100, Samsung OLED) with kernel `7.2.0-jg-0sp11v23-qcom-x1e` from
[ooaklee/linux_ms_dev_kit-sp11](https://github.com/ooaklee/linux_ms_dev_kit-sp11) and the
Denali OLED device tree loaded explicitly by GRUB.

Working: display + GPU acceleration, Wi-Fi, Bluetooth, touchscreen (multi-touch), pen,
speakers, microphone, keyboard/touchpad, battery. Not covered: 5G modem, cameras.
Audio and battery status are unavailable in the *live* session only (the audio DSP stays off
while running from USB-C, as Fedora's WoA install notes require); both work once installed.

Everything runs on the Surface itself inside WSL (Fedora aarch64) so the kernel builds natively
and the device firmware is read from the Windows partition on `C:`.

## Build

Requirements: WSL Fedora 44 aarch64 on the Surface, passwordless `sudo`, Windows on `C:`, 40 GiB free,
internet. Each step is idempotent; `FORCE=1` rebuilds a step.

1. `scripts/00-setup-host.sh` — installs build dependencies, checks the host.
2. `scripts/05-detect-hardware.sh` — reads SKU, panel and Bluetooth address from Windows, validates every
   regex against this machine, writes `build/hardware.env`.
3. `scripts/10-fetch-sources.sh` — downloads and checksum-verifies the Fedora ISO, the ooaklee kernel source
   tarball, the FullIO v19c audio files, pinned iptsd/OE checkouts and helper sources.
4. `scripts/20-build-kernel.sh` — compiles the kernel natively with ooaklee's exact annotations config
   (about 15 min on the Surface's 12 cores) and packages it as `kernel-sp11` RPM. `KERNEL_MODE=prebuilt`
   repackages ooaklee's released `.deb` payload instead (1 min); both produce the same 7816-module set.
5. `scripts/30-build-support-rpm.sh` — `sp11-surface-support` RPM: ADSP/CDSP/GPU firmware from the Windows
   DriverStore, audio topology + ALSA UCM (matcher fixed for the 5G SKU), WCN7850 `board.bin`, Bluetooth
   address service, kernel-install boot-policy plugin, dracut policy, first-boot finalizer.
6. `scripts/40-build-iptsd-rpm.sh` — `sp11-iptsd` RPM (pinned upstream iptsd + ooaklee's SP11 integration).
7. `scripts/50-build-iso.sh` — remasters the live root (EROFS/LZMA, SELinux labels), builds the live
   initramfs for the SP11 kernel, writes the GRUB menu and replays the hybrid boot layout.
   Output: `build/out/Fedora-Workstation-Live-44-1.7-SP11-7.2.0-jg-0sp11v23-qcom-x1e.aarch64.iso` (+ `.sha256`).

`scripts/build-all.sh` runs steps 1 to 7 (about 45 min in total after the downloads).
`scripts/60-verify-rootfs.sh` (optional) checks the remastered root and simulates Anaconda's kernel-install
hand-off in a chroot, proving the BLS entry gets the Denali DTB and the SP11 kernel arguments.

## Use

8. Write the ISO to a USB stick (16 GB or more). Windows: Rufus in **DD image** mode, or Fedora Media Writer.
   Linux: `sudo dd if=<iso> of=/dev/sdX bs=4M status=progress oflag=sync`.
9. In Windows, shrink `C:` to free at least 60 GB for Fedora. Keep Windows: it is the firmware source.
10. Hold Volume-Up + Power to enter the Surface UEFI, disable **Secure Boot**, set USB first in boot order.
11. Boot the USB and take the first GRUB entry. No kernel arguments need to be typed.
12. Run "Install to Hard Drive", choose "Install alongside", finish, reboot without the USB.
13. Log in. The first boot runs `sp11-first-boot.service` once (enables the audio DSP, finalizes GRUB and the
    initramfs). Check with `systemctl status sp11-first-boot`; if audio is not up yet, reboot once.

## What the scripts decide for you

- Kernel: ooaklee `7.2.0-jg-0sp11v23` source, config exported from `debian.qcom-x1e/config/annotations`
  (identical to the shipped config except `CONFIG_LOCALVERSION`, which carries the ABI, and
  `CONFIG_VERSION_SIGNATURE`). FIPS is not compiled in and never enabled; the initramfs omits the dracut
  `fips` modules.
- Device tree: `qcom/x1e80100-microsoft-denali-oled.dtb`, always loaded explicitly (GRUB `devicetree` on the
  live media, `GRUB_DEVICETREE` in every BLS entry on the installed system via
  `/usr/lib/kernel/install.d/15-sp11-surface.install`). Fedora's own stubble hardware-ID database does not
  contain this 5G SKU, so automatic DTB selection would fail on this machine.
- Kernel arguments: `clk_ignore_unused pd_ignore_unused systemd.tpm2_wait=0
  soundwire_qcom.sp11_feedback_active_offset2_zero=1`; live media adds `modprobe.blacklist=qcom_q6v5_pas
  rd.driver.blacklist=qcom_q6v5_pas`, removed again on the installed system.
- GRUB: `gfxterm` at `1024x768,800x600,auto` on live media and installed system.
- The stock Fedora kernel stays installed in the live root but hidden from Anaconda; the Troubleshooting menu
  keeps a stock-kernel entry with the Denali DTB.
- LSM: the ooaklee config's LSM list (`landlock,lockdown,yama,integrity,apparmor`) activates AppArmor, not
  SELinux, so Fedora runs without MAC enforcement on this kernel. Because the config also sets
  `CONFIG_SECURITY_APPARMOR_RESTRICT_USERNS=y` and Fedora has no AppArmor profiles, the support RPM ships
  `/usr/lib/sysctl.d/90-sp11.conf` with `kernel.apparmor_restrict_unprivileged_userns = 0`; without it
  Flatpak, browser sandboxes and rootless containers fail with `bwrap: Creating new namespace failed`.

## Fedora 45 or a newer kernel release

Edit `sp11.conf`: `FEDORA_RELEASE`, `FEDORA_COMPOSE` (from the release's ISO filename), and for a new kernel
`KERNEL_RELEASE_TAG`, `KERNEL_PKG_VERSION`, `KERNEL_UPSTREAM_VERSION`, `KERNEL_RPM_RELEASE`,
`KERNEL_SOURCE_COMMIT` (all printed on the ooaklee release page). Then `FORCE=1 scripts/build-all.sh`.
The ISO layout (volume id, marker file, kernel/initrd paths, font) is read from the ISO, not assumed.
Points that may need attention on a new release: a new alsa-ucm may already ship a Surface Pro 11 matcher
(the support RPM replaces the x1e80100 selector file), dracut/anaconda behaviour changes, and the
`x1e80100.conf` regex substitution in `scripts/30-build-support-rpm.sh` which expects ooaklee's v19c file.

## Layout

- `sp11.conf` — all versions, URLs, regexes and boot policy.
- `scripts/` — numbered pipeline steps plus `lib.sh` (helpers) and `build-all.sh`.
- `rpm/` — spec templates for `kernel-sp11`, `sp11-surface-support`, `sp11-iptsd`.
- `files/` — payload shipped in the support RPM and the GRUB menu template.
- `build/` — caches, work trees, RPMs and the output ISO (git-ignored).

The support RPM contains proprietary Qualcomm firmware copied from this device's Windows installation.
Do not redistribute the RPM or the ISO.
