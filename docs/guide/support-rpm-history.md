# Support RPM history

What each version of `sp11-surface-support` changed (`VERSION=` in `scripts/30-build-support-rpm.sh`). Versions 1.1
to 2.1, 2.5, 2.6 and 3.0 onwards were confirmed on the tested unit; 2.2 to 2.4 and 2.7 were verified in the chroot
only, and their changes reached the device with the next version installed there. The device results by date are
in [`docs/verified.md`](../verified.md).

- 1.1: Flatpak works (`kernel.apparmor_restrict_unprivileged_userns=0`).
- 1.3: Windows Boot Manager entry in GRUB, before UEFI Firmware Settings.
- 1.4: Bluetooth address in the right octet order; earlier versions set it byte-reversed.
- 1.5: `sp11-bt-import-pairings` and `sp11-diag` under `/usr/libexec/sp11`.
- 1.6: `sp11-grub-defaults` as the single writer of the `/etc/default/grub` policy; dnf excludes the stock kernel
  packages.
- 1.7: `sp11-diag` lists every Bluetooth device BlueZ knows; license tag GPL-3.0-or-later.
- 1.8: the dnf exclusion also covers `kernel-uki-*`, which owns the boot kernel on aarch64; without it an upgrade
  could add a stock kernel boot entry.
- 1.9: corrected override hint in the exclusion file: dnf5 has no `--disableexcludes`, the override is
  `dnf --setopt=disable_excludes='*' ...`.
- 2.0: the Adreno microcode (`gen70500_sqe.fw`, `gen70500_gmu.bin`) goes into the initramfs, so early boot no
  longer logs `failed to load gen70500_sqe.fw`. The package requires `qcom-firmware`.
- 2.1: `sp11-remove-stock-kernels.service` removes the hidden stock kernel once. `dracut --regenerate-all` no longer
  fails with `Can't write to /boot/efi/...`, and boot entries whose kernel image is missing are removed.
- 2.2: the stock-kernel cleanup accepts every installed `kernel-sp11` version as the running SP11 kernel, so it also
  works with several SP11 kernels installed side by side.
- 2.3: the ISO build removes the stock kernel packages, so `sp11-remove-stock-kernels` is gone. Only the five
  firmware files the device tree loads are shipped. A system that never ran the stock-kernel cleanup (older than
  2.1) needs 2.1 or 2.2 and one reboot before this update.
- 2.4: GRUB at the panel's native 2880x1920 with a 40 pt console font. `%posttrans` applies the GRUB policy before
  regenerating the menu, so an upgrade that changes a policy value takes effect.
- 2.5: the user-namespace sysctl is limited to the earlier AppArmor kernels (`-` prefix, ignored where the key does
  not exist). `sp11-diag` reports the active LSMs, `getenforce` and AVC denials. `sp11-selinux-restore` re-enables
  SELinux on installations the live installer disabled it on
  ([`docs/kernel.md`](../kernel.md), SELinux).
- 2.6: `sp11-diag` runs `sp11-sensors-check` when the sensors stack is installed.
- 2.7: the internal microphone's decimator gain (`UCM_MIC_GAIN`, +16 dB) in the UCM Mic device. `sp11-diag` reports
  the audio controls and the PipeWire source.
- 3.0: for the Fedora-based kernel: the stock-kernel exclusion becomes a dnf repository override (local kernel RPMs
  install without an override flag), `scmi-cpufreq` is loaded at boot, the FIPS dracut omission and the
  AppArmor-era sysctl and SELinux restore are gone, and `sp11-diag` gains a section that diffs cleanly between two
  kernels and records `systemd-analyze chid`.
- 3.1: `sp11-diag` reads the audio controls through the card's raw control interface (`amixer -D hw:N`); through
  `amixer -c N` it had found none of them. `sp11-cdsp-check.service` restarted the compute DSP once at boot when it
  ran without answering.
- 3.2: `sp11-cdsp-check` is gone: kernel revision 3 lets the compute DSP wake. `sp11-diag` lists the power-domain
  and interconnect providers still holding their boot-time votes and the devices they wait for.
- 3.3: `sp11-diag` reports the cameras: the camera packages, what the camera drivers bound, the device nodes and
  LEDs, the media graph, `cam -l`, and the kernel's and libcamera's camera messages. Goes with kernel revision 6.
- 3.4: `sp11-diag` takes the media devices as `/dev/media[0-9]*`. Updated installations also have a `/dev/media`
  directory, which the camera section had counted as device nodes and passed to `media-ctl`
  (`Failed to enumerate /dev/media (-21)`).
