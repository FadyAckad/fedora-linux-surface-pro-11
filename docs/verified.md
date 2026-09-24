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

## Fedora's kernel 7.2.5-300.sp11.1 and support RPM 3.0 (2026-09-23)

On the installation above: support RPM 3.0 as an upgrade, then `kernel`, `kernel-core` and
`kernel-modules{,-core,-extra}` `7.2.5-300.sp11.1.fc45` with `dnf install` next to `kernel-sp11` v23.2, and one
`sp11-diag` on each kernel. Confirmed from the owner's transcript and the two diag files: the new kernel boots as
the saved default with the same arguments and the Denali OLED device tree
(`microsoft,denali-oled microsoft,denali qcom,x1e80100`), SELinux enforcing without an AVC; the ADSP boots Linux's
firmware without a crash (mainline shuts the UEFI-started "lite" firmware down) and every stage of the
speaker-protection graph is accepted; the microphone records speech at about −22 dBFS RMS on both channels with
3.0's gain; the sensors stack reads light, accelerometer, gyroscope, magnetometer and compass, and
iio-sensor-proxy has the accelerometer, light sensor and compass; the touchscreen, pen, iptsd's virtual stylus, POS
tablet-mode switch, volume keys, Surface Aggregator keyboard and touchpad and the Flex Keyboard over Bluetooth are
present, and the Bluetooth controller has the unit's address as on v23.2; one battery (`qcom_battmgr`), the fan's
hwmon (`surface_fan`), `Surface Platform Profile` with four profiles, `scmi` cpufreq on all three policies; the GPU,
display, ath12k, NVMe and USB drivers bound; one suspend and resume (deep) with the iptsd sleep hooks. systemd's
`bpf-restrict-fs` now loads (v23.2 had no BTF: "Failed to load BPF object").

Confirmed by the owner the same day: Wi-Fi and Bluetooth connect and work, touch gestures, the pen, the speakers,
keyboard folding with tablet mode, the volume buttons, suspend and resume, Flatpak apps and the Windows entry in
GRUB.

Differences from v23.2: the camera stack is gone as intended (v23.2 exposed 16 CAMSS video nodes and `imx681` to
libcamera, but its picture was always far too dark; left out until a camera fix). Fedora's configuration also binds
the CoreSight tracing drivers, `qcomtee` and `surface_temp`. The CDSP link is down: the CDSP boots and opens its
QRTR channel, then neither answers the FastRPC channel's open (`failed to create endpoint`, error -12, no
`/dev/fastrpc-cdsp`) nor publishes its QRTR services (node 10). On v23.2 it worked from boot, then crashed once in
the same boot (`fatal error received: sleep_stats…`, a CDSP firmware fault Qualcomm's tracker also shows on other
boards) and remoteproc recovered it. Nothing in the feature table uses the CDSP.
`sp11-diag`'s audio section found none of its controls on either kernel (`amixer -c` opens the UCM's remapped
`sysdefault` interface; 3.1 reads `hw:N`). Not reported: GPU acceleration and the brightness slider, auto-rotation,
switching power profiles, USB-C.

## Kernel revision 2 (CDSP boot order) and support RPM 3.1 (2026-09-23)

`kernel`, `kernel-core` and `kernel-modules{,-core,-extra}` `7.2.5-300.sp11.2.fc45` with `dnf install` next to
revision 1 (the first confirmation on the device that support 3.0's repository override leaves local kernel RPMs
installable), then support 3.1 as an upgrade from 3.0; boot entry with the Denali DTB and the SP11 arguments, saved
default on the new entry. On two boots the CDSP waited for the ADSP as designed (`booting after adsp` 0.01 s after
`remote processor adsp is now up`) and still stopped answering: FastRPC's channel open timed out, and later it
answered neither sysmon's shutdown request nor the SMP2P stop. `sp11-cdsp-check` restarted it about 30 s after boot
both times (`CDSP answers after the restart`, 12 s for the restart): `/dev/fastrpc-cdsp` and the five CDSP QRTR
services were there, and no CDSP crash followed in the next minutes. So the boot order is not the cause; the
restarted CDSP, too, stopped answering at its next sleep (next section). Unchanged against revision 1: speakers,
microphone, sensors, one battery, no new kernel warning besides the two from the CDSP stop. 3.1's audio section
records the UCM's values (`TX_DEC0/1 Volume` 100, `WSA_RX0/1 Digital Volume` 81, `SpkrLeft/SpkrRight PA Volume` 24,
the TX MUX items).

## Sync state and kernel revision 3 (2026-09-24)

