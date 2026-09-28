# Cameras

The front and the rear camera: what the support is, how to install or update it on an installed system, how to
check it, and its limits. How it works, and its device history, are in [`docs/camera.md`](../camera.md); building
its RPMs is part of [`docs/guide/build.md`](build.md).

The Surface Pro 11 has three cameras: the front camera (Sony IMX681), the rear camera (OmniVision OV13858) and an
infrared camera for face login (ST VD55G0). The kernel side is part of the SP11 kernel: since revision 6 the camera
subsystem's C-PHY support, the camera nodes and the sensor drivers, since revision 7 the light next to the front
camera, since revision 8 the front camera's frame length. libcamera, which turns the sensors' raw frames into a
picture for desktop applications, is Fedora's own package rebuilt with the IMX681's data, a faster exposure control
with digital gain for low light, an exposure target chosen on the device, a fix of its GPU downscaling and the
sensor's nearest gain step (`0.7.2-3.sp11.6`). ISOs built since 2026-09-28 install them in place of Fedora's build.
Confirmed on the tested unit: both cameras in GNOME Snapshot and in Firefox, also after suspend and resume and after
reboots; the light next to the front camera while it is in use; an exposure that is right in daylight and settles
within a few seconds in dim light.

## Install or update

A system installed from an ISO built since 2026-09-28 has them already. The RPMs come from a build (`build/rpms/`,
step 47 of [`docs/guide/build.md`](build.md)) or from `/sp11/rpms` on such an ISO; the system needs the SP11 kernel
of revision 8 or later (`uname -r` ends in `.sp11.8.fc45.aarch64` or a later revision; installing a kernel:
[`docs/guide/update.md`](update.md)). From the directory holding the RPMs:

```bash
sudo dnf install ./libcamera-0.7.2-3.sp11.6.fc45.aarch64.rpm ./libcamera-ipa-0.7.2-3.sp11.6.fc45.aarch64.rpm ./libcamera-tools-0.7.2-3.sp11.6.fc45.aarch64.rpm
```

Then, as the desktop user, so that desktop applications load the new build:

```bash
systemctl --user restart wireplumber pipewire
```

The packages replace Fedora's libcamera of the same version. Nothing holds back Fedora's libcamera updates: a newer
Fedora build replaces the rebuild, and the cameras fall back to Fedora's build (no IMX681 support: a dark front
camera with a slow exposure control, and coloured squares in dark pictures) until the rebuild is redone for the new
version. If dnf reports that another libcamera package, such as `libcamera-v4l2` or `libcamera-gstreamer`, requires
Fedora's build, add its rebuild from `build/rpms/` to the same command. `rpm -q libcamera` shows which build is
installed (`.sp11.` in the release is the rebuild).

## Check

```bash
cam -l
```

Lists `Internal front camera`, `Internal back camera` and the infrared camera as `'vd55g0'`. GNOME Snapshot offers
the front and the rear camera and leaves the infrared camera out by itself. `sudo /usr/libexec/sp11/sp11-diag`
(support RPM 3.3 or later) has a camera section: the camera packages, what the camera drivers bound, the media
graph, `cam -l` and libcamera's messages from the journal.

The exposure control aims at `exposureTarget: 1.4` in `/usr/share/libcamera/ipa/simple/imx681.yaml` (front camera)
and `ov13858.yaml` (rear camera), lower is darker, higher brighter. Values from 1.3 to 2.5 (libcamera's own default)
work; a value outside 1.3 to 5 is clamped to that range, with a warning in the log
(`exposureTarget ... outside 1.3 to 5, using ...`). A changed value takes effect after the PipeWire restart above; a
libcamera update replaces the file.

## Limits

- Dim light: the exposure is at most one frame at 30 fps (libcamera's simple pipeline has no frame-rate control),
  the sensor gain at most 16x (front) or 15.5x (rear), plus 4x digital gain, and the software image processing has
  no noise reduction. In a dark spot (the light sensor at 1 lux) both cameras reach those limits and the picture
  stays dark and grainy.
- Colours: white balance only, without a colour-correction matrix, which needs a measurement with a colour chart;
  colours look muted.
- The infrared camera streams only raw frames, which ordinary applications cannot use; face login (Howdy) is not
  covered.
