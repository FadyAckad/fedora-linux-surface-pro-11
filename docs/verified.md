# Hardware-verified status
What has been confirmed on the tested unit, by date and package version: the packages installed, what was checked,
the result. "The kernel RPMs" are the package family `docs/kernel.md` describes; "the feature table" is
`README.md`'s; "by hand (owner)" is the owner's check of the feature table's rows in use.

## The standard checks

From 7.2.11 revision 1 on, every kernel round confirmed this set unless its entry says otherwise:

- the boot entry with the unit's device tree and the SP11 arguments, SELinux `Enforcing`;
- the speaker stage with VI+CPS feedback at every playback, the QSPI touch path;
- both DSPs over FastRPC (the CDSP again in a second boot), no provider waiting for `sync_state`; up to 7.2.15 the
  crypto engine's two hashes (idle as `suspended` from revision 4), from 7.3.3 revision 1 its node disabled and
  no `-qce` algorithm;
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

## Kernel 7.2.15 revision 1: the reversed USB-C plug (2026-11-03)

- Installed: the kernel RPMs `7.2.15-300.sp11.1.fc45` (7.2.14 revision 2's 94 patches unchanged on Fedora's
  `kernel-7.2.15-300.fc45`, plus 0095, the PS8830 retimer told of the connection 30 ms before its mode) with
  support 3.9, `dnf install` next to revisions 1 and 2 of 7.2.14, dnf removing 7.2.11 revision 13; the 5G device
  tree in the boot entry, `saved_entry` on the new kernel.
- Confirmed: the USB 3 stick (SanDisk 3.2Gen1) at 5000 Mb/s in both ports turned over and the usual way (six
  checks: port A and B each way, port A turned over after a wake and in a second boot), where every earlier kernel
  found it only the usual way; the standard checks (the three PCIe links, the QSPI touch path, the touch
  controller and its HID bridge, the speakers' feedback lines, both DSPs answering, the crypto engine's hashes,
  the three cameras with the front camera's light); `no provider waits for sync_state`; the journal's errors only
  the ADSP handover lines. By hand (owner): the files on the stick, the wake's checks, the round's checks.

## Kernel 7.2.14 revision 2 and sp11-iptsd 3.1.0-4: the wake (2026-11-02)

- Installed: `sp11-iptsd-3.1.0-4.sp11` with `dnf upgrade` over 3.1.0-3 on 7.2.14 revision 1, then the kernel
  RPMs `7.2.14-300.sp11.2.fc45` (revision 1 plus 0093 and 0094) with `dnf install` next to 7.2.11 revision 13 and
  7.2.14 revision 1, dnf removing 7.2.11 revision 12; the 5G device tree in the boot entry, `saved_entry` on the
  new kernel.
- Confirmed: `Enforcing`, the modem `registered`, Wi-Fi connected, the QSPI touch path, both DSPs, no provider
  waiting for `sync_state`; the hook's `pre complete: stopped=1` and `post: nothing to do` lines at every sleep
  with one `Started sp11-iptsd@` per wake; the DRM connector on 0.05 to 0.07 s after `PM: suspend exit` on
  revision 1 and 2 with the new hook, against 1.27 to 1.33 s with the old one; twelve wakes on revision 2 with
  three `link up` lines each, the modem controller's L2 timeout at every suspend as before, no other new kernel
  line; NVMe `live`, Wi-Fi connected, the modem `registered` after them; the memory's low-power share 617 of
  675 s suspended (91 %, on battery). By hand (owner): touch and pen after every wake, Wi-Fi and mobile data,
  speakers, the Bluetooth keyboard and pen, the cameras, charging; later the same evening, with the profile set
  to connect automatically, mobile data back by itself at once after every wake. The journal's errors those of
  revision 1.
- From the follow-up of the same evening (the journal's JSON form of that boot and of a new revision 2 boot with
  one wake with mobile data on): the kernel from its first line to `PM: suspend exit` 1.31 to 1.42 s over the
  thirteen wakes (2.54 to 2.58 s on revision 1), the three links up within 0.39 s side by side, the resume phase
  0.21 to 0.28 s, the hooks 0.015 s (`docs/sleep.md`, Wake); mobile data connected and pinging after that wake
  once its profile was activated. Not measured: the firmware's share (the follow-up's tarball of the debugfs
  counters held empty files).
- Seen: with the charger connected the tablet woke by itself three times (wakes without a wake interrupt, between
  60 and 80 % of charge), and the memory's low-power share was 69 of 682 s while it charged at 38 W
  (`docs/sleep.md`, Wake).
- The night of 2026-11-03 on battery with mobile data on: 29027 s with one sleep, 0.32 W, `ddr` 27253 of 28957 s
  (94 %), the ADSP 10 a second, woken by the power key with nothing in between; mobile data and Wi-Fi connected
  and pinging at the wake. The same as revision 9's night of 2026-10-31.

