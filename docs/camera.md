# Cameras
The three cameras: the kernel side the SP11 patch set carries since revision 6, Fedora's libcamera, and what only
the device can show.

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
  metadata; its exposure control counts exposure lines and gain codes, so the picture does not change. 0074 applies
  the IMX681's controls at stream start under the control handler's lock, which `__v4l2_ctrl_handler_setup()`
  expected and `.s_stream` does not hold. On the device (`docs/verified.md`) the 2112x1188 mode reports 216 MHz and
  a full exposure of 33.3 ms at 29.95 fps, and both cameras work as before in GNOME Snapshot.
- The camera nodes add two users of the providers that must reach `sync_state` (`docs/kernel.md`): the camera clock
  controller votes on the RPMh power domains, CAMSS on the interconnect (the CCI buses use the clock controller's
  own power domain). Step 20's check finds a driver for both in Fedora's packages; whether they bind only the
  device shows (`sp11-diag`'s sync line).

## libcamera

- The cameras use Fedora's libcamera as it is (0.7.2-3.fc45 in Fedora 45): the simple pipeline handles `qcom-camss`
  with the software ISP, whose GPU (EGL) debayering is built in and the default, and `pipewire-plugin-libcamera`
  brings the cameras to desktop applications. It knows the OV13858 (gain helper and sensor properties), not the
  IMX681. Without IMX681 data the software ISP's exposure control steps the sensor's analogue gain code as if it
  were linear (the IMX681's gain is reciprocal, 1024 / (1024 - code), code 0 to 960 for 1x to 16x) and uses default
  control delays. Its black level starts at 16 of 255, the IMX681's own pedestal (64 at 10 bits), so the black level
  did not darken v23.2's picture. Its one tuning file for the software ISP, `uncalibrated.yaml` (black level,
  grey-world white balance, adjustments, exposure control; no colour-correction matrix), serves all three cameras.
  The exposure control aims at a mean sample value of 2.5 of five histogram bins, moves exposure and gain by at most
  6 % per statistics period (every fourth frame) and adds no digital gain.
- The rebuild (2026-09-26 to 2026-10-02): step 47 rebuilt Fedora's source RPM with turbineBMW's IMX681 support
  (sensor properties, gain and black-level helper, tuning file), Robert Bozik's faster exposure control with digital
  gain (libcamera-devel patchwork 28101, declined upstream under libcamera's policy on AI-assisted contributions),
  and the project's tuning and fixes (the rear camera's gain bound at 15.5x, an exposure target of 1.4 chosen on the
  device, the sensor's nearest gain code, whole-quad GPU downscaling); step 50 installed it in place of Fedora's
  build. On the device both cameras then reached their limits within about a second in a dark spot, settled within
  seconds in dim light and were right in daylight (owner, 2026-09-28). Dropped on 2026-10-02 by the owner as
  unsustainable for little gain: every libcamera release needs the patches rebased, and after 0.7.2 upstream moved
  the simple IPA to `src/ipa/softisp` and its exposure control into libipa, so the exposure patches would have had
  to be ported. The patches are in the git history (`payload/camera/`, `rpm/libcamera.spec.in`).
- A system with the rebuild (installed from an ISO built from 2026-09-28 to 2026-10-02, or from a device round's
  RPMs) keeps it: `0.7.2-3.sp11.6` sorts above Fedora's `0.7.2-3`, so `dnf upgrade` replaces it only once Fedora
  ships a newer libcamera. `sudo dnf distro-sync 'libcamera*'` installs Fedora's build of the same version instead
  (on the device on 2026-10-03; first tried with test packages on the host, 2026-09-28).
- Squares in dark pictures (2026-09-27): the GPU debayering (`debayer_egl.cpp`, `bayer_1x_packed.frag`) draws a
  downscaled stream by scaling the frame by the output size over the native size (1920/3832 = 0.501 for 1920x1080 of
  the 3840x2640 IMX681 frame, uniformly, cropping the rest) with the viewport at the input size, and each output
  pixel interpolates around the one input pixel it lands on. The Bayer position it lands on drifts by 0.004 pixels
  per output pixel and changes every 240 output pixels in both directions. Each position gives a different colour
  once the black-level subtraction clips the noise, so a dark, noisy picture shows a chessboard of faintly coloured
  240-pixel squares aligned to the frame's corner; bright pictures do not. The CPU debayering crops instead of
  scaling. Reproduced with libcamera 0.7.2's own shaders under Mesa's llvmpipe in a mock chroot, set up as
  `DebayerEGL` does: squares 4 levels apart in a flat, dark, noisy frame. Taking the whole 2x2 quad (red, blue, mean
  green) per output pixel when downscaled removes them; the rebuild did that, and the squares were gone on the
  device (2026-09-28). Upstream had no fix (2026-09-27; a pending patch centres the crop but keeps the scale).
- The metering area (2026-09-28, libcamera 0.7.2's code, found in a review; not measured on the device): with the
  GPU debayering and a stream smaller than the sensor's, the statistics the exposure control and the white balance
  use cover an area of the stream's size at the raw frame's top-left corner, not the picture. `DebayerEGL` gives the
  statistics a window without its offset (`setWindow(Rectangle(window_.size()))`) and hands over the whole frame
  (`processFrame(frame, 0, ...)`), while the CPU debayering passes each line from inside its window. For 1920x1080
  of the IMX681's frame that is the picture's top-left quarter, so exposure and colour follow whatever is there.
  Unchanged on libcamera's master of 2026-09-15.
- IPA signatures: Fedora's spec re-signs `libcamera/ipa_*.so` after stripping, but installs the modules in
  `libcamera/ipa/`, so the signatures it ships are those of the unstripped modules and do not verify against the key
  built into `libcamera.so` (0.7.2-3.fc45, checked with `openssl`); libcamera then runs each IPA isolated in a
  process of its own.
- Device access: PipeWire runs libcamera as the desktop user. Fedora's `70-uaccess.rules` hands the seat user every
  `video4linux` node (the subdevices included), every `media` node and `/dev/udmabuf`; `70-libcamera.rules` gives
  `/dev/dma_heap` to the `video` group only, so libcamera allocates its buffers from `/dev/udmabuf` instead. Since
  systemd 262 (on the device by 2026-09-26; the ISO's root has 261) udev also creates a `/dev/media` directory of
  by-path links next to `/dev/media0`, so scripts take the media devices as `/dev/media[0-9]*`
  (`sp11-camera-probe`, `sp11-diag` since support 3.4).
- The IR camera: the software ISP has no monochrome path in 0.7.2, so libcamera can offer the VD55G0 only as a raw
  stream, which ordinary applications cannot use. Face login would need Howdy and a bridge of its own (turbineBMW
  tested one), none of which Fedora packages.
- The ISO carries the live root's libcamera, Fedora's `libcamera` and `libcamera-ipa`; `cam` comes with Fedora's
  `libcamera-tools`, which the live root lacks.

## On the device

- The round of 2026-09-26 (`docs/verified.md`): the three sensors bind, the CDSP answers and no provider waits for
  `sync_state`, the front and the rear camera stream in GNOME Snapshot and in Firefox, also after a suspend and
  resume (rechecked on 2026-09-28 with revision 8 and 0.7.2-3.sp11.6, also after reboots). `cam -l` lists
  `Internal front camera`, `Internal back camera` and `'vd55g0'` (the VD55G0 driver has no orientation control);
  libcamera runs the rear camera in its 2112x1188 mode for GNOME Snapshot (the software ISP's
  `Input 2112x1188-GRBG-10-CSI2P`) and in its full 4224x3136 mode for `cam` without a stream size, since the simple
  pipeline takes the smallest sensor mode that covers the stream; the IR camera at 320x240 8-bit, about 59 fps.
  GNOME Snapshot leaves the IR camera out by itself (`IR Camera ignored: vd55g0`). For the front camera Fedora's
  build logs that the IPA's signature is `not valid`, falls back to `uncalibrated.yaml` and sets a gain range of
  `0-960 (1)` (the rebuild: `valid`, `imx681.yaml`, `1-16 (0.15)`). The OV13858 retry recovered one CCI queue
  timeout, when Snapshot switched from the front to the rear camera.
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
  frame-duration control, so the exposure ends at 33 ms), its software ISP has no noise reduction, and Fedora's
  exposure control adds no digital gain and moves exposure and gain by at most 6 % per statistics period, which is
  every fourth frame: from 1x to 16x takes about 6 s where libcamera knows the sensor's gain (the rear camera; the
  front camera with the rebuild's IMX681 helper was at 5.2x after 3 s in the first round), while Fedora's build
  steps the front camera's raw gain code. Its target, a mean sample value of 2.5 of 5 histogram bins, needs about
  50 lux of the light sensor at full exposure and 16x. With the rebuild, the owner found that target too bright in
  daylight and chose 1.4.
- The OV13858 applies no analogue gain above 15.5x (`sp11-camera-probe rear --gain-range`, 2026-09-27: the level
  x1.00 from 15.5x to 31x and to 64x), while its driver offers codes up to 0x1fff (64x in libcamera's helper), so
  in the dark Fedora's exposure control raises the rear camera's gain through codes that do nothing, up to 64x.
- Colours: `uncalibrated.yaml` runs grey-world white balance without a colour-correction matrix (as did the
  rebuild's `imx681.yaml` and `ov13858.yaml`), so colours stay muted; a matrix needs a colour-chart measurement.
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
  host against simulated tools and sensors (frame length taken or ignored, gain stopping at 15.5x or not;
  2026-09-27).
- Revision 7's light: it comes on while the front camera streams (owner, 2026-09-27); `white:camera-indicator` reads
  0, 1 while `cam` streams, 0 after, and a write during the stream fails (`Device or resource busy`).
- Fedora's build with revision 10 (2026-10-03, KDE Plasma installation, after `dnf distro-sync 'libcamera*'`
  replaced the rebuild): `cam -l` lists the three cameras, each IPA falling back to `uncalibrated.yaml`, with
  `Failed to create camera sensor helper` for the IMX681 and the VD55G0, and the front camera streams 300 frames
  with its light on; both cameras work in applications (owner, 2026-10-05).

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
over. 2026-10-02: the rebuild dropped (owner: unsustainable across libcamera releases, little gain); the cameras run
Fedora's libcamera again, and steps 47 and 48, the spec template, the patches and the camera skill were removed.
