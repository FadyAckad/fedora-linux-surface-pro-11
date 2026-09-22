# Hardware-verified status
What has been confirmed on the tested unit, by date and package version.

## Fedora 44 GA Workstation (2026-09-13/14, support RPM 1.7)

Working: boot, install, display/GPU, Wi-Fi, Bluetooth with the correct address, touch, pen inking, audio, battery,
Flatpak, Windows entry in GRUB before UEFI Firmware Settings, shared Windows pairings for keyboard and pen,
`sp11-bt-import-pairings` and `sp11-diag` under `/usr/libexec/sp11`. Suspend and resume confirmed on 2026-09-17.

Support RPM 1.7 (`sp11-diag` enumerates paired devices instead of fixed addresses; otherwise identical to 1.6, which
added `sp11-grub-defaults` and the dnf kernel exclusion) was confirmed working on the installed system on
2026-09-14. `sp11-iptsd` 3.1.0-2.sp11 restarts the running pen daemon on upgrade. The Fedora 44 ISO built on
2026-09-14 (sha256 `eb62a087…7fee`) contains both.

## Fedora 45 Beta 1.3 Workstation (2026-09-16)

Built with `FEDORA_TARGET=beta` and installed on the tested unit, onto a LUKS-encrypted root. Confirmed: the media
boots and installs, the installed system runs (dnf, desktop applications), and the SP11 kernel is the booted one.
`qcom_q6v5_pas` loads on the installed system, so the live-only blacklist is being dropped as intended.

`dnf upgrade --refresh` on the fresh install added a stock `kernel-uki-dtbloader-7.2.5-300.fc45` boot entry, because
the exclusion list predated that package (support RPM 1.8 adds `kernel-uki-*`); removing it needed
`dnf --setopt=disable_excludes='*' remove`.

Benign boot-time messages on this unit: `qcom_pmic_glink … Failed to create device link (0x180) with supplier …` for
the PD and USB nodes (probe deferral, retried); `surface_hid … unexpected descriptor length: got 0, expected 9` then
`error -71` for one Surface Aggregator HID endpoint that nothing depends on; with kernel revision 2,
`unknown device posture for type-cover: 0` once each time the keyboard is attached.

Confirmed working on the installed system by the owner on 2026-09-16: the 44 GA list above, the Bluetooth pairing
import, no early-boot Adreno error with support RPM 2.0, a clean `dnf upgrade --refresh` after the `kernel-uki-*`
exclusion, and support RPM 2.1 as an upgrade (stock kernel removed, `dracut --regenerate-all -f` clean). Suspend and
resume confirmed on 2026-09-17.

## Kernel 7.2.5 on Fedora 45 Beta Workstation (2026-09-17)

