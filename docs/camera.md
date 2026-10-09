# Cameras
The three cameras: the kernel side the SP11 patch set carries since revision 6, Fedora's libcamera, and what only
the device can show.

## Hardware

### The three modules

- turbineBMW's Denali device tree (turbineBMW/surface-pro-11-linux) describes three camera modules, supplied by the
  PM8010 camera PMIC.
- The front camera: a Sony IMX681 (3840x2640 RAW10, one C-PHY trio at 2406 Msym/s) on CCI1 bus 1 at `0x1a` and
  CAMSS port 2 (CSIPHY2).
- The rear camera: an OmniVision OV13858 (4224x3136 RAW10, four D-PHY lanes) on CCI0 bus 1 at `0x10` and port 1.
- The IR camera: an ST VD55G0 (644x604 `Y10P`, one D-PHY lane) on CCI0 bus 0 at `0x60` and port 0, lit by the
  PM8550 flash controller's current sinks 1 and 4 (600 mA ceiling).

### The front camera's light

- Revision 7 (0071) describes the light as a GPIO LED on TLMM GPIO 225, active high (confirmed on the device), and
  gives it to the IMX681 as its `privacy` LED, without which the light stays off while the front camera streams.
- The pin is one of the two TLMM outputs of Windows' camera device `CAMP` (`QCOM0C32`, subsystem `MSHW0495`), 225
  and 105; mainline's Denali tree names 225 `cam_indicator_en`, and what Windows drives through 105 (CCI1
  bus 0's unused SDA pin on Linux) is not known.
- The IMX681 driver registers with `v4l2_async_register_subdev_sensor()`, so the V4L2 core takes the LED, locks its
  sysfs control (a write returns `EBUSY`) and lights it while the sensor streams; step 20 checks the link in the
  built device tree.

### The IMX681's modes

- Sony's datasheet (IMX681-AAQH5-C, 0.0.5): 4032x3024 active pixels of 1 um (Type 1/3.6), RGGB, analog and digital
  gain up to 24 dB each, static defect correction from the sensor's OTP, and four video modes besides the full
  4032x3024 at 30 fps: 2x2 analog binning at 2016x1512 and, cropped to 16:9, 2016x1134, and 4x4 binning at
  1008x756, each at 60 fps; the register settings are in application notes that are not public.
- The driver's one mode, recorded from Windows, reads a 3840x2640 crop (x 104 to 3943, y 256 to 2895) without
  binning: it programs the CCS crop and output-size registers (`0x0344` to `0x034f`, `0x0408` to `0x040f`) but none
  of the binning registers (`0x0900` to `0x0902`).

### The image processing Windows has

- Windows runs the cameras through the SoC's Spectra ISP ("Qualcomm Spectra 695 ISP Camera AVStream Device"), tuned
  per camera module by files in the DriverStore (`SCFG_{FRONT,REAR,AUX}_MSHW049x.bin` and sensor-module `.bin`,
  `.pb` and `.json` files, an undocumented format; rjindael/fedora-surface-pro-11 `CAMERA.md`).
- Linux has no path to that processing (2026-10-09): CAMSS on the X1E80100 captures raw frames only
  (`camss-vfe-680.c` programs the RDI write masters, "RDI is all we support right now"; the `msm_vfe0_pix` and
  `msm_vfe1_pix` entities have nothing behind them) and the device tree has no ICP, IPE or BPS node. Bryan
  O'Donoghue's ICP/BPS/IPE driver for the X1E80100 (posted 2026-07-03) is an early RFC that needs Qualcomm's
  closed ICP firmware, and Hans de Goede's libcamera `camss` pipeline handler (v2, 2026-07-21) still uses the
  software ISP, so every processing step happens in libcamera's software ISP.

## Kernel

### What mainline lacks and the patch set carries