The QDSS clock held on did not change the CDSP, and on v23.2 the CDSP answered a QMI ping after 3 and 8 minutes
idle, with 12 completed sleeps. On revision 2 with support 3.1, `state_synced` read 0 for `rpmhpd` and for two of
the 19 interconnect providers (`aggre2_noc`, `mc_virt`) and 1 for the rest; the only links they still waited on went
to the video clock controller (`aaf0000.clock-controller`) and the crypto engine (`1dfa000.crypto`). Forcing
`rpmhpd`'s sync through sysfs made the CDSP, stuck since boot, answer the ping at once (its sleep counter went from
0 to 4); restarted, it answered again after 3 minutes idle, and its stop no longer timed out. Forcing the
interconnect's sync as well changed nothing further for the CDSP.

`kernel`, `kernel-core` and `kernel-modules{,-core,-extra}` `7.2.5-300.sp11.3.fc45` installed with `dnf install`
next to revision 2 and v23.2, after revision 1 was removed; entry with the Denali DTB and the SP11 arguments (plus
the `$tuned_params` placeholder of tuned's kernel-install plugin), saved default. First boot: all 20 providers
synced, `videocc_sm8550` and `qcrypto` loaded, no FastRPC error, the CDSP (sleep counter 7) and the ADSP answered
the ping after 3 minutes idle, and the CDSP again after a suspend and resume. On all three boots `sp11-cdsp-check`
logged `CDSP answers` without a restart and the CDSP answered after 3 minutes idle. New at boot: the crypto engine's
AES XTS and CTR fail the kernel's self-tests (`xts-aes-qce setkey failed ... actual_error=-126`,
`ctr-aes-qce encryption test failed (wrong output IV)`), which revision 4 leaves out. Across a 1-minute suspend the
chip's `aosd`, `cxsd` and `ddr` counters stayed at 0 on revision 2 and on revision 3 alike, so the deepest sleep is
not reached in suspend either way; the ADSP's sleep counter advances about 100 times a second, also while suspended.

Revision 4 (`7.2.5-300.sp11.4`: the crypto engine with its hashes only) and support RPM 3.2 were built the same
evening (steps 20, 35 and 36 passed), and with them a 45 Beta 1.3 ISO (sha256 `c60c2f6f…0dc0`; `build-all.sh` 10 min
with everything else cached, 35 and 46 passed, 60 its 90 checks, the implanted media checksum verifies); next
section.

## Fresh installation from the revision-4 ISO (2026-09-24)

The earlier installation had been deleted; the unit was installed fresh from that ISO (the live session's checks
were not recorded). Confirmed on the installed system: kernel `7.2.5-300.sp11.4` with the SP11 arguments and neither
the live-only blacklist nor `selinux=0`, SELinux enforcing without an AVC; support 3.2, `sp11-iptsd` 3.1.0-3 and the
sensors stack (hexagonrpc 0.5.0-6, libssc 0.4.4-2, iio-sensor-proxy 3.9-3.sp11.1, sp11-sensors 1.10) installed, no
`sp11-cdsp-check` unit; `/dev/fastrpc-adsp`, `/dev/fastrpc-cdsp` and `/dev/fastrpc-cdsp-secure`, both DSPs answering
the QMI ping; the crypto engine registers only `sha256-qce` and `hmac-sha256-qce` and no self-test fails;
`sp11-diag` reports no provider waiting for sync_state; light, accelerometer, gyroscope, magnetometer and compass
readings, iio-sensor-proxy running, the POS tablet-mode switch; the sound card with the UCM's values
(`TX_DEC0/1 Volume` 100, `WSA_RX0/1 Digital Volume` 81, `SpkrLeft/SpkrRight PA Volume` 24) and PipeWire's speaker
and microphone array as the defaults; one battery, the fan's hwmon, the platform profile, `scmi` cpufreq; the Flex
Keyboard and Slim Pen 2 pairings imported (keyboard connected); `dnf upgrade --refresh` without a stock kernel
(Fedora's `kernel-tools` 7.2.7, userspace only, did update). In the diag's boot the CDSP firmware reported its
`sleep_stats` fatal error once, a few minutes after boot, and remoteproc recovered it, as on v23.2 (revisions 1 and
2 never woke it far enough). The ADSP's `Handover signaled, but it already happened` errors (274 in that boot)
appear on every kernel since the sensors stack, v23.2 included (137 to 350 per diag run). Confirmed by the owner
afterwards: GPU acceleration (an Adreno GPU in Settings), the brightness slider, auto-rotation, automatic screen
brightness (the first confirmation on any kernel), Wi-Fi, touchscreen, multi-touch and pen, speakers and microphone,
battery status, Flatpak, the Windows entry in GRUB, the Slim Pen 2 connecting without pairing, tablet mode, suspend
and resume. GNOME's Power Mode reaches the Surface: Power Saver, Balanced and Performance switch tuned (`tuned-ppd`)
to `powersave`, `balanced` and `throughput-performance` and the platform profile to `low-power`, `balanced` and
`performance`. On a second boot `/dev/fastrpc-cdsp` was present and both DSPs answered the ping. USB-C charging and
data confirmed as well (an external display over USB-C not checked).

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