`kernel-sp11-7.2.5-sp11v23` (`KERNEL_STABLE_VERSION=7.2.5`, built with `FEDORA_TARGET=beta`) installed next to 7.2.0
on the 45 Beta install. Confirmed working by the owner: Bluetooth, touchscreen, Wi-Fi, pen, suspend and resume,
speakers, microphone, GPU acceleration, keyboard/touchpad, battery, Flatpak, the Windows GRUB entry, the keyboard
and pen pairings shared with Windows, backlight control (brightness slider) and multi-touch
(rjindael/fedora-surface-pro-11's HID-over-SPI patches give single touch only). 7.2.5 is the build default since
then; a 45 Beta ISO with this kernel was built on 2026-09-18 (never booted) and one with revision 2 on 2026-09-22,
installed on the tested unit (see below).

## Kernel config policy rev 1, SELinux (2026-09-18)

`kernel-sp11-7.2.5-sp11v23.1` and support RPM 2.5 (`FEDORA_TARGET=beta`), installed as an update on the 45 Beta
Workstation system next to the AppArmor kernels: nothing regressed. The installation still carried the installer's
`selinux=0` and `SELINUX=disabled` (the LSM list read `lockdown,capability,yama,bpf,landlock,ipe,ima,evm`; see the
`liveinst` bullet in `docs/kernel.md`); since the restore on 2026-09-19 it runs SELinux **enforcing** with no
kernel AVC. Off-hardware before the hand-off: the shipped config differs from the AppArmor build only by the policy
and what it pulls in (`SECURITY_APPARMOR*` off, `IGH_ECAT*` off, `SECURITY_IPE` on with its verity properties,
`DEFAULT_SECURITY_SELINUX`, `CONFIG_LSM`, `ZSTD_COMPRESS` y→m because AppArmor's `EXPORT_BINARY` had selected it
built-in, plus `LOCALVERSION`/`VERSION_SIGNATURE`); 7816 modules (`ec_master` gone, `zstd_compress` new); both
Denali DTBs byte-identical to the AppArmor build; steps 36 and 35 pass. The ISO was rebuilt on 2026-09-22 with
revision 2 (next section).

## Kernel SP11 revision 2, tablet mode (2026-09-21)

`kernel-sp11-7.2.5-sp11v23.2`, installed as an update on the same system. Rebuilt on the revision-1 tree in 7.6 min;
against revision 1: the same 7816 module names, identical DTBs, a config that differs only in
`LOCALVERSION`/`VERSION_SIGNATURE`, and at section level only `surface_aggregator_registry.ko` changed (its
`.rela.data`: the SP11 group's switch entry now points at the POS node) besides version strings and `kheaders.ko`.
On the device the POS tablet-mode switch follows the keyboard, and with the sensors stack GNOME's auto-rotation
works (see `docs/sensors.md`). A 45 Beta 1.3 ISO with this kernel, support 2.6, the `--mkfs-time` fix and the
sensors stack inside was built on 2026-09-22 (sha256 `121e542a…be65`, after a first build of the day without the
stack; `build-all.sh` took 11 min with everything cached, 35 passed on its reinstall branch, 46 reinstalling over
the root, 60 its 87 checks) and installed fresh on the tested unit the same day (next section).

## Fedora 45 Beta Workstation from the revision-2 ISO (2026-09-22)

Fresh installation from the ISO built on 2026-09-22 (sha256 `121e542a…be65`: kernel v23.2, support RPM 2.6, iptsd
3.1.0-3, the sensors stack, `--mkfs-time`). The owner reports every check of the hand-off list passing: the live
session and the installed system run SELinux enforcing without `selinux=0` or a relabel boot (the first media built
with the SELinux kernel), package file times instead of the ISO's build date, the seven packages installed, the
sensors stack active from the first boot without a separate install (`sp11-sensors-check`, auto-rotation), the
pairing import, the Windows entry, `dnf upgrade --refresh` without a stock kernel, and the README's feature table.

## Sensors stack (2026-09-19 to 2026-09-21)

On the 45 Beta install: `hexagonrpc-0.5.0-6.git79d1bed.sp11`, `libssc-0.4.4-2.git54dd13e.sp11`,
`iio-sensor-proxy-3.9-3.sp11.1` and `sp11-sensors-1.9-1` (fc45); support RPM 2.6 adds `sp11-sensors-check` to
`sp11-diag`. `sp11-sensors-1.10-1` (2026-09-22: the initramfs is regenerated by a trigger only when a 1.1/1.2
package is upgraded away, `sp11-sensors-reset` says the copy is read at the next boot, comments) is verified in the
chroot (step 46: 131 checks, the upgrade from 1.9 included) and on the device since the 2026-09-22 installation
from the ISO. Working:
readings from the light sensor, accelerometer, gyroscope, magnetometer and compass (`ssccli`),
`monitor-sensor` with orientation, tilt, light and compass, GNOME's auto-rotation, suspend and resume, SELinux
enforcing without an AVC for the stack's domains, no ADSP crash since the write support. Not reported: automatic
screen brightness. Step 46 passed for this set (129 checks, the upgrade from 1.8 included). The history is at the
end of `docs/sensors.md`.