- Mainline 7.2 has CAMSS for the X1E80100, the camera clock controller and the CCI driver, and Fedora builds them
  (`VIDEO_QCOM_CAMSS`, `I2C_QCOM_CCI`, `CLK_X1E80100_CAMCC`, `VIDEO_OV13858`, `LEDS_QCOM_FLASH`); still missing in
  7.3: CAMSS C-PHY, the camera nodes of `hamoa.dtsi` (7.3 brings the clock controller's) and of the Denali board,
  and the IMX681 and VD55G0 drivers.
- Revision 6 carries them as 0059–0070 (`docs/kernel-patches.md`): turbineBMW's camera branch, their OV13858 retry
  of the first register write after power-up and ooaklee's IMX681 exposure fix; `kernel-local` adds
  `VIDEO_IMX681=m` and `VIDEO_VD55G0=m`. Revision 8 changes the IMX681 driver (0072), revision 9 the OV13858's and
  the IMX681's (0073, 0074); the other driver files equal turbineBMW's 7.3 port, and the IMX681's Kconfig and
  Makefile entries follow the MAX9271 library entry, clear of the IMX471 hunks of Fedora's `patch-7.2-redhat.patch`.
- The camera nodes add two users of the providers that must reach `sync_state` (`docs/kernel.md`), the camera clock
  controller on the RPMh power domains and CAMSS on the interconnect; step 20 finds a driver for both in Fedora's
  packages; `sp11-diag`'s sync line shows whether they bind.

### The IMX681 frame length (revision 8)

- The sensor ignores the standard frame-length register `0x0340` and takes a 24-bit frame length at `0x033d` (3554
  lines in the mode table) and the exposure at `0x0229`, at most the frame length less 8 lines.
- A line takes 9.38 us and the sensor lengthens the frame to the exposure plus 8 lines
  (`sp11-camera-probe front --frame-length`); the driver assumed 2708 lines of 12.3 us and left a quarter of each
  frame's exposure unused.
- Revision 8 (0072) writes `0x033d`, keeps 3554 lines as the shortest frame, lets the exposure reach the frame
  length less 8 lines (3546 at 30 fps) and reports the line as 5144 pixels of the 548.57 MHz CSI-2 pixel rate, so
  the frame duration libcamera derives is the sensor's.

### Revision 9: two fixes from a review

- The OV13858 pixel rate (0073): the Surface Pro 11 mode put its 592.8 MHz link frequency first in the driver's
  menu, whose second entry gave the pixel rate's minimum, 432 instead of 216 MHz, so the 270 MHz modes (among them
  GNOME Snapshot's 2112x1188) reported half the `ExposureTime`; 0073 takes the minimum from the lowest link
  frequency, and the picture does not change, since libcamera 0.7.2 uses the pixel rate only for that metadata.
- The IMX681 control lock (0074): the controls are applied at stream start under the control handler's lock, which
  `__v4l2_ctrl_handler_setup()` expects and `.s_stream` does not hold.

### Revision 12: the gain steps (prepared, not built)

- Three commits for the top of `sp11/7.2.9` (`docs/kernel-patches.md`, Planned): 0075 limits the OV13858's analogue
  gain control to codes 0x80 to 0x7c0 (1x to 15.5x, smallest libcamera step 0.145x instead of 0.64x), 0076 writes
  the IMX681's digital gain to all four channel registers, 0077 offers the IMX681's analogue gain as linear gain in
  1/256 steps (256 to 4096) and writes the nearest code (module parameter `linear_gain`, default on; `0` restores
  the register code for a libcamera with an IMX681 sensor helper).
- Without a sensor helper libcamera 0.7.2 moves the gain by at least one control unit per update
  (`againMinStep` 1), so linear units give the same proportional steps as on the rear camera; libcamera logs the
  range at stream start: `gain 256-4096 (1)` for the IMX681 and `gain 1-15.5 (0.145)` for the OV13858 (revision 11:
  `gain 0-960 (1)` and `gain 0-63.9922 (0.639922)`).
- State (2026-10-09): the patches apply to `0fdddb4d` and compile without warnings (W=1); the build and the device
  round wait (`build/handoff/camera-quality-2026-10-09/`).

## libcamera

### Fedora's libcamera as it is

- The cameras use Fedora's libcamera as it is (0.7.2-3.fc45): the simple pipeline handles `qcom-camss` with the
  software ISP, whose GPU (EGL) debayering is the default, and `pipewire-plugin-libcamera` brings the cameras to
  desktop applications; `cam` comes with Fedora's `libcamera-tools`, which the live root lacks.
- Sensor data: libcamera knows the OV13858 (gain helper and sensor properties), not the IMX681, whose reciprocal
  gain, 1024 / (1024 - code), code 0 to 960 for 1x to 16x, the software ISP steps as if it were linear.
- Tuning: the one tuning file, `uncalibrated.yaml`, serves all three cameras: a black level from 16 of 255 (the
  IMX681's own pedestal), grey-world white balance, no colour-correction matrix, and an exposure control that aims
  at a mean sample value of 2.5 of five histogram bins and moves exposure and gain by at most 6 % every fourth
  frame, with no digital gain.
- A rebuild of Fedora's libcamera with IMX681 tuning and a faster exposure control was shipped from 2026-09-26 to
  2026-10-02 and dropped as unsustainable: every libcamera release would need its patches rebased (they are in the
  git history). A system that still carries it (`rpm -q libcamera` shows `.sp11.`) goes back with
  `sudo dnf distro-sync 'libcamera*'` and `systemctl --user restart wireplumber pipewire` as the desktop user.

### What the software ISP does (0.7.2)

- One GPU pass per frame (`bayer_1x_packed.frag` for the sensors' packed RAW10): a bilinear demosaic of the 3x3
  neighbourhood around one input pixel, then black level, white-balance gains (the result clipped at 1), the colour
  matrix, the contrast curve and gamma. It reads only the 8 high bits of each sample (the CPU path too), and neither
  path has lens-shading correction, noise reduction, sharpening or defect correction (`software_isp/TODO.md`).
- A stream smaller than the frame is decimated: each output pixel is one demosaic sample (`GL_NEAREST`), so
  1280x720 of the IMX681's frame keeps one neighbourhood in nine and averages nothing (noise, aliasing; the squares
  below).
- Statistics come every fourth frame. The exposure control (`agc.cpp`) aims at a mean sample value of 2.5 of five
  bins with a dead band of 0.2, steps by 0.04 of the error (at most +6 % and -10 % per update), exposure first and
  then gain; white balance is grey world with R and B gains capped at 4; the black level starts at 16 of 255 and is
  only ever lowered, towards the histogram's 2 % point, unless a tuning file sets it.

### Tuning files

- libcamera searches `/etc/libcamera/ipa:/usr/share/libcamera/ipa` (compiled into `libcamera.so`) for
  `simple/<sensor>.yaml` (`imx681.yaml`, `ov13858.yaml`) before it falls back to `uncalibrated.yaml`, and `cam -l`
  logs the fallback ("Configuration file 'imx681.yaml' not found for IPA module 'simple', falling back to ..."). A
  file in `/etc` needs no libcamera rebuild, and `LIBCAMERA_IPA_CONFIG_PATH=<dir>` (looking in `<dir>/simple/`)
  tries one without installing it.
- 0.7.2 reads two keys (`blc.cpp`, `ccm.cpp`): `BlackLevel.blackLevel` (int16 on a 16-bit scale, shifted to 8 bits:
  4096 is 64 at 10 bits) and `Ccm.ccms`, a list of `ct` and a row-major 3x3 `ccm`; Awb, Adjust and Agc read none.
  Ccm interpolates linearly between the two nearest `ct`, clamps outside them, and changes matrix only after the
  colour temperature moves 100 K; that temperature is `estimateCCT()` (libipa `colours.cpp`: a generic RGB-to-XYZ
  matrix and McCamy's formula) of the inverse white-balance gains, so a matrix's `ct` has to be that estimate for
  its light, not the lamp's rating.
- The algorithms rebuild one matrix per frame from the identity, in the file's order: Ccm multiplies its matrix in,
  then Adjust its saturation (BT.601 chroma scaling), whose `Saturation` control exists only when a Ccm is
  configured; the white-balance gains apply before the matrix. The GPU shader multiplies every pixel by the matrix
  anyway, so a configured Ccm costs nothing there.
- The project's files therefore list `version: 1`, then `BlackLevel` (`blackLevel: 4096`), `Awb`, `Ccm`, `Adjust`
  and `Agc`, in that order: step 30 refuses another order or a missing algorithm, step 35 a file without `Ccm`.
- Upstream master (2026-10-06, no release since 0.7.2) renames the IPA `softisp` (tuning files under
  `ipa/softisp/`) and moves Awb, Ccm and the exposure control into libipa with new keys; a pending series adds
  lens-shading correction (17x17 grids per colour temperature, GPU only).

### Colour calibration

- `sp11-camera-probe front|rear --save PATH` keeps ten raw frames of a ColorChecker Classic at 1x in `PATH.raw` and
  describes them in `PATH.json` (exposure halved from the maximum until the brightest green stays below 900, or a
  higher gain in a dim scene); `--dark --save` keeps frames with the lens covered.
- `sp11-camera-calibrate` (standard library only): `preview` draws a capture at one pixel per Bayer quad with a
  100-pixel grid and, given the centres of the corner patches 1, 6, 24 and 19, the squares it samples; `ccm`
  averages the frames over the inner 40 % of each patch, balances on the neutral patches 20 to 22, takes the
  colour temperature as libcamera estimates it, and fits a matrix with rows summing to 1 to the chart's linear
  sRGB with the least mean CIEDE2000 (reference: X-Rite's L*a*b* for charts made after November 2014, through
  Bradford D50 to D65); `evaluate` measures the CIEDE2000 of the chart in a frame `cam -F` wrote. `selftest` checks
  the conversions, CIEDE2000 against Sharma et al.'s data and a synthetic capture through the whole fit.
- What a calibration needs: a ColorChecker Classic (full size or Mini) made after November 2014, daylight without
  sun on the chart, the chart filling a third to half of the picture and no window or lamp in it (the capture's
  exposure follows the brightest green of the whole frame), and a `--dark` capture per camera; a second capture
  under a warm lamp gives a second `ct`. `ccm` prints the `Ccm` block, which goes between `Awb` and `Adjust` of the
  layout above; the black level stays 4096 while the dark capture reads 62 to 66 at 10 bits.
- Trying files before packaging them: `LIBCAMERA_IPA_CONFIG_PATH=<dir> cam ...`; for the desktop applications
  `systemctl --user set-environment LIBCAMERA_IPA_CONFIG_PATH=<dir>` and a restart of `wireplumber` and `pipewire`,
  undone with `unset-environment`, since the variable is searched before `/etc`.
- State (2026-10-09): no capture made yet. `payload/camera/imx681.yaml` and `ov13858.yaml` come from it; until they
  exist step 30 stops every support RPM build on this branch (`missing .../imx681.yaml`), so it can reach `main`
  only with them. The device steps: `build/handoff/camera-quality-2026-10-09/camera-quality-steps.md`.

### The GPU debayering: squares in dark pictures, the metering area

- Squares: for a stream smaller than the sensor's frame the GPU debayering (`debayer_egl.cpp`,
  `bayer_1x_packed.frag`) scales the frame by the output over the native size (0.501 for 1920x1080 of the IMX681's
  3840x2640) and interpolates each output pixel around the one input pixel it lands on, whose Bayer position
  changes every 240 output pixels, so a dark, noisy picture shows a chessboard of faintly coloured 240-pixel
  squares. Taking the whole 2x2 quad per output pixel removes them; Fedora's build and upstream's
  pending patch keep the scale.
- The metering area: `DebayerEGL` gives the statistics a window without its offset
  (`setWindow(Rectangle(window_.size()))`) and hands over the whole frame (`processFrame(frame, 0, ...)`), so
  exposure and white balance meter an area of the stream's size at the raw frame's top-left corner, the picture's
  top-left quarter for 1920x1080 of the IMX681's frame; from 0.7.2's code, not measured on the device.

### IPA signatures and device access

- Fedora's spec re-signs `libcamera/ipa_*.so` after stripping but installs the modules in `libcamera/ipa/`, so the
  shipped signatures do not verify against the key in `libcamera.so` and libcamera runs each IPA isolated in a
  process of its own.
- PipeWire runs libcamera as the desktop user: `70-uaccess.rules` hands the seat user every `video4linux` and
  `media` node and `/dev/udmabuf`, `70-libcamera.rules` gives `/dev/dma_heap` to the `video` group only, so
  libcamera allocates from `/dev/udmabuf`; since systemd 262 udev also creates a `/dev/media` directory next to
  `/dev/media0`, scripts take the media devices as `/dev/media[0-9]*` (`sp11-camera-probe`, `sp11-diag` since
  support 3.4).

### How PipeWire holds a camera

- In libcamera 0.7.2 and pipewire-plugin-libcamera 1.6.9 the simple pipeline keeps the camera's video node and
  subdevices open for PipeWire's life; the plugin (`spa/plugins/libcamera/libcamera-source.cpp`) acquires and
  configures a camera when a stream's format is set, starts it on Start, stops it on Pause or Suspend, and releases
  it only when the format is cleared with the application's stream.
- The busy error: `Camera::start()` fails with `EACCES` unless the camera is in its configured state and the plugin
  reports that as `EBUSY`, so PipeWire's `running -> error (error changing node state: Device or resource busy)`
  means a start the camera's state did not allow, not a device another process holds.
- CAMSS's video nodes call `v4l2_pipeline_pm_get()` on open and the driver registers
  `v4l2_pipeline_link_notify()`, so once the links are enabled the CSIPHY, CSID and VFE subdevices keep their
  runtime-PM reference between streams while PipeWire runs, and system sleep only drops and restores CAMSS's
  interconnect votes; whether a camera held this way comes back after a sleep is not known.

### The IR camera

- The software ISP has no monochrome path in 0.7.2, so libcamera offers the VD55G0 only as a raw stream, which
  ordinary applications cannot use; face login would need Howdy and a bridge, which Fedora does not package.

## On the device

### What works

- Recorded in `docs/verified.md`: the three sensors bind, the CDSP answers and no provider waits for `sync_state`;
  the front and the rear camera stream in GNOME Snapshot, Firefox and KDE Plasma, also after suspend and resume,
  with the front camera's light on (`white:camera-indicator` reads 1), last with revision 10 on Fedora's build;
  GNOME Snapshot leaves the IR camera out (`IR Camera ignored: vd55g0`).
- `cam -l` lists `Internal front camera`, `Internal back camera` and `'vd55g0'`, and logs
  `Failed to create camera sensor helper` for the IMX681 and the VD55G0; the simple pipeline takes the smallest
  sensor mode that covers the stream, the rear camera's 2112x1188 for GNOME Snapshot and 4224x3136 for `cam`
  without a stream size, and the IR camera runs at 320x240 8-bit, about 59 fps.

### Brightness

- Dark, grey pictures come from dim rooms, not the sensors: the front camera gives roughly 0.5 steps (of 959 above
  black) per lux of the light sensor at full exposure (33 ms) and 1x, so a room of about 100 lux needs a few times
  gain, below about 10 lux even the IMX681's 16x leaves the picture dark and noisy, and the exposure control's
  target of 2.5 of 5 bins needs about 50 lux at full exposure and 16x.
- The simple pipeline keeps the sensor's 30 fps timing and has no frame-duration control, so the exposure ends at
  33 ms, and the software ISP has no noise reduction; at the control's 6 % steps the gain takes about 6 s from 1x to
  16x where libcamera knows the sensor's gain (the rear camera), while the front camera's raw gain code moves one
  code per update (revision 12 changes both gains, Kernel above); colours stay muted without a colour-correction
  matrix (Colour calibration).
- The rear camera's gain ceiling: the OV13858 applies no analogue gain above 15.5x
  (`sp11-camera-probe rear --gain-range`) while its driver offers codes up to 0x1fff (64x in libcamera's helper),
  so in the dark the exposure control steps through codes that do nothing.

### The raw-capture probe

- `payload/camera/sp11-camera-probe` (`sudo python3`, every camera application closed) measures the raw sensor
  output without libcamera: it routes the sensor to the RDI video node with `media-ctl`, sets fixed exposures and
  gains with `v4l2-ctl` and prints per-channel levels in 10-bit units and the signal ratios between the settings
  (about 4, 16 and 0.5 when the sensor applies its controls).
- `--dark` with the lens covered gives the black level and the noise; `--frame-length` runs the default and two
  longer frames (front 3554, 5331 and 7108 lines, rear 3214, 4821 and 6428) and prints the frame rate and level
  against a sensor that takes the frame length; `--gain-range` steps the gain (rear up to code 8191, front up to
  16x) and prints each step's level against what it asks for. The frames are deleted once measured and the sensor's
  default blanking, exposure and gain restored, since libcamera does not set the blanking itself.

### Cameras stopping until PipeWire is restarted (open)

- Reported on 2026-10-07 from the KDE Plasma installation: after a while, which fits a sleep, the cameras stop until
  PipeWire and WirePlumber are restarted; not captured yet. The only related record, from GNOME: PipeWire's
  front-camera node hit the busy error (How PipeWire holds a camera) right after a resume and recovered 30 s later
  by itself, with no camera message in the kernel log.
- The capture (`build/handoff/sp11-libssc-3-2026-10-07`, Part B) collects, before the restart, the kernel's camera
  lines, PipeWire's and WirePlumber's log, the camera nodes, the camera blocks' runtime-PM state and `cam -C 5` on
  both cameras from a second process: a frame capture there puts the fault in PipeWire's node, an acquire failure
  means PipeWire still holds the camera, any other error points at the kernel's camera path after the sleep.

## History

- 2026-09-14: the front camera enumerated on ooaklee's v23 kernel with Fedora's libcamera.
- 2026-09-23: the camera stack left out of the Fedora-based kernel, its picture on v23.2 far too dark.
- 2026-09-26: revision 6 streams both cameras, dark and unlit; revision 7 and the probe.
- 2026-09-27: the probe explains the dark pictures, the frame length and the squares; revision 8.
- 2026-09-28: revisions 8 and 9 confirmed.
- 2026-10-03: Fedora's libcamera checked with revision 10.
- 2026-10-07: the cameras stopping until PipeWire is restarted reported (open); the capture handed over.
- 2026-10-09: the colour calibration prepared (tools, support 3.5's packaging) and revision 12's gain patches; both
  wait for the device.
