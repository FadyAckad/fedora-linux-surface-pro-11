# Cameras
The three cameras: the kernel side the SP11 patch set carries since revision 6, libcamera rebuilt for the front
camera's sensor, what the host checks prove and what only the device can show.

## Hardware

- Three camera modules, as turbineBMW's Denali device tree describes them (turbineBMW/surface-pro-11-linux; they
  captured frames from all three on their unit), all three bound and streaming on the tested unit: the front camera,
  a Sony IMX681 (3840x2640 RAW10, one C-PHY trio at 2406 Msym/s) on CCI1 bus 1 at `0x1a` and CAMSS port 2 (CSIPHY2);
  the rear camera, an OmniVision OV13858 (4224x3136 RAW10, four D-PHY lanes) on CCI0 bus 1 at `0x10` and port 1; the
  IR camera, an ST VD55G0 (644x604 `Y10P`, one D-PHY lane) on CCI0 bus 0 at `0x60` and port 0, lit by the PM8550
  flash controller's current sinks 1 and 4 (600 mA ceiling). The PM8010 camera PMIC supplies the modules. ooaklee's
  v23 described only the front camera, at `0x10`, with a separate CSI PHY driver and a privacy LED on TLMM GPIO 225
  whose polarity it marked as unvalidated; turbineBMW's tree has no privacy LED.
- The front camera's light: Windows' camera platform device `CAMP` (`QCOM0C32`, subsystem `MSHW0495`; DSDT from
  `HKLM\HARDWARE\ACPI\DSDT`, decompiled with `iasl`) holds two GPIO outputs of the TLMM, 225 and 105, and mainline's
  Denali tree already names GPIO 225 `cam_indicator_en` (a pin state no node used). Without an LED node the light
  stays off while the front camera streams (revision 6); the rear camera's light comes on by itself. Pin 105 is CCI1
  bus 0's SDA pin on Linux (unused there); what Windows drives through it is not known. On revision 7 pins 105 and
  106 sit in the CCI function with pull-up (input, high), and the light sensor and the cameras work. Revision 7
  (0071) describes the light as a GPIO LED on pin 225, active high (the ACPI resource states no polarity; confirmed
  on the device), and gives it to the IMX681 as its `privacy` LED: `v4l2_async_register_subdev_sensor()`, which the
  IMX681 driver uses, takes the LED, switches it off, and locks its sysfs control (a write returns `EBUSY`); the
  V4L2 core then lights it while the sensor streams. Step 20 checks the link in the built device tree.

## Kernel