- 3.5: on the 5G SKU (the build decides by the unit's SKU): GRUB's device tree becomes the 5G tree with the modem
  (in the kernel since 7.2.11 revision 3), ModemManager leaves the modem's QMI port alone (otherwise the shutdown
  waits 45 s and every suspend fails), and a GNSS feed passes the modem's positions to GeoClue while an application
  asks for the exact location, with its SELinux module. Builds for the other SKUs carry none of it.
- 3.6: the GNSS feed pauses across a sleep instead of stopping: with 3.5, after a sleep, GeoClue never reconnected
  to it and used a full CPU core until the application stopped asking.
- 3.7: `sp11-diag` finds SELinux denials. It searched only the kernel's messages, where the audit daemon's denials
  never appear.
- 3.8: the video codec's firmware (`qcvss8380.mbn`), which the kernel requests from 7.2.11 revision 6 on.
- 3.9: on the 5G SKU, ModemManager's quick suspend/resume (a drop-in on its unit): with a kernel from 7.2.11
  revision 9, whose modem keeps its power through a sleep, mobile data is back 2 s after a wake instead of 52 s.
- 3.10: GRUB's console font is smaller (size 32 instead of 40: 150x50 characters instead of 119x39) and built to
  fit GRUB's character cell. With the earlier font the menu and its editor showed no underscores and cut the
  letters' descenders.
- 3.11: a udev rule keeps two clock votes of the audio block held (`78-sp11-speakers.rules`). With kernel 7.3.3
  the speakers could stay silent after a pause in the sound until the sound was stopped and started again;
  `sp11-diag` lists the amplifiers' bus state and the rule's setting
  ([`docs/hardware.md`](../hardware.md), Audio).
- 3.12: Secure Boot for the installed system, optional. `sp11-secureboot` keeps the copies and GRUB entries of
  signed boot images current, through a kernel-install plugin, a block in GRUB's menu and a unit, and `sp11-diag`
  lists its status; without a signed image none of it does anything
  ([`docs/guide/secure-boot.md`](secure-boot.md)).
- 3.13: with Secure Boot on, GRUB's menu is drawn on the firmware's console and has its frame again, where 3.12
  showed question marks. The text stays small ([`docs/secure-boot.md`](../secure-boot.md), GRUB under Secure
  Boot).
- 3.14: with Secure Boot on, a graphical menu names its entries by images, since GRUB loads no font file then:
  the signed kernels, Windows and the firmware settings, with a countdown bar. Escape leads to 3.13's text
  menu.
- 3.15: that menu looks like the usual one: every entry's full title, the frame, the help lines and the
  countdown in the usual font and size, drawn on the tablet at every sync
  (`/usr/libexec/sp11/sp11-secureboot-theme`). The screen is cleared whole before an entry starts: with 3.14
  a black box lay over the menu's middle while Windows started. Python is a requirement on every model now.
- 3.16: the same Secure Boot route with less code. `sp11-secureboot try`, the one start through the signed
  entry with Secure Boot still off, is gone: the guide goes from enrolling the key to switching Secure Boot on.
- 3.17: systemd's early TPM setup (`systemd-tpm2-setup-early.service`) runs only in the initramfs, which on
  Fedora does not carry it. In the root, SELinux refused it a write to systemd's TPM measurement log at every start
  with kernel 7.3.5 revision 2 or later ([`docs/hardware.md`](../hardware.md), TPM).
- 3.18: the live media add no kernel arguments of their own any more: their initramfs starts the audio DSP, as an
  installed system's does, because with kernel 7.3.5 USB-C carries no data without it. On an installed system it
  changes nothing ([`docs/hardware.md`](../hardware.md), The DSP on the live media).
- 3.19: the Windows entry is `--unrestricted`, as Fedora's own entries: with a GRUB password (`grub2-setpassword`)
  Windows starts without it, while the password guards GRUB's editor and command line
  ([`docs/guide/secure-boot.md`](secure-boot.md), 6).
- 3.20: os-prober is switched off (`GRUB_DISABLE_OS_PROBER=true`). From Fedora's os-prober 1.81-13 (2026-11-22)
  it found Windows as well and wrote a second entry of the same name, which asked for the GRUB password; the SP11
  entry is the only one again ([`docs/fedora-media.md`](../fedora-media.md), GRUB image, font and modules).
- 3.21: with Secure Boot on, a poweroff no longer turns into a restart when the TPM refuses systemd's `shutdown`
  measurement (a drop-in for `systemd-pcrphase.service`).
- 3.22: the same for the `final` measurement (`systemd-pcrphase-sysinit.service`), which with 3.21 alone still
  turned a poweroff into a restart after the TPM had failed ([`docs/hardware.md`](../hardware.md), TPM).
