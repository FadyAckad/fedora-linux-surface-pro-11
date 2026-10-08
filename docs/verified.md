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
