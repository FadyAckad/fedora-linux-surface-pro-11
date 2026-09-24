# Support RPM history

What each version of `sp11-surface-support` changed (`VERSION=` in `scripts/30-build-support-rpm.sh`). Versions 1.1
to 2.1, 2.5, 2.6 and 3.0 onwards were confirmed on the tested unit; 2.2 to 2.4 and 2.7 were verified in the chroot
only, and their changes reached the device with the next version installed there. The device results by date are in
[`docs/verified.md`](../verified.md).

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
  `sp11-selinux-restore` re-enables SELinux on installations the live installer disabled it on
  ([`docs/guide/troubleshooting.md`](troubleshooting.md)). Installed together with the SELinux kernel
  `7.2.5-jg-0sp11v23.1-qcom-x1e`.
- 2.6: `sp11-diag` runs `sp11-sensors-check` when the sensors stack is installed. Installed on the device from the
  ISO built on 2026-09-22.
- 2.7: the internal microphone's decimator gain (`UCM_MIC_GAIN`, +16 dB) in the UCM Mic device; `sp11-diag`
  reports the audio controls and the PipeWire source. Never installed on the device on its own; its gain was
  confirmed with 3.0.
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
