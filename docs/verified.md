# Hardware-verified status
What has been confirmed on the tested unit, by date and package version: the packages installed, what was checked,
the result. "The kernel RPMs" are the package family `docs/kernel.md` describes; "the feature table" is
`README.md`'s; "by hand (owner)" is the owner's check of the feature table's rows in use.

## The standard checks

From 7.2.11 revision 1 on, every kernel round confirmed this set unless its entry says otherwise:

- the boot entry with the unit's device tree and the SP11 arguments, SELinux `Enforcing`;
- the speaker stage with VI+CPS feedback at every playback, the QSPI touch path;
- both DSPs over FastRPC (the CDSP again in a second boot), the crypto engine's two hashes (idle as `suspended`
  from revision 4), no provider waiting for `sync_state`;
- the three cameras listed and the front camera's light;
- the five sensors' readings and the proxy's orientation, light and compass;
- a deep sleep and resume; the bound devices and the kinds of kernel warning those of the previous revision.

## Earlier rounds (2026-09-13 to 2026-10-08)

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
  active from the first boot, SELinux enforcing and package file times (owner).
- 2026-09-23: Fedora's kernel `7.2.5-300.sp11.1` with support 3.0: the saved default, the ADSP on Linux's firmware,
  the microphone at about -22 dBFS with 3.0's gain, a deep suspend, the owner's checks; the CDSP never wakes from
  its first sleep. Revision 2 (CDSP boot order) with support 3.1: no change, so the order is not the cause.
- 2026-09-24: revision 3 (the video clock controller and the crypto engine): all 20 providers synced, the CDSP
  answers after idle and after a suspend (`docs/kernel.md`, Sync state); its AES self-tests fail, so revision 4
  keeps the hashes. A fresh install from the revision-4 ISO (support 3.2, sp11-sensors 1.10): every row of the
  feature table of the time (owner), with automatic brightness, tablet mode, the power modes and USB-C for the
  first time; `aosd`, `cxsd` and `ddr` at 0 across a suspend.
- 2026-09-25: revision 5 (7.2.7): as revision 4, both speakers with `VI+CPS feedback accepted` at every playback
  (patch 0058), the touch controller in QSPI mode, a deep suspend and resume (owner).
- 2026-09-26 to 28: revisions 6 to 9 (7.2.7) with support 3.3, the cameras: the three sensors bound, front and
  rear camera in GNOME Snapshot and Firefox, also after a suspend (owner); revision 7's front-camera light; the
  daylight probe shows the dark pictures came from the room; revision 8's frame length and revision 9's pixel rate
  measured as designed (`docs/camera.md`); CCI queue timeouts on the rear camera's bus recovered by the OV13858
  retry.
- 2026-09-29: support 3.4: `sp11-diag` counts 48 media nodes and no longer passes `/dev/media` to `media-ctl`.
- 2026-09-30 and 10-01: the KDE Plasma Desktop ISO (revision 9, support 3.4, sp11-sensors 1.10; sha256
  `f84b60ba…`) installed from its second build: the whole feature table under Plasma (owner). The first build's
  installer drew corrupted in slitherer; the viewer is Firefox since.
- 2026-10-02 to 05: revision 10 (7.2.8) with Fedora's libcamera on KDE: as revision 9, an 8.5-hour deep sleep, the
  three cameras on `uncalibrated.yaml`, the whole feature table (owner). Auto-rotation sometimes stopped after a
  wake: libssc, fixed on 2026-10-07.
- 2026-10-07: libssc 0.4.4-3: twenty claim-and-release cycles without CPU time, 52 minutes with 1 s of CPU after a
  reboot and a sleep (owner).
- 2026-10-08: iio-sensor-proxy 3.9-3.sp11.2 with sp11-sensors 1.11: 20 sleeps in one boot without an ADSP signal,
  up to 1.9 h, the proxy stopping in under 0.1 s at five reboots; 1.12 the same evening: 15 quick wakes with the
  daemon running (counters 1 and 15); KDE's power button on Lock screen keeps the tablet awake after a power-key
  wake. Revision 11 (7.2.9) on KDE: the full check set, both PS8830 retimers bound, the whole feature table
  (owner).

## Fresh installation from the 7.2.11 revision 1 ISO (2026-10-19)