## Fresh installation from the Fedora 45 release media 1.4 with 7.2.15 revision 1 (2026-11-03)

- Installed: a fresh install from `Fedora-Workstation-Live-45-1.4` (Fedora's 45 release, in place of the 45 Beta
  1.3) remastered with kernel `7.2.15-300.sp11.1`, support 3.9, iptsd 3.1.0-4, hexagonrpc 0.5.0-8, libssc
  0.4.4-3, iio-sensor-proxy 3.9-3.sp11.2 and sp11-sensors 1.15 (sha256 `41826984…`); the media check passed and
  the installer opened in Firefox (owner). After the first-boot service, the boot entry and the command line carry
  the 5G device tree and the four SP11 arguments.
- Confirmed: `Enforcing`; the speakers' feedback lines and the microphone; the QSPI touch path, the touch
  controller and its HID bridge; both DSPs answering, the CDSP again in a second boot; the five sensors' readings
  with the proxy's orientation, light and compass; the pairings imported from the tarball, the Flex Keyboard and
  the Slim Pen 2 connected; one deep sleep and resume; `no provider waits for sync_state`; the journal's errors only
  the ADSP handover lines. By hand (owner): the live session (display, touch, pen, keyboard and touchpad, Wi-Fi),
  the auto-rotate button, auto-rotation and automatic brightness, both cameras with the front camera's light in
  GNOME Snapshot, battery, brightness and volume keys, the power modes, GPS near a window, mobile data, the wake's
  checks.
- Found: one CDSP assert (`sleep_statsi.c:537`, recovered in 0.14 s) 15 minutes into the boot, the known open
  issue (`docs/sensors.md`, The CDSP asserts around stream changes); the touch controller's automatic recovery
  twice in that boot (`recoveries=2`); `cam` is not on a fresh Workstation installation (`libcamera-tools`).
- The ISO's second build (sha256 `dd3a8950…`), whose live entries boot without `quiet rhgb`, showed the boot
  messages on the console and gave the live session's expected output (owner, later the same day).

## Kernel 7.2.15 revision 2: the boot hang in dracut-initqueue (2026-11-06)

- Installed: the kernel RPMs `7.2.15-300.sp11.2.fc45` (revision 1's 95 patches plus 0096, the QRTR-over-glink
  driver's send lock released before a failed open's unregistration), `dnf install` next to revision 1; the 5G
  device tree in the boot entry, `saved_entry` on the new kernel.
- Confirmed: fourteen boots in a row ended the initqueue at 1.8 to 7.1 s with the root switched by 7.3 s, where
  three of the twenty boots before had sat 212 s (the CDSP's IPCRTR open still fails with `-121` at 6.6 s, now
  without consequence); after them a battery reading, Wi-Fi connected and the five sensors' readings; the standard
  checks (the speakers' feedback lines, the microphone, the QSPI touch path, both DSPs answering, the crypto
  engine's hashes, the three cameras listed); one deep sleep and resume; `no provider waits for sync_state`; the
  journal's errors only the ADSP handover lines. No line came back for the by-hand checks or the shutdown.

## Kernel 7.3.3 revision 1: the first 7.3 kernel (2026-11-08)

- Installed: the kernel RPMs `7.3.3-300.sp11.1.fc45` (Fedora's `kernel-7.3.3-300.fc45` with 88 patches: 7.2.15
  revision 2's 96 less nine that 7.3 carries, three adapted, plus 0088, the crypto engine's node disabled),
  `dnf install` next to 7.2.15 revision 2; the 5G device tree in the boot entry, `saved_entry` on the new kernel.
- Confirmed: the standard checks, with the crypto node `disabled` and no `-qce` algorithm in place of the engine's
  hashes; the microphone clear at its normal pitch; mobile data connected and GNSS fixes in GNOME Maps (owner);
  Wi-Fi and mobile data back after a wake; the CDSP answering in a second boot. New in the kernel log: a `Timeout
  waiting for L2 entry` from the Wi-Fi link at each suspend, one SoundWire `bus clsh detected` at a playback
  start, QRTR `failed to announce new service` lines at each resume.
- Found: a suspend started with the cover open ended after 2 s, woken by the cover switch's interrupt (twice from
  the Power menu); with the cover closed a suspend held 82 s and opening the cover woke it. Revision 2 below.

## Kernel 7.3.3 revision 2: the cover switch's wake path (2026-11-09)

- Installed: the kernel RPMs `7.3.3-300.sp11.2.fc45` (revision 1 plus 0089, the GPIO wake interrupts kept off the
  PDC), `dnf install` next to revision 1 (dnf removed 7.2.15 revision 1, the oldest of four kernels).
