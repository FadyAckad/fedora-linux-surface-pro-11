# Hardware-verified status
What has been confirmed on the tested unit, by date and package version: the packages installed, what was checked,
the result. "The kernel RPMs" are the package family `docs/kernel.md` describes; "the feature table" is
`README.md`'s; "by hand (owner)" is the owner's check of the feature table's rows in use.

## The standard checks

From 7.2.11 revision 1 on, every kernel round confirmed this set unless its entry says otherwise:

- the boot entry with the unit's device tree and the SP11 arguments, SELinux `Enforcing`;
- the speaker stage with VI+CPS feedback at every playback, the QSPI touch path;
- both DSPs over FastRPC (the CDSP again in a second boot), no provider waiting for `sync_state`; the crypto
  engine's node disabled and no `-qce` algorithm (up to 7.2.15: its two hashes);
- the three cameras listed and the front camera's light;
- the five sensors' readings and the proxy's orientation, light and compass;
- a deep sleep and resume; the bound devices and the kinds of kernel warning those of the previous revision.

Lines the rounds keep seeing without a known effect: the ADSP's `Handover signaled` lines while a sensor stream is
open; from 7.2.11, in boots with sleeps, `IRQ: set affinity failed`, a PHY's hwmon PM ordering warning and the
Surface hub's unhandled event; from 7.3.3 `Timeout waiting for L2 entry` from the Wi-Fi link at each suspend
(`docs/sleep.md`), the QRTR pair `failed to announce new service` and `failed while handling packet from 7:-2` at a
resume, and the audio probe's `CMD timeout for [1001021]`.

## Earlier rounds (2026-09-13 to 2026-11-06)

One entry per round; the facts each established live in the topic notes.

- 2026-09-13/14: Fedora 44 GA Workstation, support 1.7, `sp11-iptsd` 3.1.0-2.sp11: boot, install, display with GPU
  acceleration, Wi-Fi, Bluetooth, touch, pen, audio, battery, Flatpak, the Windows entry in GRUB, the shared
  pairings, `sp11-diag`; suspend and resume on 2026-09-17.
- 2026-09-16: Fedora 45 Beta 1.3 Workstation on a LUKS root, support 2.0 and 2.1: the media installs;
  `dnf upgrade --refresh` adds no stock kernel once `kernel-uki-*` is excluded (1.8).
- 2026-09-17 and 18: `kernel-sp11` 7.2.5 v23, then v23.1 with Fedora's LSM stack and support 2.5: speakers,
  microphone, keyboard, touchpad, brightness, multi-touch (owner); SELinux enforcing after the restore of
  2026-09-19.
- 2026-09-19 to 22: the sensors stack (sp11-sensors 1.9, then 1.10) and `kernel-sp11` v23.2 (the POS switch): all
  five sensors, `monitor-sensor`, GNOME's auto-rotation; a fresh install from the ISO of 2026-09-22 with the stack
  active from the first boot (owner).
- 2026-09-23: Fedora's kernel `7.2.5-300.sp11.1` with support 3.0: the ADSP on Linux's firmware, the microphone at
  about -22 dBFS, a deep suspend; the CDSP never wakes from its first sleep. Revision 2 (CDSP boot order) with
  support 3.1: no change.
- 2026-09-24: revision 3 (the video clock controller and the crypto engine): all 20 providers synced, the CDSP
  answers after idle and after a suspend (`docs/kernel.md`, Sync state); its AES self-tests fail, so revision 4
  keeps the hashes. A fresh install from the revision-4 ISO (support 3.2, sp11-sensors 1.10): the feature table of
  the time (owner), automatic brightness, tablet mode, the power modes and USB-C for the first time.
- 2026-09-25: revision 5 (7.2.7): both speakers with `VI+CPS feedback accepted` at every playback, the touch
  controller in QSPI mode, a deep suspend (owner).