- Installed: a fresh install from `Fedora-Workstation-Live-45_Beta-1.3` remastered with kernel `7.2.11-300.sp11.1`
  (the first revision of the restarted count), support 3.4, iptsd 3.1.0-3, hexagonrpc 0.5.0-8, libssc 0.4.4-3,
  iio-sensor-proxy 3.9-3.sp11.2, sp11-sensors 1.12 and Fedora's libcamera `0.7.2-3.fc45` (sha256 `1c11373e…`); the
  media check passed and the installer opened in Firefox (owner).
- Confirmed: the standard checks, with both WSA digital volumes at 81 (-3 dB), which 7.2.11 applies at playback
  start, and both UCSI connectors and PS8830 retimers; four deep sleeps, each resumed, without an ADSP or CDSP
  crash; the same bound devices as revision 11; the whole feature table under GNOME, the speakers' level and
  balance included (owner).
- Found: only the warnings boots with sleeps showed in revisions 5 to 10 (`IRQ: set affinity failed`, a PHY's
  hwmon PM ordering warning, the Surface hub's unhandled event); the ADSP's known `Handover signaled` lines while
  `sp11-diag` reads the sensors.

## Kernel 7.2.11 revision 2 (2026-10-22)

- Installed: the kernel RPMs `7.2.11-300.sp11.2.fc45` (the battery-driver fixes 0075 to 0077) with `dnf install`
  next to revision 1, on the Workstation installation of 2026-10-19.
- Confirmed: the standard checks, a 36-minute deep sleep among them; the battery's `capacity` present and UPower's
  percentage taken from it; with a USB-C charger, unplugging and plugging in each sent a uevent for
  `qcom-battmgr-usb`, and UPower's `on-battery` followed at once. On revision 1 the same day, with the Surface
  charger: no uevent for `qcom-battmgr-ac`, `on-battery: no` after unplugging until the next resume, and
  `status=Not charging` at 100 % on the charger (`docs/hardware.md`).
- Confirmed by hand (owner, 2026-10-22 and 23): every row of the feature table, GNOME's battery icon on battery
  and charging after unplugging and plugging in, all of them again after the sleep. Not covered: the Surface
  charger and a full battery on revision 2.

## Kernel 7.2.11 revision 3, support 3.5 and 3.6: the 5G modem and GPS (2026-10-23)

- Installed: support 3.5 over 3.4, then the kernel RPMs `7.2.11-300.sp11.3.fc45` (the 5G SKU's device tree, 0078)
  with `dnf install` next to revision 2; support 3.6 over 3.5 the same day.
- Confirmed: `GRUB_DEVICETREE` the 5G tree, the new entry on `x1e80100-microsoft-denali-oled-5g.dtb` and revisions
  1 and 2 still on the OLED tree; the model `(OLED, 5G)`; the standard checks.
- Confirmed, the modem: `17cb:0308` on PCIe 5; ModemManager's modem at 27.7 s with `wwan0qmi0 (ignored)`;
  `sp11-gnss.socket` active, its socket labelled `sp11_gnss_var_run_t`; near a window GeoClue reported
  `GPS GGA+RMC` with 50 m, 50 of 59 locations in 120 s, the first after 71 s; deep sleeps without
  `failed to suspend device`; a reboot without ModemManager's 45 s stop. With 3.6, a deep sleep while an
  application asked for the location: the feed paused 28 ms after the sleep hook's signal and 0.25 s before the
  suspend, resumed 60 ms after the wake on the same connection (134 fixes after it); GeoClue's CPU time under a
  second.
- Found: away from windows no position in 120 s (one satellite with signal); with 3.5's sleep hook GeoClue did not
  reconnect to the feed after a sleep (fixed in 3.6); two SELinux denials of GeoClue's compass source at every
  GeoClue start (sp11-sensors 1.13).

## sp11-sensors 1.13 to 1.15 and support RPM 3.7: the compass and the denials (2026-10-23 and 24)

- Installed: `sp11-sensors-1.13-1` over 1.12, then a reboot; 1.14 and support 3.7 over 1.13 and 3.6; one boot with
  iio-sensor-proxy under `strace`, then the way back; 1.15 over 1.14 and a reboot.
- Confirmed with 1.13: 229 of 230 GeoClue locations in 60 s with a heading, which followed a quarter turn of the
  tablet; no denial for GeoClue; no CDSP crash. With 1.14 and 3.7: both diagnostics list the boot's denials; the
  strace boot traced the proxy's five to gvfs's GIO module (`docs/sensors.md`), with the sensors and rotation
  working under strace. With 1.15: no denial for the proxy, all three of its sensors found, GeoClue's locations
  with headings, GPS among them; rotation before and after a sleep (owner). GNOME Maps, behind GNOME's location
  prompt, shows the location with its heading (owner).
- Confirmed by hand (owner, 2026-10-24, with revision 3, support 3.7 and sp11-sensors 1.15): every row of the
  feature table's Workstation column.
- Found with 1.13: five denials for iio-sensor-proxy at every start (`/etc/passwd`, `dac_read_search`,
  `dac_override`) in all six boots checked, with 1.12 as well; the diagnostics had never shown a denial.

## Kernel 7.2.11 revisions 4 and 5: deep sleep (2026-10-27 and 28)

- Installed: the kernel RPMs `7.2.11-300.sp11.4.fc45` (the mainline changes 0079 to 0081) with `dnf install` next
  to revision 3, dnf removing revision 1; on 2026-10-28 `7.2.11-300.sp11.5.fc45` (the modem fix 0082), dnf
  removing revision 2.
- Confirmed with revision 4: the standard checks, the crypto engine idle as `suspended`; in a 10-minute sleep the
  six PCIe devices in D3hot and `ddr` counting 591 of 630 s; GPS after the modem's restart.
- Found with revision 4: a night at 1.40 W, in which the modem's driver refused a suspend 26 s after a wake and
  systemd fell back to `s2idle` (`docs/sleep.md`).
- Confirmed with revision 5: the standard checks; sleeps started within 15 s of a wake stayed deep, the modem
  powered down for them, GPS afterwards; 8 hours asleep at 0.33 W, `ddr` 94 % of the time. By hand (owner,
  2026-10-28): every row of the feature table.

## Kernel 7.2.11 revisions 6 and 7: GPU fixes, video codec (2026-10-28 and 29)

- Installed: on 2026-10-28 the kernel RPMs `7.2.11-300.sp11.6.fc45` (the Type-C switch-array fix, five Adreno
  fixes, the clock `sync_state` series and the video codec) with support 3.8 (the codec's firmware), next to
  revision 5, dnf removing revision 3; on 2026-10-29 `7.2.11-300.sp11.7.fc45` (revision 6 without the clock series)
  next to revision 5, revision 6 removed by the owner before.
- Confirmed with revision 6: the standard checks; no GPU hang, GMU or HFI line in the kernel log after a sleep;
  the codec's V4L2 devices. One boot without `clk_ignore_unused` and one without `pd_ignore_unused` too came up
  with a working screen; in a 10-minute sleep each, `cxsd` stayed at 0 and `ddr` counted 571 of 609 s and 560 of
  599 s.
- Found with revision 6: the clock series left the AOSS clock provider waiting for `sync_state` in the normal
  entry; without `clk_ignore_unused` the eDP pixel clock warned twice at the display's enable; a USB 3 stick
  plugged in reversed was still not found (`docs/hardware.md`, USB-C data).
- Confirmed with revision 7: the standard checks; no GPU hang, GMU or HFI line after a sleep; a 720p VP9 clip
  decoded in hardware frame for frame as libvpx decodes it, and 720p H.264 and H.265 clips once relabelled
  `bt601`, the H.264 frames matching Cisco's `openh264dec` (`docs/hardware.md`, Video codec); the USB 3 stick at
  5000 Mb/s plugged the usual way; the reversed plug's port state and the retimer test (`docs/hardware.md`, USB-C
  data). By hand (owner): the speakers, the microphone, touch and the pen, Wi-Fi, the keyboard cover's keys and
  touchpad, Bluetooth, rotation with the keyboard folded back, a sleep and wake.

## Kernel 7.2.11 revision 8: mobile data (2026-10-29)

- Installed: the kernel RPMs `7.2.11-300.sp11.8.fc45` (the modem's data channels for `mhi_wwan_mbim`, 0090) with
  support 3.8, `dnf install` next to revisions 5 and 7, dnf removing revision 4; a nano-SIM (o2 Germany) in the
  slot behind the SSD door.
- Confirmed: the standard checks; `wwan0` from `mhi_wwan_mbim`, ModemManager's ports `wwan0 (net), wwan0mbim0
  (mbim)`; over `wwan0` alone pings over IPv4 and IPv6 and 5 MB in 0.38 s; GPS's QRTR path; no SELinux denial.
  Before it, a module build of the same change on revision 7 had passed with pages in Firefox over mobile data
  (owner). By hand (owner): every row of the feature table.
- Measured after a 10-minute deep sleep (the mobile profile set to connect by itself): Wi-Fi online after 20.7 s,
  the modem answering after 36.0 s, registered after 50.5 s, mobile data online after 52.3 s; `ddr` 579 of 619 s,
  `cxsd` 0. With a test tree that keeps the modem powered through the sleep: the modem resumed without a restart,
  answering after 3.4 s, registered after 15.7 s, mobile data after 16.7 s; `ddr` 569 of 608 s, `cxsd` 0; the
  battery's reading changed by the same 0.511 Wh in both runs. Wi-Fi: country `DE` for the system and the chip,
  102 channels, none passive-only; a full scan took 8.5 s with the country known, the first scan after a wake 16 s
  (`docs/hardware.md`, Wi-Fi).

## Kernel 7.2.11 revision 9: the modem powered through a sleep, ModemManager's quick resume (2026-10-31)

- Installed: the kernel RPMs `7.2.11-300.sp11.9.fc45` (the 5G tree keeps the modem's supply through a sleep, 0091;
  ath12k re-sends the country when a radio starts, 0092) with support 3.8, `dnf install` next to revisions 7
  and 8, dnf removing revision 5; a drop-in on ModemManager's unit with `--test-quick-suspend-resume` (not in the
  support RPM).
- Confirmed: the standard checks; the 5G tree with `regulator-always-on` on the modem's supply and no slot supply
  on PCIe 5; mobile data over `wwan0` (5 MB in 1.8 s on 5G), GPS's QRTR path; no SELinux denial. By hand (owner):
  every row of the feature table.
- Measured after a 10-minute deep sleep: ModemManager synced the modem 1.4 s after the wake, mobile data online
  after 2.0 s (revision 8: 52.3 s), no modem restart and no port re-attach in the kernel log; `ddr` 560 of 599 s,
  `cxsd` 0. The night: 8 hours asleep at 0.32 W (27.035 to 24.485 Wh over 28885 s, `ddr` 27148 s, one sleep;
  revision 5 with the modem off: 0.33 W); in the morning mobile data online 2.0 s after the wake.
- Found: patch 0092 did not reach the first scan after the wake: the nl80211 events show the firmware starting
  in world roaming, the scan over its list (15 s) and `DE` set by the chip's own country scan 7 s in, as on
  revision 8; the night's wake scanned in 8.4 s and was online after 13.1 s. The driver's `regd_updated` gate and
  the interfaces added right after the start re-apply the rules last received, so the firmware's answer to the
  restored country is dropped unless it arrives first (`docs/hardware.md`, Wi-Fi); revision 10 waits for it.
- The Wi-Fi figures of the boot and of the 10-minute wake were taken on a phone hotspot that was not beaconing at
  the time (online after 190 s and 35 s) and say nothing about the kernel; the night's wake was on the home network.

## Kernel 7.2.11 revision 10: the country re-send with a wait (2026-10-31)

- Installed: the kernel RPMs `7.2.11-300.sp11.10.fc45` (revision 9 with 0092 waiting for a regulatory answer)
  with support 3.8 and the ModemManager drop-in, `dnf install` next to revisions 8 and 9, dnf removing
  revision 7.
- Confirmed: `Enforcing`, the DSPs, the modem connected; no SELinux denial. Mobile data online 1.8 s and 2.0 s
  after two wakes. On the home network (5180 MHz, 160 MHz): a boot online after 30.2 s (unchanged by design); the
  second wake with `DE` restored before the first scan, the scan 8.6 s, online after 13.6 s; `DE` and the 160 MHz
  link after both wakes.
- Found: the first wake still ran its scan over the world list (16.1 s, online after 20.6 s): the wait returned
  on the firmware's own first regulatory event, not on the answer to the command, so the world rules were applied
  and the answer dropped by the gate. Revision 11 waits for the answer that carries the country.

## Kernel 7.2.11 revision 11: the country re-send waiting for the matching answer (2026-11-01)

- Installed: the kernel RPMs `7.2.11-300.sp11.11.fc45` (revision 10 with 0092 waiting for the answer that carries
  the country) with support 3.8 and the ModemManager drop-in, `dnf install` next to revisions 9 and 10, dnf
  removing revision 8.
- Confirmed: `Enforcing`, the DSPs, the modem connected; no SELinux denial. Mobile data online 2.4 s and 1.8 s
  after two wakes on the home network; a boot online after 27.3 s; `DE` and the 160 MHz link after both wakes.
- Found: both wakes still scanned the world list (16 s, online after 20.3 s and 20.4 s), with the world rules
  applied twice at the start and `DE` only from the chip's own scan 7 s in, although the driver found the
  restored country in the firmware's answer within 500 ms (no timeout warning). Revision 10's one good wake had
  the radio restarted by the resume path, not by NetworkManager's link-up. Revision 12 logs the sequence.

## Kernel 7.2.11 revision 12: the country re-send with diagnostics (2026-11-01)

- Installed: the kernel RPMs `7.2.11-300.sp11.12.fc45` (revision 11 with the regulatory path logged, a changed
  country let through the gate, a re-send on world roaming) with support 3.8 and the ModemManager drop-in,
  `dnf install` next to revisions 10 and 11, dnf removing revision 9.
- Confirmed: `Enforcing`, the DSPs, the modem connected; no SELinux denial. Mobile data online 2.1 s and 1.1 s
  after two wakes; a boot online after 26.3 s; `DE` and the 160 MHz link after both wakes. At the second wake the
  restore worked end to end: the country sent as the radio started, answered after 3 ms, applied before the
  interfaces were created, the scan 8.5 s, Wi-Fi online after 12.4 s.
- Found: at a sleep, NetworkManager's disconnection starts a scan that the link's end aborts, the chip's 11d
  scan stops and reports no country (`00`), and the driver takes that over as the known country and sends it to
  the firmware, which is the `set to world roaming` of every sleep. At the next wake there is nothing to restore
  (the first wake: no restore, the world list, online after 21.0 s). The second sleep had no scan to abort (it
  fell back to `s2idle`), so the country survived to the second wake. Revision 13 keeps a known country when the
  11d scan reports none.

## Kernel 7.2.11 revision 13: the country kept across a sleep (2026-11-01)

- Installed: the kernel RPMs `7.2.11-300.sp11.13.fc45` (0091 and the final 0092: a known country kept when the
  11d scan reports none, restored as the radio starts) with support 3.8 and the ModemManager drop-in,
  `dnf install` next to revisions 11 and 12, dnf removing revision 10.
- Confirmed: `Enforcing`, the DSPs, the modem connected; no SELinux denial. On the home network (5180 MHz,
  160 MHz): after two wakes `DE` applied within 1.4 s of the resume and before the first scan, the scan 8.5 and
  8.6 s, Wi-Fi online after 13.2 and 13.5 s (revision 8: 20.7 s), mobile data after 2.4 and 2.0 s (revision 8:
  52.3 s); a boot online after 27.7 s (unchanged); `DE` and the 160 MHz link after both wakes; at the sleeps the
  aborted scan no longer ends in world roaming; no regulatory warning in the kernel log.

## Kernel 7.2.14 revision 1: the rebase onto 7.2.14 (2026-11-02)

- Installed: the kernel RPMs `7.2.14-300.sp11.1.fc45` (7.2.11 revision 13's 92 patches unchanged on Fedora's
  `kernel-7.2.14-300.fc45`) with support 3.9, `dnf install` next to revisions 12 and 13 of 7.2.11, dnf removing
  revision 11; the 5G device tree in the boot entry, `saved_entry` on the new kernel.
- Confirmed: the standard checks (the modem `registered`, the light and accelerometer readings, orientation,
  light and compass through the proxy; a 78 s deep sleep); the USB-C retimers and the UCSI supplies as with
  revision 13; Wi-Fi up in both boots, the second a reboot, with the link up, the chip named and no error line
  (the 7.2.13 reset at the sequencer's probe); the journal's errors those of 7.2.11 revision 1 (the ADSP handover
  lines after the resume). One new kind of warning in the first boot: the touch controller's HID-SPI read at 10 s
  returned an invalid header (`ret=-71`), and the driver's cold recovery brought it up 1 s later; not in the 17
  earlier diagnostics, and no 7.2.12 to 7.2.14 change touches the SPI, GPI DMA or TLMM paths the touch uses.
  By hand (owner): the round's checks passed, touch and pen, USB-C, the cameras and the wake's checks included.

## Support RPM 3.9: ModemManager's quick resume packaged (2026-11-01)

- Installed: `sp11-surface-support-3.9-1.fc45` with `dnf upgrade` over 3.8 on kernel 7.2.11 revision 13; the kit's
  copy of the drop-in removed from `/etc`, so that the package's copy under `/usr/lib` is the one in force
  (`systemctl cat ModemManager.service` shows only that one).
- Confirmed: the modem `connected` again after the restart; after a wake ModemManager's sync 2.5 s and mobile
  data online 2.5 s after it, no probe, pings over `wwan0`; Wi-Fi online after 12.9 s.
