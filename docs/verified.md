# Hardware-verified status
What has been confirmed on the tested unit, by date and package version. "The kernel RPMs" are the package family
`docs/kernel.md` describes; "the feature table" is `README.md`'s.

## Fedora 44 GA Workstation (2026-09-13/14, support RPM 1.7)

- Installed: Fedora 44 GA Workstation, support RPM 1.7 and `sp11-iptsd` 3.1.0-2.sp11.
- Confirmed: boot, install, display with GPU acceleration, Wi-Fi, Bluetooth with the unit's address, touch, pen
  inking, audio, battery, Flatpak, the Windows entry in GRUB, the keyboard and pen pairings shared with Windows,
  `sp11-diag` and the pairing import; iptsd's upgrade restarts the pen daemon; suspend and resume (2026-09-17).

## Fedora 45 Beta 1.3 Workstation (2026-09-16)

- Installed: fresh install from the 45 Beta ISO (`FEDORA_TARGET=beta`) onto a LUKS-encrypted root; support RPMs 2.0
  and 2.1 as upgrades.
- Confirmed: the media boots and installs; the installed system runs on the SP11 kernel with the live-only DSP
  blacklist dropped (`qcom_q6v5_pas` loads), the 44 GA list, no early-boot Adreno error with 2.0, a clean
  `dnf upgrade --refresh` after the `kernel-uki-*` exclusion and 2.1's stock-kernel removal; suspend and resume.
- Found: `dnf upgrade --refresh` had added a stock `kernel-uki-dtbloader` boot entry (the exclusion list predated
  the package; 1.8 adds `kernel-uki-*`), removed with `dnf --setopt=disable_excludes='*' remove`. The journal's
  errors are the known benign messages (`docs/guide/troubleshooting.md`).

## Kernel 7.2.5 on Fedora 45 Beta Workstation (2026-09-17)