- 2026-09-26 to 28: revisions 6 to 9 (7.2.7) with support 3.3, the cameras: front and rear camera in GNOME Snapshot
  and Firefox, also after a suspend (owner); the front camera's light; revision 8's frame length and revision 9's
  pixel rate as designed (`docs/camera.md`).
- 2026-09-29: support 3.4: `sp11-diag` counts 48 media nodes and no longer passes `/dev/media` to `media-ctl`.
- 2026-09-30 and 10-01: the KDE Plasma Desktop ISO (revision 9, support 3.4, sp11-sensors 1.10) installed from its
  second build: the whole feature table under Plasma (owner). The first build's installer drew corrupted in
  slitherer; the viewer is Firefox since.
- 2026-10-02 to 05: revision 10 (7.2.8) with Fedora's libcamera on KDE: an 8.5-hour deep sleep, the three cameras on
  `uncalibrated.yaml`, the whole feature table (owner); auto-rotation sometimes stopped after a wake (libssc).
- 2026-10-07: libssc 0.4.4-3: twenty claim-and-release cycles without CPU time, 52 minutes with 1 s of CPU after a
  reboot and a sleep (owner).
- 2026-10-08: iio-sensor-proxy 3.9-3.sp11.2 with sp11-sensors 1.11: 20 sleeps in one boot without an ADSP signal;
  1.12 the same evening: 15 quick wakes with the daemon running. Revision 11 (7.2.9) on KDE: the full check set,
  both PS8830 retimers bound, the whole feature table (owner).
- 2026-10-19: a fresh install from the 45 Beta 1.3 media with `7.2.11-300.sp11.1` (the restarted count), support
  3.4, iptsd 3.1.0-3, hexagonrpc 0.5.0-8, libssc 0.4.4-3, iio-sensor-proxy 3.9-3.sp11.2, sp11-sensors 1.12 and
  Fedora's libcamera: the standard checks, four deep sleeps, the whole feature table with the speakers' level and
  balance (owner).
- 2026-10-22: 7.2.11 revision 2 (the battery-driver fixes): the battery's `capacity`, UPower's `on-battery` at once
  on unplugging a USB-C charger; every row (owner). Not covered: the Surface charger and a full battery.
- 2026-10-23: revision 3 (the 5G device tree) with support 3.5 and 3.6: the modem on PCIe 5, `wwan0qmi0` ignored by
  ModemManager, GPS through GeoClue near a window, deep sleeps without a refused suspend; with 3.6 the feed paused
  and resumed across a sleep (`docs/gnss.md`).
- 2026-10-23 and 24: sp11-sensors 1.13 to 1.15 and support 3.7: GeoClue's locations with a heading, no denial for
  GeoClue (1.13) or the proxy (1.15, `docs/sensors.md`); every row of the Workstation column (owner).
- 2026-10-27 and 28: revisions 4 and 5 (deep sleep): the PCIe devices in D3hot and `ddr` counting in a sleep;
  revision 4's night at 1.40 W after a refused suspend, revision 5's 8 hours at 0.33 W (`docs/sleep.md`); every row
  (owner).
- 2026-10-28 and 29: revisions 6 and 7 (GPU fixes, the video codec) with support 3.8: no GPU hang after a sleep;
  hardware decoding of VP9, H.264 and H.265 (`docs/hardware.md`, Video codec); by hand (owner). Revision 6's clock
  `sync_state` series left a provider waiting and was dropped (`docs/kernel-patches.md`).
