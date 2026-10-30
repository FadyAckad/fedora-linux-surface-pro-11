# Fedora Live ISO for Surface Pro 11 (Snapdragon X Elite, OLED, incl. the 5G SKU)

![Screenshot showing the About section](images/Screenshot-kde.png)

This repository builds a Fedora 45 installer for the Microsoft Surface Pro, 11th Edition with the OLED panel, the
Snapdragon X Elite tablet, including its 5G model. It is for owners of that tablet who want Fedora next to Windows.
There is no ISO to download: the image contains firmware and sensor files copied from your own Windows
installation, so you build it yourself, on the Surface, in WSL; the kernel alone takes about an hour.

What you get: Fedora's own kernel rebuilt with the community's Surface Pro 11 patches, a support package with the
device's firmware and settings, the pen daemon, the sensor stack, and Fedora's live ISO remastered with all of it,
for the Workstation or the KDE Plasma Desktop edition. How the pieces fit, and the words the guides use:
[`docs/guide/overview.md`](docs/guide/overview.md).

## Current versions

| Component | Version |
|---|---|
| Fedora | 45 Beta 1.3, Workstation or KDE Plasma Desktop |
| Kernel | Fedora's `kernel-7.2.11-300.fc45`, SP11 revision 8 (`7.2.11-300.sp11.8.fc45.aarch64`) |
| Support RPM (`sp11-surface-support`) | 3.8 |
| Pen daemon (`sp11-iptsd`) | 3.1.0-3.sp11 |
| Sensors stack | hexagonrpc 0.5.0-8, libssc 0.4.4-3, iio-sensor-proxy 3.9-3.sp11.2, sp11-sensors 1.15 |

## What works

Tested on the 5G SKU (`Surface_Pro_with_5G_11th_Edition_2077`), on a Fedora 45 Beta Workstation installation from
the ISO built on 2026-10-19 and updated since to the versions above; every row was confirmed again on 2026-10-29.
The KDE Plasma Desktop edition builds from the same RPMs; its rows were last confirmed on 2026-10-08 with kernel
revision 11 (7.2.9). The results by date: [`docs/verified.md`](docs/verified.md).

