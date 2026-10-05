# Cameras

The front and the rear camera: what the support is, how to check it, its limits, and how a system with the
project's former libcamera rebuild goes back to Fedora's build. How it works, and its device history, are in
[`docs/camera.md`](../camera.md).

The Surface Pro 11 has three cameras: the front camera (Sony IMX681), the rear camera (OmniVision OV13858) and an
infrared camera for face login (ST VD55G0). The support is part of the SP11 kernel: since revision 6 the camera
subsystem's C-PHY support, the camera nodes and the sensor drivers, since revision 7 the light next to the front
camera, since revision 8 the front camera's frame length. libcamera, which turns the sensors' raw frames into a
picture for desktop applications, is Fedora's own package, unmodified. Confirmed on the tested unit with the
project's former libcamera rebuild: both cameras in GNOME Snapshot and in Firefox, also after suspend and resume and
after reboots, and the light next to the front camera while it is in use. With Fedora's build both cameras and
the light work on the tested unit (kernel revision 10, KDE Plasma, 2026-10-05).

## Check

```bash
cam -l
```

Lists `Internal front camera`, `Internal back camera` and the infrared camera as `'vd55g0'`. `cam` comes with
Fedora's `libcamera-tools` (`sudo dnf install libcamera-tools`; ISOs built from 2026-09-28 to 2026-10-02 install
it). GNOME Snapshot offers the front and the rear camera and leaves the infrared camera out by itself.
`sudo /usr/libexec/sp11/sp11-diag` (support RPM 3.3 or later) has a camera section: the camera packages, what the
camera drivers bound, the media graph, `cam -l` and libcamera's messages from the journal.

## Back to Fedora's libcamera

A system installed from an ISO built from 2026-09-28 to 2026-10-02, or one that installed the libcamera RPMs of a
device round, has the project's former rebuild: `rpm -q libcamera` shows `.sp11.` in the release. `dnf upgrade`
keeps it until Fedora ships a newer libcamera. Fedora's build of the same version replaces it with:

```bash
sudo dnf distro-sync 'libcamera*'
```

Then, as the desktop user, so that desktop applications load it:

```bash
systemctl --user restart wireplumber pipewire
```

## Limits

- Front camera: Fedora's libcamera has no data for the IMX681. Its exposure control treats the sensor's gain code
  as linear, so in dim light the gain rises one raw step per update at first, and the picture takes longer to
  brighten; it uses libcamera's generic tuning file.
- Dim light: the exposure is at most one frame at 30 fps (libcamera's simple pipeline has no frame-rate control),
  the sensor gain at most 16x (front) or 15.5x (rear; the driver offers higher codes, which change nothing), there
  is no digital gain, and the software image processing has no noise reduction. Exposure and gain change by at most
  6 % every fourth frame. In a dark room both cameras stay dark and grainy.
- Dark pictures at less than the sensor's full size can show faintly coloured squares (libcamera's GPU
  downscaling).
- Daylight: with the former rebuild, libcamera's default exposure target turned faces white in daylight; Fedora's
  build uses that default.
- Colours: white balance only, without a colour-correction matrix, which needs a measurement with a colour chart;
  colours look muted.
- The infrared camera streams only raw frames, which ordinary applications cannot use; face login (Howdy) is not
  covered.