- Installed: `kernel-sp11-7.2.5-sp11v23` next to 7.2.0 on the 45 Beta installation.
- Confirmed (owner): the 44 GA list plus speakers, microphone, keyboard and touchpad, the brightness slider and
  multi-touch (rjindael's HID-over-SPI patches gave single touch only).

## Kernel config policy rev 1 (v23.1), SELinux (2026-09-18)

- Installed: `kernel-sp11-7.2.5-sp11v23.1` (Fedora's LSM stack in the configuration) and support RPM 2.5 as an
  update, next to the AppArmor kernels.
- Confirmed: nothing regressed; SELinux enforcing without a kernel AVC since the restore on 2026-09-19.
- Found: the installer's `selinux=0` and `SELINUX=disabled` were still in place (`docs/kernel.md`, SELinux).

## Sensors stack (2026-09-19 to 2026-09-21)

- Installed: hexagonrpc 0.5.0-6.git79d1bed, libssc 0.4.4-2.git54dd13e, iio-sensor-proxy 3.9-3.sp11.1 and
  sp11-sensors 1.9-1 on the 45 Beta installation, support RPM 2.6; sp11-sensors 1.10 since the ISO of 2026-09-22.
- Confirmed: light, accelerometer, gyroscope, magnetometer and compass readings (`ssccli`), `monitor-sensor` with
  orientation, tilt, light and compass, GNOME's auto-rotation, suspend and resume, SELinux enforcing without an AVC
  for the stack's domains, no ADSP crash since the write support. Not reported: automatic screen brightness.

## Kernel SP11 revision 2 (v23.2), tablet mode (2026-09-21)

- Installed: `kernel-sp11-7.2.5-sp11v23.2` (the POS tablet-mode switch) as an update on the same system.
- Confirmed: the POS switch follows the keyboard, and with the sensors stack GNOME's auto-rotation works
  (`docs/sensors.md`).

## Fedora 45 Beta Workstation from the revision-2 ISO (2026-09-22)

- Installed: fresh install from the ISO of 2026-09-22: kernel v23.2, support 2.6, iptsd 3.1.0-3, the sensors stack.
- Confirmed (owner): the live session and the installed system run SELinux enforcing without `selinux=0` or a
  relabel boot, package file times instead of the ISO's build date, the sensors stack active from the first boot,
  the pairing import, `dnf upgrade --refresh` without a stock kernel, the feature table of the time.

## Fedora's kernel 7.2.5-300.sp11.1 and support RPM 3.0 (2026-09-23)

- Installed: support RPM 3.0 as an upgrade on the installation above, then the kernel RPMs `7.2.5-300.sp11.1.fc45`
  with `dnf install` next to `kernel-sp11` v23.2.
- Confirmed: the kernel boots as the saved default, SELinux enforcing; the ADSP runs Linux's firmware without a
  crash and accepts the speaker-protection graph; the microphone records speech at about −22 dBFS RMS with 3.0's
  gain; sensors, touch, pen, the POS switch, keyboard, Bluetooth, battery, fan, platform profile, `scmi` cpufreq,
  GPU, Wi-Fi, NVMe and USB bound; a deep suspend and resume; by hand (owner) Wi-Fi, Bluetooth, touch, the pen,
  the speakers, tablet mode, the volume keys, suspend and resume, Flatpak and the Windows entry.
- Found: the CDSP never wakes from its first sleep (cause and fix: `docs/kernel.md`, Sync state); `sp11-diag`'s
  audio section found no controls through `amixer -c` (3.1 reads `hw:N`).

## Kernel revision 2 (7.2.5-300.sp11.2, CDSP boot order) and support RPM 3.1 (2026-09-23)

- Installed: the kernel RPMs `7.2.5-300.sp11.2.fc45` with `dnf install` next to revision 1; support 3.1 over 3.0.
- Confirmed: boots as the saved default; the CDSP starts after the ADSP as designed; speakers, microphone, sensors
  and battery as before. 3.1's audio section reads the UCM's values (`TX_DEC0/1 Volume` 100,
  `WSA_RX0/1 Digital Volume` 81, `SpkrLeft/SpkrRight PA Volume` 24).
- Found: the CDSP still stopped answering on both boots; `sp11-cdsp-check` restarted it about 30 s after boot and
  it stopped again at its next sleep, so the boot order is not the cause.

## Sync state and kernel revision 3 (2026-09-24)

- Installed: the kernel RPMs `7.2.5-300.sp11.3.fc45` (the video clock controller and the crypto engine) with
  `dnf install` next to revision 2 and v23.2.
- Confirmed: boots as the saved default; all 20 providers synced, no FastRPC error; on three boots the CDSP answered
  the ping without a restart, after 3 minutes idle and after a suspend and resume, as did the ADSP.
- Found: on revision 2 `rpmhpd`, `aggre2_noc` and `mc_virt` held their boot votes for the two drivers Fedora lacks,
  and forcing `rpmhpd`'s sync woke the stuck CDSP at once: the cause (`docs/kernel.md`); a held QDSS clock changed
  nothing. Revision 3's crypto engine fails the AES XTS and CTR self-tests, so revision 4 keeps its hashes only.
  Across a 1-minute suspend the SoC's `aosd`, `cxsd` and `ddr` counters stayed at 0: no deepest sleep in suspend.

## Fresh installation from the revision-4 ISO (2026-09-24)

- Installed: fresh install from the 45 Beta 1.3 ISO of 2026-09-24: kernel `7.2.5-300.sp11.4`, support RPM 3.2,
  iptsd 3.1.0-3, hexagonrpc 0.5.0-6, libssc 0.4.4-2, iio-sensor-proxy 3.9-3.sp11.1, sp11-sensors 1.10.
- Confirmed: the kernel without the live-only blacklist or `selinux=0`, SELinux enforcing; both DSPs answer the ping
  on two boots, the crypto engine registers `sha256-qce` and `hmac-sha256-qce` only, no provider waiting for
  sync_state; sensors, the POS switch, the sound card with 3.1's UCM values, the pairings imported,
  `dnf upgrade --refresh` without a stock kernel; by hand (owner) every row of the feature table of the time, with
  automatic screen brightness, tablet mode, the power modes and USB-C charging and data for the first time.
- Found: the CDSP's `sleep_stats` assert once, recovered by remoteproc, and the ADSP's `Handover signaled` lines on
  every kernel since the sensors stack: both benign (`docs/guide/troubleshooting.md`).

## Kernel revision 5 (7.2.7-300.sp11.5) as an update (2026-09-25)

- Installed: the kernel RPMs `7.2.7-300.sp11.5.fc45` (the patch set rebased onto Fedora's 7.2.7) with `dnf install`
  next to `7.2.5-300.sp11.4` on the installation above; support RPM 3.2 unchanged.
- Confirmed: as revision 4, plus both speakers with `SP11 stage SP/SPVI enabled with VI+CPS feedback accepted` at
  every playback and no `All ports busy` (7.2.6's SoundWire port check, patch 0058), the touch controller in QSPI
  mode (`SP11: accepting protocol 9 as QSPI controller`), the same 422 bound devices, a deep suspend and resume
  with display, touch, pen, keyboard, Wi-Fi and sound working after it (owner).
- Found: new warnings against revision 4, none with a visible effect: one `dpu_crtc_disable` frame-done timeout,
  `IRQ: set affinity failed` and a PM ordering warning of a PHY's hwmon device, in a boot with a suspend.

## Kernel revision 6 (7.2.7-300.sp11.6) and support RPM 3.3: cameras (2026-09-26)

- Installed: the kernel RPMs `7.2.7-300.sp11.6.fc45` (revision 5 plus the camera commits 0059–0070) with
  `dnf install` next to revisions 4 and 5, support RPM 3.3 over 3.2 in the same transaction.
- Confirmed: as revision 5, with the camera clock controller, both CCI buses, CAMSS, the three sensors and the
  flash LED bound (438 devices); `cam -l` lists the three cameras; front and rear camera in GNOME Snapshot and
  Firefox, also after a suspend and resume (owner).
- Found: one `i2c-qcom-cci ac15000.cci: master 1 queue 0 timeout` when Snapshot switched to the rear camera,
  recovered by the OV13858 retry (0069).
- Not working: dark, grey pictures (the room, as the next rounds showed); the front camera's light (revision 7).

## Kernel revision 7 (7.2.7-300.sp11.7): the front camera's light, raw sensor levels (2026-09-26)

- Installed: the kernel RPMs `7.2.7-300.sp11.7.fc45` (revision 6 plus the light's device-tree commit 0071) with
  `dnf install`; dnf removed `7.2.5-300.sp11.4`.
- Confirmed: as revision 6; the LED `white:camera-indicator` reads 1 while the front camera streams and 0 otherwise,
  and the light comes on (owner). `sp11-camera-probe` in a lamp-lit evening room: raw frames almost empty, exposure
  and gain acting as set.
- Found: nine CCI queue timeouts on the rear camera's bus in two bursts, every capture completed; the light sensor
  at 0 lux in this and both revision-6 diags (dim rooms, as the next day showed).

## Kernel revision 7 in daylight: camera levels, light sensor (2026-09-27)

- Installed: revision 7 unchanged, in daylight.
- Confirmed: the light sensor works (97 to 99 lux in the room, about 2,700 to 2,800 lux facing a window);
  `sp11-camera-probe` facing the window gives a normal, clipping signal from both cameras, so the evening's dark
  pictures came from the room. GPIO 105 and 106 sit in the CCI function with pull-up; GPIO 225 is an output, low
  with no camera in use.

## Raw sensor measurements: frame length and gain range (2026-09-27)

- Installed: revision 7 unchanged.
- Confirmed: `sp11-camera-probe --frame-length` and `--gain-range` on both cameras; the rear camera takes the frame
  length the driver writes (29.95, 19.97 and 14.98 fps at 3214, 4821 and 6428 lines).
- Found: the IMX681 ignores the frame length at `0x0340` and keeps 3554 lines at 30 fps (fixed in revision 8); the
  OV13858 applies no analogue gain above 15.5x; a chessboard of faintly coloured squares in dark pictures from
  libcamera's GPU debayering (`docs/camera.md`).

## Kernel revision 8 (7.2.7-300.sp11.8): the IMX681's frame length (2026-09-28)

- Installed: the kernel RPMs `7.2.7-300.sp11.8.fc45` (revision 7 plus 0072, the IMX681's frame length) with
  `dnf install`; dnf removed `7.2.7-300.sp11.5`.
- Confirmed: as revision 7, with no DSP crash and no CCI timeout in the boot; the front camera takes the frame
  length the driver writes (30.01, 20.00 and 15.00 fps at 3554, 5331 and 7108 lines, `docs/camera.md`).
- Found: a daylight photo with the front camera too bright (an average of 169 of 255, 72 % of the face at 245 or
  above): libcamera's default exposure target.

## Kernel revision 9 (7.2.7-300.sp11.9): the camera driver fixes (2026-09-28)

- Installed: the kernel RPMs `7.2.7-300.sp11.9.fc45` (revision 8 plus 0073, the OV13858's lowest pixel rate, and
  0074, the IMX681's control lock) with `dnf install`; dnf removed `7.2.7-300.sp11.6`.
- Confirmed: as revision 8; the front camera streams 300 frames with its light on (0074); the OV13858's pixel rate
  control reads 216 to 474.24 MHz and its 2112x1188 mode (`cam -s width=1280,height=720`) reports 216 MHz at
  29.95 fps with a full exposure of 33306 us, where revision 8 read 432 MHz (0073, `docs/camera.md`); no OV13858
  retry; both cameras in GNOME Snapshot, Wi-Fi, Bluetooth, the pen, tablet mode and suspend and resume (owner).

## Support RPM 3.4: sp11-diag's media nodes (2026-09-29)

- Installed: `sp11-surface-support` 3.4-1 over 3.3 with `dnf install`, on revision 9.
- Confirmed: `sp11-diag`'s camera section counts 48 media, video and subdevice nodes (3.3 counted the `/dev/media`
  directory too, 51) and prints the media graph without the `Failed to enumerate /dev/media (-21)` line.

## Fedora 45 Beta KDE Plasma Desktop: live session and installation (2026-09-30)

- Installed: `Fedora-KDE-Desktop-Live-45_Beta-1.3` remastered with kernel `7.2.7-300.sp11.9`, support RPM 3.4, the
  sensors stack (hexagonrpc 0.5.0-8, sp11-sensors 1.10), the RPMs built for Workstation;
  fresh install from the second build (sha256 `f84b60ba…`), whose installer opens in Firefox.
- Confirmed: the live session's Plasma desktop draws correctly at 2880x1920, scale 200 % (a recording of the
  first build, `d6c57aeb…`); on the installed system the whole feature table (owner, 2026-09-30 and
  2026-10-01), the sensor readings and the front camera's light included.
- Found: the first build's installer, in slitherer as Fedora's KDE profile sets it, was drawn corrupted by its GPU
  rendering; step 50 switches the viewer to Firefox (`docs/fedora-media.md`).

## Kernel revision 10 (7.2.8-300.sp11.10) and Fedora's libcamera, KDE Plasma installation (2026-10-02 to 2026-10-05)

- Installed: the kernel RPMs `7.2.8-300.sp11.10.fc45` (revision 9's 74 patches on Fedora's 7.2.8) with
  `dnf install` next to revision 9; libcamera Fedora's `0.7.2-3.fc45`.
- Confirmed: as revision 9 (the same 439 bound devices and LEDs); a second boot slept 8.5 hours (deep) and
  resumed; with Fedora's libcamera `cam -l` lists the three cameras on `uncalibrated.yaml` and the front camera
  streams with its light on; the whole feature table under Plasma, both cameras included (owner, 2026-10-05).
- Found: auto-rotation sometimes stops after a wake until iio-sensor-proxy is restarted; in the diagnostics' boot
  the proxy spun at 92 % of a core and crashed in libssc (fixed in libssc 0.4.4-3, `docs/sensors.md` Known issues).

## libssc 0.4.4-3: the sensor stall (2026-10-07)

- Installed: `libssc-0.4.4-3.git54dd13e.sp11` (release 2 plus the three patches of `payload/sensors/libssc/`) over
  release 2 on the KDE Plasma installation (kernel revision 10).
- Confirmed: the proxy links release 3's `libssc.so.2`; twenty claim-and-release cycles (`monitor-sensor` for 0.3 s
  each) leave it active without CPU time, with orientation, tilt and compass readings afterwards; after a reboot
  and a sleep, 52 minutes of uptime with 1 s of CPU time and no crash (owner). The multi-day watch continues.

## iio-sensor-proxy 3.9-3.sp11.2 and sp11-sensors 1.11: the sleep pause (2026-10-08)

- Installed: `iio-sensor-proxy-3.9-3.sp11.2` and `sp11-sensors-1.11-1` over 3.9-3.sp11.1 and 1.10 with
  `dnf install --setopt=disable_excludes='*'`, on the KDE Plasma installation (kernel revision 10, libssc
  release 3).
- Confirmed: the proxy holds a `sleep` `delay` inhibitor lock, no AVC; awake with automatic brightness on, the light
  stream runs (10 SMP2P interrupts in 10 s); 20 sleeps in one boot, each with its pause and resume logged and none
  with an ADSP signal in its window, among them 25 minutes and 1.9 hours with the cover closed; the proxy ran the
  boot without a restart or crash (0.54 s of CPU in 4 h 40 min), no ADSP or CDSP crash; after the last wake
  `ssccli` reads all five sensors and the proxy streams the compass.
- Found: from the 13th start of a boot the guard refuses hexagonrpcd, and quick sleeps hit its start limit, so the
  unit ends the boot failed; the sensors keep working. At the upgrade the old proxy did not stop within the 45 s
  stop timeout and was aborted (core dump).

## sp11-sensors 1.12: hexagonrpcd after many wakes (2026-10-08)

- Installed: `sp11-sensors-1.12-1` over 1.11 with `dnf install`, then a reboot (iio-sensor-proxy 3.9-3.sp11.2).
- Confirmed: 15 sleeps and wakes with the cover within seven minutes, none with an ADSP signal; the guard's
  counters at `attaches: 1` and `resume-attaches: 15`; the daemon running after the last wake, without a refusal or
  a start-limit line; the proxy streams the accelerometer and the compass afterwards.
- Found: each of the 10 wakes with the power key that evening was followed by a new sleep 1 to 6 s later, without
  another press; the old proxy's core dump from the upgrade shows it waiting in an accelerometer open.

## iio-sensor-proxy 3.9-3.sp11.2 at shutdown, KDE's power button on Lock screen (2026-10-08)

- Confirmed: at the five reboots after the install of 3.9-3.sp11.2 (17:27 to 21:15) the proxy stopped in 69 to
  92 ms, without a time-out or a core dump.
- Confirmed: with KDE's power button on Lock screen (`PowerButtonAction` 32 in the AC, Battery and LowBattery
  profiles) the tablet stayed awake after a power-key wake.
- Found: the CDSP asserted (`sleep_statsi.c:537`) during one of the five stops, while the proxy closed its streams,
  and once during `sp11-sensors-check`'s `ssccli` readings.

## Kernel revision 11 (7.2.9-300.sp11.11) (2026-10-08)

- Installed: the kernel RPMs `7.2.9-300.sp11.11.fc45` (revision 10's 74 patches on Fedora's 7.2.9) with
  `dnf install` next to revision 10, on the KDE Plasma installation.
- Confirmed: the boot entry with the Denali device tree and the SP11 arguments, `Enforcing`; the four GENI I2C buses
  and both PS8830 retimers bound, with no I2C or retimer message in this boot or in revision 10's; the speaker stage
  with VI+CPS feedback, the QSPI touch path, both DSPs over FastRPC (the CDSP again in a second boot), the crypto
  engine's two hashes, the three cameras and the front camera's light, no provider waiting for sync_state; the same
  439 bound devices and loaded modules as revision 10, no new kind of kernel warning; the five sensors' readings and
  the proxy's orientation and compass; the whole feature table under Plasma (owner).
- Found: the CDSP's known `sleep_statsi.c:537` assert once while `sp11-diag` ran, in a boot without a sleep,
  recovered by remoteproc (`docs/sensors.md`, Known issues).

## Fresh installation from the 7.2.11 revision 1 ISO (2026-10-19)

- Installed: fresh install from `Fedora-Workstation-Live-45_Beta-1.3` remastered with kernel `7.2.11-300.sp11.1`
  (revision 11's 74 patches on Fedora's 7.2.11, the first revision of the restarted count), support RPM 3.4, iptsd
  3.1.0-3, hexagonrpc 0.5.0-8, libssc 0.4.4-3, iio-sensor-proxy 3.9-3.sp11.2, sp11-sensors 1.12 and Fedora's
  libcamera `0.7.2-3.fc45` (sha256 `1c11373e…`); the media check passed and the installer opened in Firefox (owner).
- Confirmed: the SP11 arguments, `Enforcing`; the speaker stage with VI+CPS feedback at every playback, also after
  wakes, with both WSA digital volumes at 81 (-3 dB, the machine driver's cap), which 7.2.11 applies at playback
  start; both UCSI connectors and PS8830 retimers; the QSPI touch path; both DSPs over FastRPC (the CDSP again in a
  second boot); the crypto engine's two hashes; the three cameras and the front camera's light; no provider
  waiting for sync_state; four deep sleeps, each resumed, without an ADSP or CDSP crash; the five sensors' readings
  and the proxy's orientation, light and compass; the same bound devices as revision 11; the whole feature table
  under GNOME, the speakers' level and balance included (owner).
- Found: no new kind of kernel warning but those that boots with sleeps showed in revisions 5 to 10
  (`IRQ: set affinity failed`, a PHY's hwmon PM ordering warning, the Surface hub's unhandled event); the ADSP's
  known `Handover signaled` lines while `sp11-diag` reads the sensors.

## Kernel 7.2.11 revision 2 (7.2.11-300.sp11.2) (2026-10-22)

- Installed: the kernel RPMs `7.2.11-300.sp11.2.fc45` (revision 1's 74 patches and the battery-driver fixes 0075
  to 0077) with `dnf install` next to revision 1, on the Workstation installation of 2026-10-19.
- Confirmed: the SP11 arguments, `Enforcing`; the speaker stage with VI+CPS feedback; the QSPI touch path; both
  DSPs over FastRPC (the CDSP again in a second boot); the crypto engine's two hashes; the three cameras listed; no
  provider waiting for sync_state; a 36-minute deep sleep, resumed; the journal's error kinds those of revision 1.
  The battery's `capacity` present, UPower's percentage taken from it; with a USB-C charger, unplugging and
  plugging in each sent a uevent for `qcom-battmgr-usb`, and UPower's `on-battery` followed at once.
- Before, on revision 1 the same day with the Surface charger: no uevent for `qcom-battmgr-ac` and
  `on-battery: no` after unplugging until the next resume; at 100 % on the charger `status=Not charging`
  (`docs/hardware.md`).
- Confirmed by hand (owner): the voice from the matching speaker and the microphone; touch, two-finger scrolling
  and pen inking; the front and the rear camera in Firefox; Wi-Fi, the Bluetooth keyboard, pen and audio,
  brightness, volume keys, keyboard and touchpad, rotation with the keyboard folded back, power profiles, a USB
  device on each USB-C port; GNOME's battery icon on battery and charging after unplugging and plugging in; all of
  them again after the sleep.
- Confirmed by hand on 2026-10-23 (owner), the feature table's remaining rows: GPU acceleration, Flatpak, the
  Windows entry in GRUB, the keyboard and pen pairings shared with Windows, the sensors' readings, tablet mode,
  automatic screen brightness, the front camera's light.
- Not covered: the Surface charger and a full battery on revision 2.

## Kernel 7.2.11 revision 3 and support 3.5: the 5G modem and GPS (2026-10-23)

- Installed: support RPM 3.5 over 3.4, then the kernel RPMs `7.2.11-300.sp11.3.fc45` (revision 2 and the 5G SKU's
  device tree, 0078) with `dnf install` next to revision 2, on the Workstation installation of 2026-10-19.
- Confirmed: `GRUB_DEVICETREE` the 5G tree, the new entry on `x1e80100-microsoft-denali-oled-5g.dtb` and revisions
  1 and 2 still on the OLED tree; the model `(OLED, 5G)`, `Enforcing`; the speaker stage with VI+CPS feedback, the
  QSPI touch path, both DSPs over FastRPC (the CDSP again after a reboot), the crypto engine's two hashes, the three
  cameras listed, no provider waiting for sync_state.
- Confirmed, the modem: `17cb:0308` on PCIe 5; ModemManager's modem at 27.7 s with `wwan0qmi0 (ignored)`;
  `sp11-gnss.socket` active, its socket labelled `sp11_gnss_var_run_t`; near a window GeoClue reported
  `GPS GGA+RMC` with 50 m, 50 of 59 locations in 120 s, the first after 71 s; deep sleeps without `failed to
  suspend device`; a reboot without ModemManager's 45 s stop.
- Found: away from windows no position in 120 s (one satellite with signal); with 3.5's sleep hook GeoClue did not
  reconnect to the feed after a sleep (support 3.6); two SELinux denials of GeoClue's compass source at every
  GeoClue start (sp11-sensors 1.13).

## Support RPM 3.6: the GNSS feed across sleep (2026-10-23)

- Installed: support RPM 3.6 over 3.5 with `dnf install`.
- Confirmed: a deep sleep while an application asked for the location: the feed paused 28 ms after the sleep
  hook's signal and 0.25 s before the suspend, resumed 60 ms after the wake on the same connection (134 fixes
  after it), GPS locations again; GeoClue's CPU time under a second.

## sp11-sensors 1.13: GeoClue's compass (2026-10-23)

- Installed: `sp11-sensors-1.13-1` over 1.12, then a reboot.
- Confirmed: 229 of 230 GeoClue locations in 60 s with a heading, which followed a quarter turn of the tablet; no
  denial for GeoClue; no CDSP crash.
- Found: five denials for iio-sensor-proxy at every start (`/etc/passwd`, `dac_read_search`, `dac_override`), in all
  six boots checked, with 1.12 as well; `sp11-sensors-check` and `sp11-diag` had never shown a denial.

## sp11-sensors 1.14 and 1.15, support RPM 3.7: the denials (2026-10-24)

- Installed: 1.14 and 3.7 over 1.13 and 3.6; one boot with iio-sensor-proxy under `strace`, then the way back;
  1.15 over 1.14 and a reboot.
- Confirmed: both diagnostics list the boot's denials (1.14, 3.7); the strace boot traced the proxy's five to
  gvfs's GIO module (`docs/sensors.md`), with the sensors and rotation working under strace; with 1.15 no denial
  for the proxy, all three of its sensors found, GeoClue's locations with headings, GPS among them; rotation
  before and after a sleep (owner).
- Confirmed by hand (owner): GNOME Maps, an application behind GNOME's location prompt, shows the location with
  its heading. Maps does not name the source; GPS and Wi-Fi both come to 50 m here.
- Confirmed by hand on 2026-10-24 (owner), with revision 3, support RPM 3.7 and sp11-sensors 1.15: every row of the
  feature table's Workstation column, among them GPU acceleration, the backlight, Wi-Fi, Bluetooth with the
  keyboard, pen and audio, touch, multi-touch and the pen, the speakers by ear and the microphone, keyboard and
  touchpad, battery status, power profiles, USB-C charging and data, Flatpak, the Windows entry in GRUB, the
  pairings shared with Windows, the sensors' readings, tablet mode, automatic screen brightness, both cameras in an
  application and the front camera's light.

## Kernel 7.2.11 revisions 4 and 5: deep sleep (2026-10-27 and 2026-10-28)

- Installed: the kernel RPMs `7.2.11-300.sp11.4.fc45` (revision 3 and the mainline changes 0079 to 0081) with
  `dnf install` next to revision 3, dnf removing revision 1; on 2026-10-28 `7.2.11-300.sp11.5.fc45` (revision 4 and
  the modem fix 0082), dnf removing revision 2.
- Confirmed with revision 4: the 5G tree, `Enforcing`; the speaker stage with VI+CPS feedback, the QSPI touch path,
  both DSPs over FastRPC (the CDSP again in a second boot), the crypto engine's two hashes and the engine idle as
  `suspended`, no provider waiting for sync_state; in a 10-minute sleep the six PCIe devices in D3hot and `ddr`
  counting 591 of 630 s; GPS after the modem's restart.
- Found with revision 4: a night at 1.40 W, in which the modem's driver refused a suspend 26 s after a wake and
  systemd fell back to `s2idle` (`docs/hardware.md`, Sleep).
- Confirmed with revision 5: both DSPs, the crypto engine idle; sleeps started within 15 s of a wake stayed deep,
  the modem powered down for them, GPS afterwards; 8 hours asleep at 0.33 W, `ddr` 94 % of the time; no provider
  waiting for sync_state, the CDSP again in a second boot.
- Confirmed by hand with revision 5 (owner): the speakers, the microphone, touch and the pen, Wi-Fi, the keyboard
  cover's keys and touchpad, Bluetooth, rotation with the keyboard folded back.
- Confirmed by hand on 2026-10-28 (owner), with revision 5, the feature table's remaining rows: the backlight,
  power profiles, USB-C charging and data, Flatpak, the Windows entry in GRUB, the pairings shared with Windows,
  the sensors' readings, tablet mode, automatic screen brightness, both cameras and the front camera's light.

## Kernel 7.2.11 revisions 6 and 7: GPU fixes, video codec (2026-10-28 and 2026-10-29)

- Installed: on 2026-10-28 the kernel RPMs `7.2.11-300.sp11.6.fc45` (revision 5, the Type-C switch-array fix, five
  Adreno fixes, the clock `sync_state` series and the video codec) with support RPM 3.8 (the codec's firmware),
  `dnf install` next to revision 5, dnf removing revision 3; on 2026-10-29 `7.2.11-300.sp11.7.fc45` (revision 6
  without the clock series) next to revision 5, revision 6 removed by the owner before.
- Confirmed with revision 6: the 5G tree, `Enforcing`, both DSPs, the crypto engine idle as `suspended`; no GPU
  hang, GMU or HFI line in the kernel log after a sleep; the codec's V4L2 devices. One boot without
  `clk_ignore_unused` and one without `pd_ignore_unused` too came up with a working screen; in a 10-minute sleep
  each, `cxsd` stayed at 0 and `ddr` counted 571 of 609 s and 560 of 599 s.
- Found with revision 6: the clock series left the AOSS clock provider waiting for `sync_state` in the normal entry;
  without `clk_ignore_unused` the eDP pixel clock warned twice at the display's enable; a USB 3 stick plugged in
  reversed was still not found (`docs/hardware.md`, USB-C data).
- Confirmed with revision 7: `Enforcing`, both DSPs, the crypto engine idle, no GPU hang, GMU or HFI line after a
  sleep, no provider waiting for sync_state; a 720p VP9 clip decoded in hardware frame for frame as libvpx decodes
  it (`docs/hardware.md`, Video codec); the USB 3 stick at 5000 Mb/s plugged the usual way on port A.
- Confirmed by hand with revision 7 (owner): the speakers, the microphone, touch and the pen, Wi-Fi, the keyboard
  cover's keys and touchpad, Bluetooth, rotation with the keyboard folded back, a sleep and wake.
- Confirmed with revision 7 on 2026-10-29: 720p H.264 and H.265 clips decoded in hardware once relabelled `bt601`,
  the H.264 frames matching Cisco's `openh264dec`; the reversed USB-C plug's port state and the retimer test
  (`docs/hardware.md`, USB-C data).

## Kernel 7.2.11 revision 8: mobile data (2026-10-29)

- Installed: the kernel RPMs `7.2.11-300.sp11.8.fc45` (revision 7 and patch 0090, the modem's data channels for
  `mhi_wwan_mbim`) with support RPM 3.8, `dnf install` next to revisions 5 and 7, dnf removing revision 4; a
  nano-SIM (o2 Germany) in the slot behind the SSD door.
- Confirmed with revision 8: `Enforcing`, both DSPs, the crypto engine idle, no provider waiting for sync_state;
  `wwan0` from `mhi_wwan_mbim`, ModemManager's ports `wwan0 (net), wwan0mbim0 (mbim)`; over `wwan0` alone pings
  over IPv4 and IPv6 and 5 MB in 0.38 s; GPS's QRTR path; no SELinux denial. Before it, a module build of the same
  change on revision 7 had passed with pages in Firefox over mobile data (owner, 2026-10-29).
- Measured after a 10-minute deep sleep (the mobile profile set to connect by itself): Wi-Fi online after 20.7 s,
  the modem answering after 36.0 s, registered after 50.5 s, mobile data online after 52.3 s; `ddr` 579 of 619 s,
  `cxsd` 0. With a test tree that keeps the modem powered through the sleep (`vreg_wwan` always on, not PCIe 5's
  slot supply): the modem resumed without a restart, answering after 3.4 s, registered after 15.7 s, mobile data
  after 16.7 s; `ddr` 569 of 608 s, `cxsd` 0; the battery's reading changed by the same 0.511 Wh in both runs.
- Wi-Fi: country `DE` for the system and the chip, no channel limited to passive scanning, 102 channels; a full
  scan took 8.5 s with the country known, the first scan after a wake 16 s (the chip restarts in world roaming and
  finds `DE` 7 s into it).
- Confirmed by hand with revision 8 (owner): every row of the feature table.