- Confirmed: a suspend from the Power menu with the cover open held 68 s and the power key woke it; a suspend with
  the cover closed held 78 s; Wi-Fi and mobile data connected after both; the speakers' feedback line, the QSPI
  touch path and the CDSP answering; the night: 8 h 1 min asleep at 0.25 W (35.95 to 33.93 Wh, 70 to 67 %), the
  memory in its low-power state 27112 of 28883 s, one suspend entry and exit, no wake in the night; mobile data
  connected after the morning wake, Wi-Fi still connecting 8 s after it (it takes about 13 s).
- By hand (owner): the feature table's rows in use passed on revisions 1 and 2 (Wi-Fi, the Bluetooth keyboard and
  pen, battery, brightness, volume keys, keyboard and touchpad, rotation, power modes, a USB 3 stick both ways
  round).
- Found: opening the cover no longer wakes the system; the power key does. Accepted for now (`docs/sleep.md`).

## Support RPM 3.10: the GRUB console font (2026-11-10)

- Installed: `sp11-surface-support` 3.10 by `dnf upgrade` over 3.9, under kernel `7.3.3-300.sp11.2.fc45`. Against
  the installed 3.9 the package changed two files: the font, and `sp11-bt-set-addr` as the Fedora 45 host compiles
  the same source (`docs/pipeline.md`, Versions and content pins).
- Confirmed: the font in `/boot/grub2/fonts` replaced by the package's and named by the menu's `loadfont` line;
  the Bluetooth address unit's journal lines the same before and after, ending in `Success: public address set`,
  and the controller carrying the configured address.
- By hand (owner): the menu and its editor show every underscore and the letters complete at size 32; the
  Bluetooth keyboard and pen connect.

## Kernel 7.3.3 revision 3 and libdisplay-info 0.3.0-2.sp11.1: HDR (2026-11-12)

- Installed: the kernel RPMs `7.3.3-300.sp11.3.fc45` (revision 2 plus 0090–0111, the DisplayPort HDR series),
  `dnf install` next to revision 2 (dnf removed 7.2.15 revision 2, the oldest of four kernels), and
  `libdisplay-info` `0.3.0-2.sp11.1.fc45` over Fedora's `0.3.0-2.fc45`, under mutter and gnome-shell 51.1.
- Confirmed, HDR: `max bpc`, `Colorspace` and `HDR_OUTPUT_METADATA` on eDP-1, DP-1 and DP-2, and mutter listing
  `bt2100`, where revision 2 with Fedora's library had neither; HDR on with `Colorspace = BT2020_RGB`, the PQ
  metadata blob and an XR30 plane at 30 bits per pixel on four 8.1 Gbit/s lanes; nine switches between SDR and
  HDR in all; seven suspends with HDR on, the session back in `bt2100`; no DisplayPort, DPU or panel error in the
  kernel log of five boots (`docs/display.md`).
- Confirmed: the standard checks (the proxy at orientation `normal`, 5 lux and a compass heading; the CDSP after
  three reboots); eight suspends from the Power menu, the lid and for the long sleep, all `deep`; 8 h 2 min
  asleep with HDR on at 0.31 W (35.82 to 33.33 Wh, 72 to 67 %), the memory in its low-power state 27167 of
  28951 s, one suspend entry and exit, no wake.
- By hand (owner): every by-hand check of the round passed: the feature table's rows in use, the cameras and the
  front camera's light, the microphone, the screen back after three lock-screen blankings, and in HDR the
  brightness keys and slider, colours, a screenshot and Night Light. An external display was not tried.