| Feature | Fedora 45 Beta Workstation, Fedora's 7.2.11-300 (sp11.8) |
|---|:-:|
| Boot from the internal NVMe drive | ✅ |
| Display with GPU acceleration | ✅ |
| Backlight (brightness slider) | ✅ |
| Wi-Fi | ✅ |
| Bluetooth | ✅ |
| Touchscreen | ✅ |
| Multi-touch (pinch, two-finger scroll) | ✅ |
| Pen | ✅ |
| Speakers | ✅ |
| Microphone | ✅ |
| Keyboard and touchpad | ✅ |
| Battery status | ✅ |
| Power profiles (GNOME: its Power Mode sets the Surface's platform profile) | ✅ |
| USB-C charging and data | ✅ |
| Suspend and resume | ✅ |
| Flatpak | ✅ |
| Windows in the GRUB menu | ✅ |
| Flex Keyboard and Slim Pen 2 pairings shared with Windows | ✅ |
| Sensors: readings from the accelerometer, gyroscope, magnetometer/compass and ambient light sensor (`ssccli`, `monitor-sensor`), with the sensors RPMs | ✅ |
| Sensors: auto-rotation on the desktop, with the sensors RPMs (GNOME: its auto-rotate button, with the keyboard folded back or detached) | ✅ |
| Tablet mode: keyboard and touchpad off while the keyboard is folded back | ✅ |
| Sensors: automatic screen brightness | ✅ |
| GPS on the 5G SKU: the location for applications through GeoClue (GNOME: Location on), with a view of the sky | ✅ |
| 5G modem: mobile data with a nano-SIM (GNOME: Mobile Network), from kernel revision 8 | ✅ |
| Cameras: front and rear (GNOME Snapshot, Firefox) | ✅ |
| Front camera's light while the camera is in use | ✅ |
| IR camera (face login) | ❌ |
| NPU (AI acceleration) | ❌ |

✅: confirmed on the tested unit. ❌: not covered by this project. Notes:

- GPS needs no SIM; near a window the first position came within about a minute, away from windows none in two
  minutes ([`docs/gnss.md`](docs/gnss.md)).
- Asleep, the tablet drew 0.33 W over 8 hours with kernel revision 5 or later, against 0.85 W before; the modem is
  off while it sleeps and back about a minute after a wake ([`docs/sleep.md`](docs/sleep.md)).
- Hardware video decoding works from kernel revision 7: a 720p VP9 clip decoded frame for frame in GStreamer, and
  H.264 and H.265 clips once their colorimetry was relabelled ([`docs/hardware.md`](docs/hardware.md), Video
  codec).
- USB-C data works with the plug one way round; turned over, a USB 3 stick is not found on either port, while
  Windows finds it both ways ([`docs/hardware.md`](docs/hardware.md), USB-C data).
- In the live session, audio and battery status are unavailable because the audio DSP stays off while running
  from USB-C. Both work once installed.
- Under KDE Plasma, auto-rotation could stop until iio-sensor-proxy was restarted, and with automatic brightness on
  the tablet did not stay asleep; the sensors RPMs fix both since libssc 0.4.4-3 (2026-10-07) and iio-sensor-proxy
  3.9-3.sp11.2 (2026-10-08) ([`docs/guide/troubleshooting.md`](docs/guide/troubleshooting.md)).

## Status and scope

- Unofficial community project, not affiliated with Microsoft, Qualcomm, or Fedora. No warranty.
- Tested only on the 5G OLED SKU. The hardware checks also accept the non-5G OLED SKUs
  (`Surface_Pro_11th_Edition_2076`, `Surface_Pro_11th_Edition_For_Business_2085`), which share the firmware; the
  build gives them the OLED device tree without the modem and leaves the modem's files out of their support RPM.
  No build from one has been reported. The X1P64100 LCD variant uses a different device tree and is rejected.
- Secure Boot must be disabled: the kernel is a local build of Fedora's kernel package and is not signed.
- Windows must stay on the device: the build reads the hardware identity, the built-in radio's Bluetooth address,
  the ADSP/CDSP/GPU/video firmware and the sensor configuration and registry from it. Without the firmware an
  installed system has no audio, battery reporting, GPU acceleration or hardware video decoding.
- The support RPM and the ISO contain proprietary Qualcomm firmware copied from your own Windows installation. Do
  not redistribute them; point other people to this repository instead.

## Quick start

Requirements: a Fedora aarch64 distribution in WSL on the Surface, Windows interop (`powershell.exe`), `sudo`
(passwordless for unattended runs), 80 GiB free disk space and internet access.

Once per unit, export its sensor registry from Windows (one UAC prompt):

```bash
scripts/75-export-sensor-registry.sh
```

Then build. The kernel takes about an hour after the downloads; keep WSL running meanwhile:

```bash
scripts/build-all.sh
```

For the KDE Plasma Desktop image instead of Workstation (the kernel and RPMs are the same and are reused):

```bash
FEDORA_EDITION=KDE-Desktop scripts/build-all.sh
```

The ISO lands in `build/out/`, for example
`Fedora-Workstation-Live-45_Beta-1.3-SP11-7.2.11-300.sp11.8.fc45.aarch64.iso` or
`Fedora-KDE-Desktop-Live-45_Beta-1.3-SP11-7.2.11-300.sp11.8.fc45.aarch64.iso`, with a `.sha256` beside it. Then
write it to a USB stick and install: [`docs/guide/install.md`](docs/guide/install.md).

## Reporting results

The hardware checks accept the non-5G OLED SKUs, but no build from one has been reported. If you build or install
on another unit, open an issue with the SKU, the ISO's name, which rows of the table worked, and for anything that
did not, the output of `sudo /usr/libexec/sp11/sp11-diag`. That file names your Bluetooth controller and devices by
address; remove them before posting if you prefer.

## Documentation

Start here:

- [`docs/guide/overview.md`](docs/guide/overview.md): how the build works, and a glossary of the terms used here.
- [`docs/guide/install.md`](docs/guide/install.md): writing the USB, the firmware settings, the installer, the
  first boot.
- [`docs/guide/update.md`](docs/guide/update.md): updating the support RPM and installing a new SP11 kernel.
- [`docs/guide/troubleshooting.md`](docs/guide/troubleshooting.md): diagnostics, known limitations, what earlier
  releases fixed.

Building:

- [`docs/guide/build.md`](docs/guide/build.md): requirements, the pipeline, its options, steps and checks.
- [`docs/guide/build-rpms.md`](docs/guide/build-rpms.md): building one set of RPMs alone for an installed system.
- [`docs/guide/sensors.md`](docs/guide/sensors.md): the sensors stack: install, update, check, reset.
- [`docs/guide/bluetooth-pairings.md`](docs/guide/bluetooth-pairings.md): sharing the Flex Keyboard and Slim Pen 2
  pairings with Windows.
- [`docs/guide/new-release.md`](docs/guide/new-release.md): moving to a new Fedora compose or kernel.

Background:

- [`docs/guide/design.md`](docs/guide/design.md): what the scripts decide for you, and why.
- [`docs/guide/support-rpm-history.md`](docs/guide/support-rpm-history.md): what each support RPM version changed.
- [`docs/guide/layout.md`](docs/guide/layout.md): what each file of the repository is.
- [`docs/guide/credits.md`](docs/guide/credits.md): license and credits.

For maintainers: the working notes under `docs/`, indexed in [`docs/README.md`](docs/README.md), hold the verified
facts, measurements and lessons the guides rest on.

## License

GPL-3.0-or-later for the repository's content (`LICENSE`). Everything third-party is downloaded and packaged at
build time. The proprietary firmware and sensor files come from your own Windows installation and never enter the
repository. Details: [`docs/guide/credits.md`](docs/guide/credits.md).