- Mainline 7.2 has CAMSS for the X1E80100 (D-PHY only), the camera clock controller (`camcc-x1e80100`) and the CCI
  driver, and Fedora builds them (`VIDEO_QCOM_CAMSS`, `I2C_QCOM_CCI`, `CLK_X1E80100_CAMCC`, also `VIDEO_OV13858` and
  `LEDS_QCOM_FLASH`). Missing, and not upstream by the 7.3 merge window (turbineBMW's port notes): CAMSS C-PHY, the
  camera nodes of `hamoa.dtsi` (7.3 brings the clock controller's), the Denali board nodes, the IMX681 and VD55G0
  drivers. Revision 6 carries them as the patches 0059–0070 (`docs/kernel-patches.md`): turbineBMW's reviewed camera
  branch, their OV13858 retry of the first register write after power-up, and ooaklee's IMX681 exposure fix;
  `kernel-local` adds `VIDEO_IMX681=m` and `VIDEO_VD55G0=m`. In revision 6 every driver file equalled the one in
  turbineBMW's 7.3 port, their daily kernel; revision 8 changes the IMX681's (0072), revision 9 the OV13858's and
  the IMX681's (0073, 0074).
- Fedora's `patch-7.2-redhat.patch` adds a Sony IMX471 driver at the IMX681's alphabetical place in
  `drivers/media/i2c/Kconfig` and `Makefile`; kernel.spec's `git apply` refused turbineBMW's hunks there (the first
  build of revision 6 stopped in `%prep`), so the IMX681 entries follow the MAX9271 library entry instead. Fedora's
  patch also touches `MAINTAINERS`, in other places.
- Up to revision 7 the IMX681 driver of the series was byte-identical to the one in ooaklee's v23, which already
  wrote the exposure through the 24-bit register (ooaklee's fix of 2026-08-29); v23.2's dark picture was not a
  sensor-driver difference.
- Up to revision 7 the IMX681 driver wrote the frame length (height plus vertical blanking) to the standard 16-bit
  register `0x0340`, which the sensor ignores: the mode table recorded from Windows never writes it, and sets a
  24-bit frame length at `0x033d` (3554 lines) and the exposure at `0x0229` (3546, the frame length less 8), the
  register the exposure fix moved to after `0x0202` showed no effect. Measured with
  `sp11-camera-probe front --frame-length` (2026-09-27): the sensor keeps 3554 lines at 30 fps, a line of 9.38 us
  (6752 clocks at 720 MHz), where the driver assumes 2708 lines of 12.3 us; it takes exposures within its own frame
  beyond the driver's maximum (3506 lines at 30 fps, the level x1.33), and lengthens the frame to the exposure plus
  8 lines past it (5368 lines ran at 19.84 fps). So that driver left a quarter of each frame's exposure unused (2660
  of 3546 lines), and its vertical blanking changed nothing below that. Revision 8 (0072) writes `0x033d` (24 bits),
  starts from 3554 lines and keeps them as the shortest frame, lets the exposure reach the frame length less 8 lines
  (3546 at 30 fps), and reports the line as 5144 pixels of the 548.57 MHz CSI-2 pixel rate, so the frame duration
  libcamera derives is the sensor's. Confirmed on the device (2026-09-28): at 3554, 5331 and 7108 lines the camera
  runs at 30.01, 20.00 and 15.00 fps also at a short exposure (886 lines), which only a frame length the sensor
  takes can lower (`sp11-camera-probe front --frame-length`).
- Revision 9 (2026-09-28, two fixes from a review): the Surface Pro 11 mode put its 592.8 MHz link frequency first
  in the OV13858 driver's menu, and the pixel rate's minimum, which the driver took from the menu's second entry,
  became 432 instead of 216 MHz. In the 270 MHz modes, among them the 2112x1188 mode GNOME Snapshot gets, the
  driver's 216 MHz was clamped to 432 MHz, so libcamera took a line for 5.19 instead of 10.39 us and reported half
  the exposure time, and CAMSS chose its VFE clock for twice the rate; 0073 takes the minimum from the lowest link
  frequency. The full 4224x3136 mode (540 MHz, 432 MHz), which `cam` takes without a stream size, was right before.
  libcamera 0.7.2 uses the pixel rate only for that line time and the line time only for the `ExposureTime`
  metadata; the exposure control and `payload/camera/` count exposure lines and gain codes, so the picture does not
  change and the libcamera rebuild needs none. 0074 applies the IMX681's controls at stream start under the control
  handler's lock, which `__v4l2_ctrl_handler_setup()` expected and `.s_stream` does not hold. On the device
  (`docs/verified.md`) the 2112x1188 mode reports 216 MHz and a full exposure of 33.3 ms at 29.95 fps, and both
  cameras work as before in GNOME Snapshot.
- The camera nodes add two users of the providers that must reach `sync_state` (`docs/kernel.md`): the camera clock
  controller votes on the RPMh power domains, CAMSS on the interconnect (the CCI buses use the clock controller's
  own power domain). Step 20's check finds a driver for both in Fedora's packages; whether they bind only the
  device shows (`sp11-diag`'s sync line).

## libcamera

- Fedora 45 ships libcamera 0.7.2-3.fc45: the simple pipeline handles `qcom-camss` with the software ISP, whose
  GPU (EGL) debayering is built in and the default, and `pipewire-plugin-libcamera` brings the cameras to desktop
  applications. It knows the OV13858 (gain helper and sensor properties), not the IMX681. Without IMX681 data the
  software ISP's exposure control steps the sensor's analogue gain code as if it were linear (the IMX681's gain is
  reciprocal, 1024 / (1024 - code), code 0 to 960 for 1x to 16x) and uses default control delays. Its black level
  starts at 16 of 255, the IMX681's own pedestal (64 at 10 bits), so the black level did not darken v23.2's picture.
- Step 47 rebuilds Fedora's source RPM with `payload/camera/`: turbineBMW's three IMX681 patches (sensor properties,
  gain and black-level helper, the software ISP's tuning file), rebased from 0.7.1 onto 0.7.2, which adds the Sony
  IMX678 at the same places; the added lines are unchanged. On 0.7.1 the patches give turbineBMW's published tree
  (`d27c3bd9`). The release is Fedora's plus `LIBCAMERA_RPM_SUFFIX` (0.7.2-3.sp11.1.fc45). turbineBMW's own system
  runs the distribution's 0.7.2 with only the tuning file.
- Exposure control, since 0.7.2-3.sp11.2 (2026-09-27): `payload/camera/` 0004 is patch 5/7 of Robert Bozik's
  software ISP series (libcamera-devel, 2026-08-26, patchwork 28101; declined upstream under libcamera's policy on
  AI-assisted contributions), backported from master's `src/ipa/softisp` to 0.7.2's `src/ipa/simple` without the
  vertical blanking of his patch 3/7. Far from the target (an MSV error above 0.5) the AGC jumps by the ratio of
  target to measured MSV, at most 2x per statistics period, instead of 0.7.2's 6 % at most; once exposure and
  analogue gain are at their maximum it adds digital gain in the ISP (the colour gains, after black-level
  subtraction), bounded by the Agc tuning key `maxDigitalGain` (default 1, off) and reported as `DigitalGain`; the
  MSV is taken from the histogram scaled by the frame's digital gain. The gain multiplies what `Awb` sets each
  frame, so a tuning file must list `Awb` before `Agc` (all three of ours do). 0005 (this project) adds the Agc key
  `maxAnalogueGain`, which bounds the AGC's analogue gain where a driver's control goes beyond the sensor's gain
  (the OV13858 driver's goes to code 0x1fff, 64x in libcamera's helper) and scales the minimum gain step with the
  range. 0006 sets `maxDigitalGain: 4.0` in `imx681.yaml` and adds `ov13858.yaml` (black level 4096, the same
  digital gain, and since sp11.3 `maxAnalogueGain: 15.5`, where `sp11-camera-probe rear --gain-range` found the
  OV13858's gain stops). Our own patches carry no author line (`payload/` names no one); the three from turbineBMW
  and Bozik's keep theirs. On the device (0.7.2-3.sp11.3, revision 8, 1 lux): each camera reached its maximum
  exposure, analogue gain and 4x digital gain about 0.9 s after the first adjustment. The target itself, a mean
  sample value of 2.5 of the five bins, puts the linear image's mean at about 40 % of full scale: a daylight photo
  with the front camera averaged 169 of 255 after the gamma curve, with most of a face at 245 or above. Since
  0.7.2-3.sp11.4, 0008 (this project) reads the target from the Agc key `exposureTarget` (default 2.5; logged as
  `Exposure target ... by the tuning file`; up to sp11.5 a value of 1 or less fell back to 2.5, since sp11.6 a value
  outside 1.3 to 5 is clamped to that range with a warning). On the device (2026-09-28) the owner compared 1.0, 1.4,
  1.6 and 1.8 on the front camera in daylight and chose 1.4, about a stop darker than the default. A target that low
  sits at most 0.4 above the MSV's floor of 1, below the large-error threshold, so a dark scene would only converge
  by the small proportional steps (half a minute in a simulation of a dim room); since sp11.5 the thresholds and the
  proportional gain scale with the target, and the ratio is squared when brightening from far below it (dim to
  daylight scenes settled in about 1 to 5 s in the simulation, without oscillating). Both tuning files set 1.4 since
  sp11.5; the rear camera's value is the front camera's. On the device with sp11.5: a dark spot's maximum in 1.2 s
  (1.96x steps), and both cameras right in daylight and settling within seconds in dim light (owner, 2026-09-28).
- Upstream after 0.7.2 (master, 2026-07): the simple IPA moved to `src/ipa/softisp` (module `ipa_softisp.so`, tuning
  files under `ipa/softisp`) and its AGC into libipa (`AgcAlgorithm`, `agc_msv`). A release with those changes
  cannot take 0004, 0005 and 0008 by rebase: they have to be ported onto the new AGC, and steps 47 and 48 name the
  old module, directory and tuning keys.
- The analogue gain code (2026-09-28, found in a review and reproduced with the skill's `agc-model.py`; not seen on
  the device): up to sp11.5 the IMX681 got the gain code `CameraSensorHelper::gainCode()` truncates, and the IPA
  reads that code's gain back. Above about 12.4x one code is worth more than the AGC's smallest step (0.15) and than
  a proportional step, so while the MSV is in the proportional band (1.12 to 1.29 at target 1.4) the analogue gain
  could stop between 12.3x and 15.75x and never reach 16x, where the digital gain starts. In the model, scenes of
  about 12 to 17 lux settled at an MSV of 1.19 to 1.22 instead of about 1.3, up to 0.4 stop darker than intended;
  the rear camera's code/128 gain is not affected. Since 0.7.2-3.sp11.6, 0009 (this project) sets the code whose
  gain is nearest to the requested one (`IPASoftSimple::gainCode()`): half a code is at most 0.125 up to 16x, below
  the smallest step, and in the model the same scenes reach 16x and digital gain (MSV 1.29 to 1.33, within 3 to 6
  s), the other scenes unchanged. On the device (sp11.6, 2026-09-28) it behaves as sp11.5 in a 1 lux spot (every
  limit reached, the brightness statistic at 1.077); a scene in the band was not tried. Targets below about 1.25
  never reach the large-error branch from a dark start, and at about 1.09 or less an MSV of 1 counts as on target:
  the exposure then brightens slowly or not at all (1.05 and 1.2 in the model); since sp11.6, 0008 clamps the target
  to 1.3 to 5.
- Flat scenes (2026-09-28, found in a review of sp11.6 and reproduced with the skill's
  `agc-model.py --lux 300 2000 --contrast 0.02 0.05 0.1`; not seen on the device): when every sample falls into one
  of the five bins, as with a blank wall or a sheet of paper filling the picture, the MSV is a whole number, and
  with the target at 1.4 none lies within 0.28 of it, the band in which 0008 corrects by small steps: the exposure
  then alternates between jumps of about 1.96x up and 0.7x down instead of settling, and the picture pumps. No
  target from about 1.25 to 1.67 has a whole number in its band; at the default 2.5 such a scene moves by steps of
  2 %. In the model, scenes with a spread of 0.05 or less never settle at 1.4 (both cameras, 300 and 2000 lux), 0.1
  only at 2000 lux; the standard scenes (spreads of 0.3 to 1.0) settle as before.
- The metering area (2026-09-28, libcamera 0.7.2's code, found in a review; not measured on the device): with the
  GPU debayering and a stream smaller than the sensor's, the statistics the exposure control and the white balance
  use cover an area of the stream's size at the raw frame's top-left corner, not the picture. `DebayerEGL` gives the
  statistics a window without its offset (`setWindow(Rectangle(window_.size()))`) and hands over the whole frame
  (`processFrame(frame, 0, ...)`), while the CPU debayering passes each line from inside its window. For 1920x1080
  of the IMX681's frame that is the picture's top-left quarter, so exposure and colour follow whatever is there.
  Unchanged on libcamera's master of 2026-09-15.
- Squares in dark pictures (2026-09-27): the GPU debayering (`debayer_egl.cpp`, `bayer_1x_packed.frag`) draws a
  downscaled stream by scaling the frame by the output size over the native size (1920/3832 = 0.501 for 1920x1080 of
  the 3840x2640 IMX681 frame, uniformly, cropping the rest) with the viewport at the input size, and each output
  pixel interpolates around the one input pixel it lands on. The Bayer position it lands on drifts by 0.004 pixels
  per output pixel and changes every 240 output pixels in both directions. Each position gives a different colour
  once the black-level subtraction clips the noise, so a dark, noisy picture shows a chessboard of faintly coloured
  240-pixel squares aligned to the frame's corner; bright pictures do not. The CPU debayering crops instead of
  scaling. Reproduced with libcamera 0.7.2's own shaders under Mesa's llvmpipe in a mock chroot, set up as
  `DebayerEGL` does: squares 4 levels apart in a flat, dark, noisy frame. Taking the whole 2x2 quad (red, blue, mean
  green) per output pixel when downscaled removes them (0.6 levels, the noise) and renders a smooth scene within one
  level of the interpolating path for RGGB and GRBG. Upstream has no fix (2026-09-27; a pending patch centres the
  crop but keeps the scale). Since 0.7.2-3.sp11.3 `payload/camera/` 0007 (this project) does that: the packed
  shader's `quad_rgb()`, enabled by the uniform `quad` when the scale is below three quarters, so full-size output
  keeps the interpolating path (bit-identical in the test with `quad` off). Step 47 checks the function in
  `libcamera.so`. Confirmed on the device (2026-09-28): no squares in a dark picture. Between half and three
  quarters of the native size there are fewer quads than output pixels, so neighbouring output pixels can show the
  same quad (the rear camera's 2112x1188 mode at 1280x720, for example), a slightly coarser picture than the
  interpolating path's; computed from the shader's mapping, not seen on the device.
- IPA signatures: Fedora's spec re-signs `libcamera/ipa_*.so` after stripping, but installs the modules in
  `libcamera/ipa/`, so the signatures it ships are those of the unstripped modules and do not verify against the key
  built into `libcamera.so` (0.7.2-3.fc45, checked with `openssl`); libcamera then runs each IPA isolated in a
  process of its own. The template re-signs in `libcamera/ipa/`; steps 47 and 48 verify every signature.
- Step 47's first build (2026-09-26) took about four minutes in its mock root. rpmbuild's "File listed twice"
  warning for the build-id link of `v4l2-compat.so` comes from Fedora's `%files` (its own `libcamera-ipa` carries
  the same link as `libcamera-v4l2`).
- Device access: PipeWire runs libcamera as the desktop user. Fedora's `70-uaccess.rules` hands the seat user every
  `video4linux` node (the subdevices included), every `media` node and `/dev/udmabuf`; `70-libcamera.rules` gives
  `/dev/dma_heap` to the `video` group only, so libcamera allocates its buffers from `/dev/udmabuf` instead.
- The IR camera: the software ISP has no monochrome path in 0.7.2, so libcamera can offer the VD55G0 only as a raw
  stream, which ordinary applications cannot use. Face login would need Howdy and a bridge of its own (turbineBMW
  tested one), none of which Fedora packages.
- The ISO: since 2026-09-28 step 50 installs the rebuild into the live root in place of Fedora's build (`libcamera`,
  `libcamera-ipa` and `libcamera-tools`, and the rebuild of any other libcamera subpackage the root carries), so the
  installer's copy of the live root gives it to the installed system, and `/sp11/rpms` carries the three. Earlier
  ISOs carry Fedora's build.
- Not pinned against Fedora's updates: a Fedora libcamera update replaces the build, and the cameras fall back to
  Fedora's behaviour (no IMX681 gain helper or tuning, the slow exposure control without digital gain, the squares,
  the default target) until the rebuild is redone for the new version: the build keeps the source RPM pinned in
  `sp11.conf` (`LIBCAMERA_SRPM`, since 2026-09-28; before, step 10 took the newest one) until the pin moves to the
  new build, step 47 then asks for the template's refresh and the new `LIBCAMERA_BASE_SPEC_SHA256`, and a new
  libcamera version needs the patches rebased or ported (`.claude/skills/sp11-camera-update`). Rerunning step 47
  alone rebuilds the old version, which dnf does not install over Fedora's newer one. An exclusion like
  iio-sensor-proxy's would also hold back PipeWire's plugin once Fedora bumps libcamera's soname.

## On the device

- The round of 2026-09-26 (`docs/verified.md`): the three sensors bind, the CDSP answers and no provider waits for
  `sync_state`, the front and the rear camera stream in GNOME Snapshot and in Firefox, also after a suspend and
  resume (rechecked on 2026-09-28 with revision 8 and 0.7.2-3.sp11.6, also after reboots). `cam -l` lists
  `Internal front camera`, `Internal back camera` and `'vd55g0'` (the VD55G0 driver has no orientation control);
  libcamera runs the rear camera in its 2112x1188 mode for GNOME Snapshot (the software ISP's
  `Input 2112x1188-GRBG-10-CSI2P`) and in its full 4224x3136 mode for `cam` without a stream size, since the simple
  pipeline takes the smallest sensor mode that covers the stream; the IR camera at 320x240 8-bit, about 59 fps.
  GNOME Snapshot leaves the IR camera out by itself (`IR Camera ignored: vd55g0`). The rebuild's markers as
  expected: `signature is valid`, `Using tuning file .../imx681.yaml`, `gain 1-16 (0.15)` (Fedora's build:
  `not valid`, `uncalibrated.yaml`, `gain 0-960 (1)`). The OV13858 retry recovered one CCI queue timeout, when
  Snapshot switched from the front to the rear camera.
- Brightness (2026-09-26 and 2026-09-27): the dark, grey picture of the first round came from dim rooms; the sensors
  are fine. In those captures the software ISP's brightness statistic (`exposureMSV`) stayed at 1 (all pixels in the
  darkest fifth) with the exposure at its maximum while the gain rose (Fedora's libcamera one raw code per update,
  the rebuild to 5x on the front, about 30x on the rear camera), and the light sensor read 0 lux.
  `sp11-camera-probe` then found the raw frames of a lamp-lit evening room almost empty: 0.4 steps of 959 above the
  covered-lens level on the front camera at full exposure (33 ms) and 1x, 7.1 at 16x; 0.1 and 11.3 on the rear
  camera at 1x and 15.5x; exposure and gain act as set (half the exposure, half the signal). Facing a daylit window
  (light sensor 2,700 to 2,800 lux) the front camera clipped 44 % of its green pixels at full exposure and 1x and
  still read 3.8 steps at its shortest exposure (8 lines); the rear camera, turned to a bright scene, clipped 36 %.
  Scaled from the shortest exposure, the front camera gives roughly 0.5 steps per lux of the light sensor at full
  exposure and 1x: a room of about 100 lux needs a few times gain, and below about 10 lux even the IMX681's 16x
  leaves the picture dark and noisy. libcamera's simple pipeline keeps the sensor's 30 fps timing (it has no
  frame-duration control, so the exposure ends at 33 ms), its software ISP has no noise reduction, and the exposure
  control of Fedora's 0.7.2 and of sp11.1 adds no digital gain and moves exposure and gain by at most 6 % per
  statistics period, which is every fourth frame: from 1x to 16x takes about 6 s (in the first round the front
  camera was at 5.2x after 3 s). Its target, a mean sample value of 2.5 of 5 histogram bins, needs about 50 lux of
  the light sensor at full exposure and 16x.
- The OV13858 applies no analogue gain above 15.5x (`sp11-camera-probe rear --gain-range`, 2026-09-27: the level
  x1.00 from 15.5x to 31x and to 64x), while its driver offers codes up to 0x1fff (64x in libcamera's helper): the
  rear camera's exposure control reaches its digital gain only with `maxAnalogueGain: 15.5` in `ov13858.yaml`, which
  0006 sets since 0.7.2-3.sp11.3.
- Colours: both tuning files run grey-world white balance without a colour-correction matrix (`imx681.yaml` and,
  since sp11.2, `ov13858.yaml`: black level 4096 at 16 bits, `Awb`, `Adjust`, `Agc`; the IR camera
  `uncalibrated.yaml`), so colours stay muted; a matrix needs a colour-chart measurement.
- `payload/camera/sp11-camera-probe` (run with `sudo python3`) measures the raw sensor output: it routes the sensor
  to the RDI video node with `media-ctl` (sensor, CSIPHY, `msm_csid0`, `msm_vfe0_rdi0`), sets fixed exposures and
  analogue gains on the sensor with `v4l2-ctl`, captures six frames per setting and prints per-channel levels of the
  last one in 10-bit units, and the signal ratios between the gains and between full and half exposure, which a
  sensor that applies its controls shows as about 4, 16 and 0.5; `--dark` with the lens covered gives the black
  level and the noise. `--frame-length` lengthens the frame through the vertical blanking (the default and two
  longer ones: front 3554, 5331 and 7108 lines on revision 8, rear 3214, 4821 and 6428), each at its maximum
  exposure and one gain picked so that the longest frame does not clip, and prints the frame rate and the level
  against what a sensor that takes the frame length gives; `--gain-range` steps the analogue gain (rear up to code
  8191, front up to 16x) at one exposure picked so that the highest step does not clip, and prints each step's level
  against what the gain asks for. The frames are deleted as soon as they are measured; the sensor's default
  blanking, exposure and gain are restored at the end (libcamera does not set the blanking itself). Tested on the
  host against simulated tools and sensors (frame length taken or ignored, gain stopping at 15.5x or not).
- Revision 7's light: it comes on while the front camera streams (owner, 2026-09-27); `white:camera-indicator` reads
  0, 1 while `cam` streams, 0 after, and a write during the stream fails (`Device or resource busy`).

## History

2026-09-14: the front camera enumerated on ooaklee's v23 kernel with Fedora's stock libcamera; a libcamera rebuild
was planned and not carried out. 2026-09-23: the camera stack left out of the Fedora-based kernel, because its
picture on v23.2 was far too dark. 2026-09-26: kernel revision 6 with turbineBMW's camera branch and libcamera
0.7.2-3.sp11.1 built and verified on the host; on the device both cameras stream, with a dark, washed-out picture
and without the front camera's light. The same day kernel revision 7 (the light) and the raw-capture probe; on the
device the light works, and the raw frames showed the dark picture was the room's (2026-09-27). The same day
libcamera 0.7.2-3.sp11.2 (faster exposure control, digital gain, the rear camera's tuning) and the probe's
frame-length and gain-range measurements; on the device the frame length the driver wrote was ignored, the rear gain
stopped at 15.5x, and dark pictures showed coloured squares. The same day kernel revision 8 (the frame length) and
sp11.3 (the squares, the rear gain bound); on the device both confirmed, and the exposure too bright in daylight
(2026-09-28). The same day sp11.4 (the exposure target from the tuning file); the owner chose 1.4, which sp11.5 sets
for both cameras, with the exposure control's thresholds scaled to it; confirmed on the device. The same day the ISO
with the rebuild, and sp11.6 (the nearest gain code and the target's bounds, after a review), both built and handed
over.