- 2026-10-29: revision 8 (the modem's MBIM data channels): mobile data over `wwan0`, IPv4 and IPv6, back 52 s after
  a wake; every row (owner).
- 2026-10-31 and 11-01: revisions 9 to 13 (the modem powered through a sleep, Wi-Fi's country across it) with a
  drop-in for ModemManager's quick resume: mobile data back 2 s after a wake, a night at 0.32 W; with revision 13
  the country set before the first scan after a wake and Wi-Fi online after 13 s (`docs/hardware.md`, Wi-Fi).
  Support 3.9 packaged the drop-in (2026-11-01).
- 2026-11-02: 7.2.14 revision 1 (the rebase), then revision 2 with `sp11-iptsd` 3.1.0-4 (the wake): the panel on
  0.05 s after the suspend exit instead of 1.3 s, the kernel's resume 1.4 s instead of 2.6 s (`docs/sleep.md`,
  Wake); the night of 11-03 at 0.32 W; by hand (owner).
- 2026-11-03: 7.2.15 revision 1 (the reversed USB-C plug): a USB 3 stick at 5000 Mb/s either way round on both
  ports. A fresh install from the Fedora 45 release media 1.4 with it, support 3.9, iptsd 3.1.0-4 and sp11-sensors
  1.15: the standard checks, the pairings, the live session and the feature table's rows but Flatpak, the Windows
  entry and USB-C (owner); `cam` needs `libcamera-tools`.
- 2026-11-06: 7.2.15 revision 2 (the QRTR probe deadlock): fourteen boots in a row through the initqueue in at most
  7.1 s, where three of twenty had sat 212 s; the standard checks.

## Kernel 7.3.3 revision 1: the first 7.3 kernel (2026-11-08)

- Installed: the kernel RPMs `7.3.3-300.sp11.1.fc45` (the rebase onto 7.3, the crypto engine's node disabled) next
  to 7.2.15 revision 2.
- Confirmed: the standard checks; the microphone at its normal pitch; Wi-Fi and mobile data after a wake; mobile
  data and GNSS fixes in GNOME Maps (owner).
- Found: a suspend started with the cover open ended after 2 s, woken by the cover switch; new in the kernel log:
  `Timeout waiting for L2 entry`, one SoundWire `bus clsh detected`, the QRTR `failed to announce new service`
  lines.

## Kernel 7.3.3 revision 2: the cover switch's wake path (2026-11-09)

- Installed: `7.3.3-300.sp11.2.fc45` (0089, the GPIO wake interrupts kept off the PDC).
- Confirmed: a suspend with the cover open held 68 s and the power key woke it, one with the cover closed 78 s;
  Wi-Fi and mobile data after both; the speakers' feedback, the QSPI touch path, the CDSP; a night of 8 h at 0.25 W,
  the memory asleep 27112 of 28883 s, no wake. By hand (owner): the rows in use, a USB 3 stick both ways round.
- Found: opening the cover no longer woke the tablet; the power key did (`docs/sleep.md`).

## Support RPM 3.10: the GRUB console font (2026-11-10)

- Installed: 3.10 over 3.9 under 7.3.3 revision 2; two files changed: the font, and `sp11-bt-set-addr` as the Fedora
  45 host compiles it (`docs/pipeline.md`, Versions and content pins).
- Confirmed: the package's font in `/boot/grub2/fonts`, named by `loadfont`; the Bluetooth address set as before. By
  hand (owner): every underscore and letter complete at size 32 in the menu and its editor.

## Kernel 7.3.3 revision 3 and libdisplay-info 0.3.0-2.sp11.1: HDR (2026-11-12)

- Installed: `7.3.3-300.sp11.3.fc45` (0090–0111, the DisplayPort HDR series) and `libdisplay-info`
  `0.3.0-2.sp11.1.fc45` over Fedora's, under mutter 51.1.
- Confirmed: `max bpc`, `Colorspace` and `HDR_OUTPUT_METADATA` on eDP-1, DP-1 and DP-2, mutter listing `bt2100`; HDR
  on (`BT2020_RGB`, the PQ metadata, a 30-bit plane, four 8.1 Gbit/s lanes); nine switches between SDR and HDR,
  seven suspends with HDR on, no DisplayPort, DPU or panel error in five boots (`docs/display.md`). The standard
  checks, eight deep suspends, 8 hours asleep with HDR on at 0.31 W. By hand (owner): the rows in use, the cameras,
  and in HDR the brightness keys, colours, a screenshot and Night Light; no external display.
- Found: a rotation switches HDR off (mutter 51.1); one suspend of ten refused by the Surface Aggregator's hub and
  slept in `s2idle` (`docs/sleep.md`); a GPU hang at login in one of five boots, recovered
  (`docs/display.md`, Known issues).

## Kernel 7.3.3 revision 4: no mode set for a gamma table (2026-11-13)

- Installed: `7.3.3-300.sp11.4.fc45` (0112–0114, the DSPPs reserved with every mode set).
- Recorded over three boots, 50 samples a second from before gdm's start: revision 3 with HDR off two mode sets
  before the login screen settled; revision 4 none with HDR off, one at a login into HDR (`docs/display.md`).
- Confirmed: mutter's gamma table an identity ramp, no CTM; a blanked lock screen, three suspends and an HDR switch
  with the picture back; the standard checks but for `sync_state` in one boot (below); 8.9 hours asleep with HDR on
  at 0.28 W, one wake 35 minutes in without a key press (`docs/sleep.md`). By hand (owner): Night Light, no flashing
  picture at boot or logout.
- Found: one boot without the modem, its PCIe link not up at the probe, and five providers waiting for `sync_state`
  (`docs/modem.md`, The link at boot); after an HDR session the login screen at the backlight's maximum, and the GPU
  hang at login once more (`docs/display.md`, Known issues).

## Support RPM 3.11: the speakers' clock votes (2026-11-15)

- Installed: 3.11 over 3.10 under 7.3.3 revision 4 (`78-sp11-speakers.rules`, `sp11-diag`).
- Confirmed: the LPASS pin controller `on` and `active`, both amplifiers `Attached`; six boots (63 playbacks, 80
  device opens, four sleeps) without the bus clash, parity or PA fault lines; a night of 11.8 hours at 0.26 W
  (`docs/hardware.md`, Audio). By hand (owner): each speaker's test tone; no silence in two days of use.

## The modem's link at boot: a check kit (2026-11-14 to 16)

- No package: a service that probes PCIe 5's controller again in a boot without the modem, under 7.3.3 revision 4.
- With the probe at the service's start the modem came up in one of three such boots; with the probe once TLMM 151
  reads low, in 25 boots the link was up at the first probe in 23 and at the service's probe in the other two
  (`docs/modem.md`, The link at boot).

## Kernel 7.3.3 revision 5: the modem's controller probed again (2026-11-16)

- Installed: `7.3.3-300.sp11.5.fc45` (0115 and 0116: PCIe 5 probed again once the modem asserts WAKE#), the check
  kit removed.
- Confirmed: the standard checks; the link at the first probe, TLMM 151 an input with a pull-up; Wi-Fi and mobile
  data around a deep sleep. By hand (owner): the round's checks.
- To 2026-11-19: the link at the first probe in 23 of 24 boots; in the 24th the second probe brought the modem up
  8.1 s after the kernel's start. No new kind of error.

## Kernel 7.3.5 revision 1: the rebase onto 7.3.5 (2026-11-19)

- Installed: `7.3.5-300.sp11.1.fc45` (the rebase, the audio patch on 7.3.4's fixes) under support 3.11.
- Confirmed: the standard checks but for the front camera's light and the crypto node (both device trees revision
  5's byte for byte); the three PCIe links at the first probe; `/dev/fastrpc-adsp` and `/dev/fastrpc-cdsp`; no
  buffer unmap refused by the audio DSP, a microphone recording; a deep sleep entered by closing the cover ended on
  opening it (`gpio_keys`); no new kind of kernel warning or journal error. By hand (owner): the round's checks.

## Secure Boot: support 3.12 to 3.16 and the signed boot image (2026-11-21 and 22)

- Installed: support 3.12 and `sp11-kernel-secureboot-7.3.5-300.sp11.1.fc45.aarch64` 1-1 under 7.3.5 revision 1, the
  owner's key enrolled in shim's list the day before; 3.13 to 3.16 by `dnf upgrade`.
- Confirmed with 3.12 and Secure Boot on (`Microsoft & 3rd party CA`): two starts through the signed entry
  (`ACTIVE`, lockdown `integrity`); a deep sleep; mobile data; no module refused, lockdown lines for hibernation
  only. Not part of the round: the standard checks.
- The menu (owner): with 3.12 in GRUB's small built-in font, its frame question marks; with 3.13 a drawn frame, the
  text small; with 3.14 the graphical menu at 2880x1920, Windows started from it, a black box in its middle while
  Windows started; with 3.15 as QEMU draws it, Escape leading to the text menu; with 3.16 Fedora and Windows from
  the menu, every restart through the signed entry (`ACTIVE`).

## Kernel 7.3.5 revision 2: the TPM (2026-11-22)

- Installed: `7.3.5-300.sp11.2.fc45` (0115 and 0116, the TPM driver built in) with its signed image, under support
  3.16 with Secure Boot on.
- Confirmed: the standard checks but for the front camera's light and the crypto node; the bound devices revision
  1's plus `tpm_qcom_mssecapp`. The TPM: `/dev/tpm0` and `/dev/tpmrm0`, `has-tpm2` `yes`, PCR 0 as in Windows' logs
  (also after a sleep and a restart), the event log's replay to PCRs 0, 7 and 9, the four persistent keys Windows
  keeps; Windows afterwards with Windows Hello, the TPM ready, lockout counter 0 (`docs/hardware.md`, TPM). By hand
  (owner): the round's checks.
- Found: the kernel's start 3.0 s slower; one SELinux denial of `systemd-tpm2-setup`; the TPM refuses every command
  after `TPM2_Shutdown` until a restart.

## Kernel 7.3.5 revision 3 and support 3.17: the TPM's registration, the denial (2026-11-23)

- Installed: support 3.17 over 3.16, then `7.3.5-300.sp11.3.fc45` (0117) with its signed image, Secure Boot on.
- Confirmed: the standard checks but for the front camera's light and the crypto node; the TPM as with revision 2;
  init at 0.63 s (revision 2: 3.72 s), `tpm2.target` at 4.28 s; `systemd-tpm2-setup-early.service` skipped, no
  denial. By hand (owner): the round's checks.
- Found: the hardware still comes up about 3 s late (`docs/hardware.md`, TPM).

## The live media on 7.3.5 revision 3: no USB disk without the ADSP (2026-11-23)

- Media: the 45 1.4 image with 7.3.5 revision 3 and the ADSP blacklisted live: the live initramfs waited for its
  stick until the emergency shell.
- On the installed system: started with `module_blacklist=qcom_q6v5_pas`, the stick enumerated on neither port,
  either way round (`docs/hardware.md`, USB-C data). With the cover detached the KIP hub's HID devices stayed
  registered, and an initramfs built then carried `surface_aggregator_hub` (`docs/tablet-mode.md`).

## Fresh installation with an encrypted root, support 3.18 (2026-11-23)

- Media: the 45 1.4 image with 7.3.5 revision 3 and support 3.18, whose live initramfs starts the ADSP: the stick at
  5000 Mb/s, the live root mounted, no DSP crash (`docs/hardware.md`, The DSP on the live media).
- Installed: partitioned by hand beside Windows (Fedora's own 2 GB EFI partition, `/boot` ext4, `/` btrfs in LUKS2),
  then libdisplay-info, the pairings and the signed image.
- Confirmed: the passphrase typed on the Type Cover; `crypttab` and the boot entries, the signed ones too, carry the
  volume; the enrolled key outlived the reinstall (`ACTIVE`); `Enforcing` without a denial, the sensors online. By
  hand (owner): the live session's sound and battery level, the round's checks.

## The TPM opens the encrypted root, support 3.19 (2026-11-23)

- Installed: 3.19 over 3.18, Secure Boot on; a GRUB password; a key sealed against PCR 7 in key slot 1,
  `tpm2-device=auto` in `crypttab`, the initramfs rebuilt (`docs/hardware.md`, TPM).
- Confirmed: the next start opened the root without a prompt, 1.3 s after `systemd-cryptsetup` started; the SP11
  Windows entry `--unrestricted`, os-prober's Windows entry in `grub.cfg` without it. By hand (owner): GRUB's editor
  asked for the password, Windows started without it.

## One Windows entry, support 3.20 (2026-11-23)

- Installed: 3.20 over 3.19, Secure Boot on; os-prober 1.81-13.
- Confirmed: `GRUB_DISABLE_OS_PROBER=true`; the SP11 Windows entry alone in `grub.cfg` and the Secure Boot menu. By
  hand (owner): Windows once in Fedora's menu with Secure Boot off; with it on, Escape asked for the GRUB password,
  then showed the text menu.

## A poweroff after a sleep, support 3.21 and 3.22 (2026-11-23 and 24)

- Found: after a sleep 30 s into a start the TPM refused systemd-pcrextend's TPM2_Startup (0x101), and
  `FailureAction=reboot-force` turned the poweroff into a restart; with `shutdown`'s failure overridden, the `final`
  measurement did the same.
- Installed: 3.21 over 3.20, then 3.22; Secure Boot on.
- Confirmed: both drop-ins in effect; after a 31 s deep sleep the TPM answered as before it and the poweroff went
  through. By hand (owner): poweroffs stayed off.

## Kernel 7.3.5 revision 4: the LCD model's patches on the tested unit (2026-11-24)

- Installed: `7.3.5-300.sp11.4.fc45` (0118 to 0121) with its signed image, under support 3.22 with Secure Boot on.
- Confirmed: the standard checks but for the crypto node; the bound devices revision 3's (458), no new kind of
  kernel warning; the root opened by the TPM under the new image, 1.35 s after `systemd-cryptsetup` started; the
  three cpufreq policies and no line of 0120. By hand (owner): the round's checks.
- Seen: a start with the ADSP up early (4.84 s), the CDSP's IPCRTR open failing (`-121`) at 10.2 s and the touch
  controller at 12.8 s, as in such starts of revisions 2 and 3.

## A firmware update through Windows (2026-11-25)

- Changed: the Surface's firmware, through Windows, which had listed the update as installed since the end of
  October while the old version kept running (status 0xC0000058).
- Confirmed with 7.3.5 revision 4 and support 3.22: the signed entry (`ACTIVE`), the root opened by the TPM,
  `Enforcing`, no provider waiting for `sync_state`, the bound devices (458), the five sensors, a deep sleep; shim's
  loader stops as before (`docs/secure-boot.md`, shim's loader). By hand (owner): no passphrase prompt, mobile data,
  the lid woke the Surface.

## The GNSS feed in its own SELinux domain, support 3.23 (2026-11-27 and 28)

- Installed: a first build of 3.23 over 3.22, `dnf downgrade` to 3.22, a second build over it, and on 2026-11-28 a
  third (a comment corrected) by `dnf reinstall`; `Enforcing`.
- First build: `sendto` on systemd's notify socket (`kernel_t`) denied, so each start timed out; after the downgrade
  the feed's file read `unlabeled_t`.
- Second build: the feed relabelled (`sp11_gnss_exec_t`) and `active` in `sp11_gnss_t` with fixes for GNOME Maps
  near a window, no denial; paused across a deep sleep, stopped when Maps closed. Third build: the label and the
  socket unchanged, no denial.

## Pen daemon 3.1.0-5: the pen in libwacom (2026-11-28)

- Installed: `sp11-iptsd` 3.1.0-5 over 3.1.0-4 (the libwacom udev rule and tablet file).
- Confirmed: `libwacom-list-local-devices` names the stylus "Microsoft Surface Pro 11", bus `serial`, also after a
  wake, where 3.1.0-4 had "not supported by libwacom"; libinput's `Left-handed` `n/a`. By hand (owner): the tablet
  and the General Pen in GNOME's Graphics Tablets panel, the pen as before, after a wake too.