- Found: rotating the tablet switches HDR off, a mutter 51.1 defect fixed upstream for 51.2 (`docs/display.md`,
  Known issues). One suspend of ten, started 20 s after a wake, was refused by the Surface Aggregator's hub,
  whose display-off notice to the EC timed out (`ssam_serial_hub_pm_prepare` returns -110 after 9 s), and
  systemd slept in `s2idle` instead (`docs/sleep.md`). One of five boots logged a GPU hang at login that
  recovered by itself (the bandwidth vote's timeout, then `hangcheck recover`; `docs/display.md`, Known issues).
  The long sleep drew 0.31 W against revision 2's 0.25 W with the same share of memory sleep; one sleep each,
  the difference is not explained.

## Kernel 7.3.3 revision 4: no mode set for a gamma table (2026-11-13)

- Installed: the kernel RPMs `7.3.3-300.sp11.4.fc45` (revision 3 plus 0112–0114, the DSPPs reserved with every
  mode set), `dnf install` next to revisions 2 and 3 (dnf removed revision 1, the oldest of four kernels), under
  mutter and gnome-shell 51.1.
- Recorded: the display over three boots, 50 samples a second from before gdm's start (the panel's power state,
  the backlight, the CRTC's DSPPs). Revision 3 with HDR off: two mode sets before the login screen settled, the
  backlight off for 1047 and 1065 ms and the login screen's first picture for 0.18 s between them. Revision 4
  with HDR off: none, through the login. Revision 4 with HDR on: none at the login screen's start, one at the
  login (`docs/display.md`).
- Confirmed on revision 4: the DSPPs reserved from Plymouth's picture on; mutter's gamma table an identity ramp
  of 1024 entries, no CTM; a blanked lock screen, three suspends (`deep`) and an HDR switch, the picture back
  each time; the standard checks but for `sync_state` (below), with Wi-Fi and mobile data connected in the
  first boot.
- By hand (owner): every by-hand check of the round passed, Night Light among them; no flashing picture at boot
  or at logout.
- Found: in the second of revision 4's two boots the modem's PCIe link did not come up and its controller's
  probe failed, so that boot had no modem and five clock and interconnect providers kept waiting for
  `sync_state` (`docs/modem.md`, The link at boot). After an HDR session the login screen runs at the
  backlight's maximum (`docs/display.md`, Known issues).
- A third boot the same morning: the modem present, no provider waiting for `sync_state`; the GPU hang at
  login, recovered (`docs/display.md`, Known issues). Then 8.9 hours asleep on battery with HDR on: 0.28 W
  (27.36 to 24.88 Wh over 31978 s), `ddr` 29565 s, both suspends `deep`, one wake 35 minutes in without a
  key press and with the cover closed, Wi-Fi connected after the wake (`docs/sleep.md`).

## Support RPM 3.11: the speakers' clock votes (2026-11-15)

- Installed: `sp11-surface-support` 3.11 by `dnf upgrade` over 3.10, under kernel `7.3.3-300.sp11.4.fc45`. Against
  3.10 the package changed two files: the udev rule `78-sp11-speakers.rules` and `sp11-diag`.
- Confirmed: after a reboot the LPASS pin controller's `power/control` `on` and its run-time state `active`;
  `sp11-diag` listing both amplifiers `Attached` and the control `on`; in the six boots after it (63 playbacks,
  80 device opens, four sleeps) none of the bus clash, parity and PA fault lines; the night: 11.8 hours asleep
  at 0.26 W (40.20 to 37.19 Wh, 80 to 74 %), the memory in its low-power state 39777 of 42336 s, one suspend
  entry and exit, no wake (`docs/hardware.md`, Audio; `docs/sleep.md`).
- By hand (owner): the test tone on the left, the right and both speakers; the speakers not silent again in two
  days of use.

## The modem's link at boot: the check kit (2026-11-14 to 11-16)

- Installed: no package. A check kit under `/usr/local/sbin` with a service that starts only in a boot without
  the modem and probes PCIe 5's controller again, under kernel `7.3.3-300.sp11.4.fc45` and support 3.11.
- First kit (2026-11-14), the probe at the service's start: three boots without the link at the first probe.
  The modem came up in one (the second probe 9.8 s after the kernel's start, TLMM 151 low before it); in two
  the probe at 6.3 s, TLMM 151 high, bound the controller without the modem.
- Second kit (installed 2026-11-15), the probe once TLMM 151 reads low: 25 boots to 11-16, the link at the first
  probe in 23. In the other two (after a reboot; after 4.0 hours off) the service's first probe found the link:
  the modem on the bus at 10.2 and 8.0 s, ModemManager's modem at 33.7 and 31.5 s, all four WWAN ports. No boot
  without the modem; ten sleeps without a link failure (`docs/modem.md`, The link at boot).

## Kernel 7.3.3 revision 5: the modem's controller probed again (2026-11-16)

- Installed: the kernel RPMs `7.3.3-300.sp11.5.fc45` (revision 4 plus 0115 and 0116: the controller's driver
  probes PCIe 5 again once a modem that missed the link asserts WAKE#), `dnf install` next to revisions 3 and 4
  (dnf removed revision 2), under support 3.11. The check kit's service was removed first.
- Confirmed: the standard checks. PCIe 5's link up at the first probe, 1.72 s after the kernel's start; TLMM 151
  an input with a pull-up, reading high; Wi-Fi and mobile data connected before and after a 36 s deep sleep; no
  provider waiting for `sync_state`; the bound drivers those of revision 4; the CDSP answering in a second boot.
- To 2026-11-19: 24 boots of revision 5 (`sp11-modem-check history`), 23 with the link 0.20 s after the reset's
  release at the first probe. In the 24th (2026-11-19 15:52, after 2.1 hours off) the first probe failed with
  `Link failed to come up. LTSSM: PRE_DETECT_QUIET`; the driver logged `WAKE# asserted after 5198 ms` and
  `Probing again (1 of 3)`, the second probe found the link, the modem was on the bus 8.1 s after the kernel's
  start and ModemManager's modem there at 31.8 s. No boot without the modem, no link failure after a sleep.
- In the journal's errors, none new with the revision: the touch controller's invalid header at 10 s with the
  driver's cold recovery 1 s later (once before, 7.2.15 revision 1; `docs/hardware.md`, Pen); the CDSP's
  `sleep_stats` assert during the sensors check (`docs/sensors.md`, Known issues); a core dump of the mail
  client 26 s after the wake (once before, 7.3.3 revision 2).
- By hand (owner): the round's by-hand checks passed.

## Kernel 7.3.5 revision 1: the rebase onto 7.3.5 (2026-11-19)

- Installed: the kernel RPMs `7.3.5-300.sp11.1.fc45` (Fedora's `kernel-7.3.5-300.fc45`; 7.3.3 revision 5's 116
  patches less the two that 7.3.4 carries, the audio patch adapted to 7.3.4's fixes) with `dnf install` next to
  7.3.3 revisions 4 and 5 (dnf removed revision 3), under support 3.11.
- Confirmed: the standard checks, but for the front camera's light and the crypto node, which the round did not
  read (both device trees are byte for byte revision 5's). The three PCIe links up at the first probe in both
  boots: the modem's 1.77 and 1.78 s after the kernel's start, the SSD's 1.78 and 1.77 s, Wi-Fi's 5.0 and 4.8 s.
  `/dev/fastrpc-adsp` and `/dev/fastrpc-cdsp` present: the assignment of the ADSP's remote heap that 7.3.4's
  FastRPC makes at the channel's probe passes on this firmware. The audio DSP refused no buffer unmap; a
  recording from the microphone made and played. Wi-Fi and mobile data connected before and after the sleeps.
- The cover: a deep sleep entered by closing it ended 24 s later when it was opened; `pm_wakeup_irq` named
  interrupt 125, `gpio_keys`, and the journal has no power key press. The deep sleep before it, from the Power
  menu, was ended with the power key (`docs/sleep.md`).
- In the kernel's warnings and the journal's errors, none new against 7.3.3 revision 5; the bound devices and
  the loaded modules are revision 5's. Still logged: the QRTR pair `failed to announce new service` and `failed
  while handling packet from 7:-2` (once in the two wakes, with upstream's `743b5c86276b` in the kernel),
  `Timeout waiting for L2 entry` at both suspends, the audio probe's `CMD timeout for [1001021]`, the CDSP's
  `sleep_stats` assert during the sensors check.
- By hand (owner): the round's by-hand checks passed (both speakers, the microphone's recording, the cameras,
  touch and pen, the Bluetooth keyboard, the brightness keys, rotation, charging on USB-C).

## Secure Boot: support 3.12 and the signed boot image (2026-11-21)

- Installed: `sp11-surface-support` 3.12 over 3.11 and `sp11-kernel-secureboot-7.3.5-300.sp11.1.fc45.aarch64`
  1-1 in one `dnf install`, under kernel `7.3.5-300.sp11.1.fc45`; the test entry of the rounds of 2026-11-20
  removed first. The owner's key had been enrolled in shim's list on 2026-11-20.
- Confirmed with Secure Boot off: `sp11-secureboot status` `READY`; after `try`, one start through the signed
  entry (`TRIED`, stub `systemd-stub 262.1-sp11.1`), the request cleared.
- Confirmed with Secure Boot on (`Microsoft & 3rd party CA`): two starts through the signed entry without a choice
  in the menu (`ACTIVE`, lockdown `integrity`); a deep sleep of 68 s and its wake; mobile data connected 46 s
  after the start, IPv4 and IPv6; the unit's sync at the start and at the shutdown; `sp11-diag` without an
  SELinux denial. No module refused, lockdown lines for hibernation only, the journal's errors those of a boot
  with Secure Boot off. The menu stood in GRUB's small built-in font with a frame of question marks (owner).
- Not part of the round: the standard checks and the checks by hand (`docs/secure-boot.md`).
- Support 3.13 by `dnf upgrade` over 3.12 the same day, with Secure Boot on: the entries file carries the console
  rule, the next start came up by itself through the signed entry (`ACTIVE`), and the menu had a drawn frame in
  the firmware console's font, its text still small (owner).
- Support 3.14 by `dnf upgrade` over 3.13 on 2026-11-22: GRUB showed the graphical menu at 2880x1920 with the
  signed entry, Windows and the firmware settings; the restart came up by itself through the signed entry
  (`ACTIVE`); Windows started from the menu with Secure Boot on. The entries' names stood large beside small
  titles, and while Windows started the menu's edges stayed around a black box (owner, photographs). Escape was
  not reported.
- Support 3.15 by `dnf upgrade` over 3.14 the same day, with Secure Boot on: `status` names the graphical menu,
  its three entries carry their image class, and the restart came up by itself through the signed entry
  (`ACTIVE`). The menu looked as QEMU drew it at 2880x1920, Escape led to the text menu, and Windows started
  from the menu (owner).
- Support 3.16 by `dnf upgrade` over 3.15 the same day, with Secure Boot on: `status` `ACTIVE` with the graphical
  menu and the kernel ready; the restart came up by itself through the signed entry (`ACTIVE`); Fedora and
  Windows started from the menu, and Escape led to the text menu (owner).

## Kernel 7.3.5 revision 2: the TPM (2026-11-22)

- Installed: the kernel RPMs `7.3.5-300.sp11.2.fc45` (revision 1 plus patches 0115 and 0116, the TPM driver built
  in) and `sp11-kernel-secureboot-7.3.5-300.sp11.2.fc45.aarch64` 1-1 in one `dnf install` next to revision 1 and
  7.3.3 revision 5 (dnf removed 7.3.3 revision 4), under support 3.16 with Secure Boot on. Both boots came
  through revision 2's signed entry (`ACTIVE`).
- Confirmed: the standard checks, but for the front camera's light and the crypto node, which the round did not
  read (both device trees are byte for byte revision 1's). The bound devices are revision 1's plus
  `tpm_qcom_mssecapp`; no kernel error in the journal that revision 1's rounds did not have.
- The TPM: `/dev/tpm0` and `/dev/tpmrm0`, `systemd-analyze has-tpm2` `yes`. PCRs read through the driver: PCR 0
  as in Windows' logs, PCR 8 empty, PCR 11 set by the signed image's stub. The kernel's event log replays to the
  TPM's PCRs 0, 7 and 9. The TPM holds the four persistent keys Windows keeps and no other; `systemd-tpm2-setup`
  found the storage key at `0x81000001` and allocated no NvPCR.
- PCR 0 read the same after a deep sleep and in the second boot, after a restart in which Linux sent
  `TPM2_Shutdown`; no line from the driver or the TPM core in either boot.
- Checks of 2026-11-22 and 23 on the same kernel: the TPM answers `TPM2_Shutdown` with `TPM_RC_FAILURE` and
  takes no command after it until a restart; traced at boot, the probe's 3.09 s are mostly the first
  `TPM2_SelfTest` (2.87 s); the SELinux denial comes from `systemd-tpm2-setup-early.service`, which runs in the
  root (`docs/hardware.md`, TPM).
- Windows afterwards: Windows Hello as before (owner); `tpmtool getdeviceinformation` ready for storage and
  attestation, not locked out, lockout counter 0.
- Not as before: the kernel's start is 3.0 s slower. Every event after the TPM's probe comes that much later,
  the modem's PCIe link at 4.77 s against 1.75 s with revision 1 and Secure Boot on (`docs/hardware.md`, TPM).
  `sp11-diag` holds one SELinux denial, where revision 1 with Secure Boot on had none: `systemd-tpm2-setup` was
  refused a write to `/run/log/systemd/tpm2-measure.log`.
- By hand (owner): the round's by-hand checks passed.

## Kernel 7.3.5 revision 3 and support 3.17: the TPM's registration, the SELinux denial (2026-11-23)

- Installed: `sp11-surface-support` 3.17 by `dnf upgrade` over 3.16, then the kernel RPMs `7.3.5-300.sp11.3.fc45`
  (revision 2 plus patch 0117) and `sp11-kernel-secureboot-7.3.5-300.sp11.3.fc45.aarch64` 1-1 in one
  `dnf install` next to revisions 1 and 2 (dnf removed 7.3.3 revision 5), Secure Boot on. Both boots came through
  revision 3's signed entry (`ACTIVE`).
- Confirmed: the standard checks, but for the front camera's light and the crypto node; the bound devices are
  revision 2's, and the journal has no error that revision 2's round did not have. The TPM as with revision 2:
  its devices, `has-tpm2` `yes`, PCR 0, the event log's replay, the four persistent keys, PCR 0 after a sleep.
- The kernel ran init at 0.63 s (revision 2: 3.72 s); `tpm2.target` came at 4.28 s, in the initramfs. PCR 11 is the
  stub's value extended with `enter-initrd`, `leave-initrd`, `sysinit` and `ready`, as with revision 2.
- Support 3.17: `systemd-tpm2-setup-early.service` skipped on its new condition, no SELinux denial in the journal
  or in `sp11-diag`.
- Not as before revision 2: the hardware still comes up about 3 s late (the touch controller's SPI at 4.36 s,
  1.44 s with revision 1), as TrustZone serves the EFI variables only after the TPM's self test
  (`docs/hardware.md`, TPM).
- By hand (owner): the round's by-hand checks passed.

## The live media on 7.3.5 revision 3: no USB disk without the ADSP (2026-11-23)

- Media: `Fedora-Workstation-Live-45-1.4` remastered with kernel `7.3.5-300.sp11.3`, the ADSP blacklisted live.
  GRUB and the kernel came from the stick; the live initramfs waited for `/dev/disk/by-label/Fedora-WS-Live-45`
  until the emergency shell.
- On the installed system, same kernel: in the usual start the stick ran at 5000 Mb/s (`uas`); started with
  `module_blacklist=qcom_q6v5_pas` both xHCI controllers came up and the stick enumerated on neither port, either
  way round. The UEFI version was the one of 2026-11-06 (`docs/hardware.md`, USB-C data).
- The KIP hub's four HID devices stayed registered with the cover detached, and an initramfs built with the cover
  detached (support 3.17) carried `surface_aggregator_hub` (`docs/tablet-mode.md`).

## Fresh installation with an encrypted root, support 3.18 (2026-11-23)

- Media: `Fedora-Workstation-Live-45-1.4` remastered with kernel `7.3.5-300.sp11.3` and support 3.18, whose live
  initramfs starts the ADSP. The ADSP was up 5.8 s into the live start, the stick enumerated at 5000 Mb/s at
  6.9 s and the live root was mounted at 10.9 s; no USB disconnect, no DSP crash in the session.
- Installed: partitioned by hand, Windows' two partitions untouched: Fedora's own EFI partition (2 GB, at
  `/boot/efi`), `/boot` ext4, `/` btrfs in LUKS2 (`aes-xts-plain64`); then libdisplay-info `0.3.0-2.sp11.1`, the
  pairings from the tarball and `sp11-kernel-secureboot-7.3.5-300.sp11.3.fc45.aarch64` 1-1.
- Confirmed: the passphrase prompt takes the Type Cover's keys (the initramfs carries `surface_aggregator_hub`);
  the volume was open 2.1 s after the passphrase and the root switched 0.7 s later. `crypttab` and the boot
  entries carry the volume, the signed entries as well. The enrolled key outlived the reinstall: `READY`, then
  `ACTIVE` with Secure Boot on. `Enforcing` without a denial, no ADSP crash, the sensors online, the journal's
  errors those of revision 3's round.
- By hand (owner): the live session's sound and battery level, and the round's checks, passed.

## The TPM opens the encrypted root, support 3.19 (2026-11-23)

- Installed: `sp11-surface-support` 3.19 by `dnf upgrade` over 3.18 on the previous entry's installation, Secure
  Boot on. Then a GRUB password (`grub2-setpassword`), a key sealed in the TPM against PCR 7 in key slot 1
  (`systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7`, in a start through the signed entry),
  `tpm2-device=auto` in `crypttab`, and the initramfs rebuilt and copied for the signed entry.
- Confirmed: the next start through the signed entry opened the root without a prompt, 1.3 s after
  `systemd-cryptsetup` started (systemd 262.1 in the initramfs). `grub.cfg` and the Secure Boot menu hold the SP11
  Windows entry with `--unrestricted`; `grub.cfg` also holds os-prober's Windows entry, without it. `Enforcing`
  without a denial, no DSP crash, no provider waiting for `sync_state`, the journal's errors among those of the
  previous round.
- By hand (owner): GRUB's editor asked for `root` and the password, Windows started from GRUB's menu without it,
  and the round's checks passed.

## One Windows entry, support 3.20 (2026-11-23)

- Installed: `sp11-surface-support` 3.20 by `dnf upgrade` over 3.19, Secure Boot on; os-prober 1.81-13.
- Confirmed: `GRUB_DISABLE_OS_PROBER=true` in `/etc/default/grub`; `grub.cfg` and the Secure Boot menu hold the
  SP11 Windows entry alone, no `osprober-efi` entry; `status` `ACTIVE`, with the graphical menu and the kernel
  ready.
- By hand (owner): with Secure Boot off, Fedora's menu listed Windows once. With Secure Boot on, Escape in the
  graphical menu asked for `root` and the GRUB password, then showed the text menu.

## A poweroff after a sleep, support 3.21 and 3.22 (2026-11-23 and 24)

- Found: in a start that slept 30 s after it began, the TPM refused systemd-pcrextend's TPM2_Startup (0x101) from
  the first measurement after the wake on, and `FailureAction=reboot-force` turned the poweroff into a restart. In
  the next start the `final` measurement did the same once `shutdown`'s failure was overridden by hand.
- Installed: `sp11-surface-support` 3.21 over 3.20 (the hand-made drop-in removed with `systemctl revert`), then
  3.22 over 3.21; Secure Boot on.
- Confirmed: both drop-ins in effect (`ignore_errors=yes` for `shutdown` and `final`). After a deep sleep of 31 s
  two minutes into a start the TPM answered as before it (PCR 0, TPM2_Startup, the self test, a measurement), and
  the poweroff after it went through without a restart.
- By hand (owner): poweroffs stayed off, with 3.21 without a sleep and with 3.22 after the sleep.

## Kernel 7.3.5 revision 4: the LCD model's patches on the tested unit (2026-11-24)

- Installed: the kernel RPMs `7.3.5-300.sp11.4.fc45` (revision 3 plus patches 0118 to 0121) and
  `sp11-kernel-secureboot-7.3.5-300.sp11.4.fc45.aarch64` 1-1 in one `dnf install` next to revision 3, with
  support 3.22 and Secure Boot on. Both boots came through revision 4's signed entry (`ACTIVE`).
- Confirmed: the standard checks, but for the crypto node; the bound devices are revision 3's (458), and the
  journal has no kernel warning that the rounds of revisions 2 and 3 did not have.
- The TPM opened the encrypted root under the new signed image, 1.35 s after `systemd-cryptsetup` started: the
  first kernel change since the key was sealed.
- The three cpufreq policies (`policy0`, `policy4`, `policy8`, all `scmi`) and no line of patch 0120 in the
  kernel log.
- The start was one with the ADSP up early (4.84 s): the CDSP's IPCRTR open failed with `-121` at 10.2 s and the
  touch controller came at 12.8 s, as in such starts of revisions 2 and 3.
- By hand (owner): the round's by-hand checks passed (the brightness keys, both cameras, touch and pen, the
  Bluetooth keyboard, rotation, charging).

## A firmware update through Windows (2026-11-25)

- Changed: the Surface's firmware, through Windows; no package. Windows had listed that update as installed
  since the end of October, while its firmware device showed status 0xC0000058 and the old version kept running.
- Confirmed in the first starts on it, with kernel 7.3.5 revision 4 and support 3.22: through the signed entry
  (`ACTIVE`), the root opened by the TPM 1.4 s after `systemd-cryptsetup` started, `Enforcing`, no provider
  waiting for `sync_state`, the bound devices revision 4's (458), the five sensors' readings, a deep sleep and
  resume. The kernel's messages are kinds earlier rounds had, the QRTR pair at the resume among them.
- shim's loader stops as before (`docs/secure-boot.md`, shim's loader).
- By hand (owner): no passphrase prompt at the first start, mobile data came up, the lid woke the Surface.

## The GNSS feed in its own SELinux domain, support 3.23 (2026-11-27)

- Installed: `sp11-surface-support` 3.23 over 3.22, back to 3.22 with `dnf downgrade` and a restart, then a
  second build of 3.23 over 3.22; `Enforcing`.
- First build: the feed ran in `sp11_gnss_t` and GeoClue connected (45 fixes), but `sendto` on systemd's notify
  socket (`kernel_t`) was denied, so `READY=1` never arrived and systemd ended each start after its timeout. After
  the downgrade and the restart the feed's file read as `unlabeled_t`; its socket listened.
- Second build: the install relabelled the feed (`sp11_gnss_exec_t`) and restarted its socket. With GNOME Maps
  near a window the feed became `active` in `sp11_gnss_t` with fixes, no SELinux denial in the boot; a deep sleep
  while Maps asked for the location paused it (46 fixes) and resumed it, `StatusText=running`; closing Maps
  stopped the session (28 fixes).
- Third build, the uninstall script's comment corrected and nothing else (2026-11-28): `dnf reinstall` over the
  second build; the new comment installed, the feed still `sp11_gnss_exec_t`, its socket active, no denial.

## Pen daemon 3.1.0-5: the pen in libwacom (2026-11-28)

- Installed: `sp11-iptsd` 3.1.0-5 (the libwacom udev rule and tablet file) by `dnf upgrade` over 3.1.0-4, the
  ISO's build.
- Confirmed: before the upgrade `libwacom-list-local-devices` called the stylus's node and the kernel's G6 Pen
  node "a tablet but not supported by libwacom"; after it, "Microsoft Surface Pro 11", bus `serial`, on the
  stylus's node with the general pen and its eraser, and again on the stylus's new node after a wake. libinput's
  `Left-handed` for the stylus went from `disabled` to `n/a`.
- By hand (owner): GNOME Settings' Graphics Tablets panel showed the tablet without a new login and the General
  Pen once the pen had been used; the pen worked as before in landscape and portrait, and after the wake.
