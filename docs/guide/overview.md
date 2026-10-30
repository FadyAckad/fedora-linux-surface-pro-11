# How it works

What the build does, from your Windows installation to an installed Fedora, why so much of it comes from Windows,
and the words the other guides use. The decisions behind each step, with their reasons:
[`docs/guide/design.md`](design.md).

## The flow

The build runs in WSL on the Surface itself and is a chain of numbered scripts under `scripts/`;
`scripts/build-all.sh` runs them in order ([`docs/guide/build.md`](build.md)).

1. Read the unit. Step 05 asks Windows (through `powershell.exe`) for the tablet's model, its panel and the
   built-in Bluetooth radio's address, checks them against the supported models and records them in
   `build/hardware.env`. The model decides which device tree the tablet will boot and whether the 5G modem's
   files are included.
2. Download. Step 10 fetches Fedora's live ISO, Fedora's kernel source package, the Surface Pro 11 patch set from
   the project's kernel fork, the pen daemon's source and the sensor libraries, every one pinned by commit or
   checksum.
3. Build the kernel. Step 20 rebuilds Fedora's own kernel package with the patch set and a few extra configuration
   lines, in a clean build root of the target Fedora release, so the result installs, boots and updates like
   Fedora's kernel. Each change to the patches is a new revision of the kernel.
4. Build the device packages. Step 30 packs the support RPM: the firmware for the audio, compute and graphics
   processors copied from Windows' driver store, the audio profile, the Wi-Fi board data, the Bluetooth address,
   GRUB's settings and the Windows boot entry, the first-boot service and a diagnostics script. Step 40 builds the
   pen daemon. Step 45 builds the sensors stack from the sensor registry exported from Windows (step 75, once).
5. Remaster. Step 50 unpacks Fedora's live image, replaces its stock kernel with the SP11 build, installs the
   RPMs, gives Fedora's boot menu the device tree and the kernel arguments, and writes the ISO with its media-check
   checksum. Steps 35, 36, 46 and 60 check the packages and the result in a copy of the live root.
6. Install. The live session boots from USB and runs Fedora's installer; the first boot of the installed system
   switches the audio processor on, writes the GRUB entries and rebuilds the initramfs
   ([`docs/guide/install.md`](install.md)). Updates then come as RPMs built the same way
   ([`docs/guide/update.md`](update.md)).

## Why so much comes from Windows

- The firmware of the audio, compute and graphics processors is proprietary and is not in Fedora's packages; the
  copy in Windows' driver store is the one the hardware was shipped with.
- The sensors (accelerometer, gyroscope, compass, light) are read by a framework inside the audio processor, which
  needs the unit's own calibration and registry, written by Windows.
- The Bluetooth controller reports no address of its own; Linux sets the one Windows uses, which is what lets the
  keyboard and pen pairings be shared.
- The model, the panel and the Bluetooth address come from Windows because WSL can ask it, and the build runs on
  the Surface so that each ISO is made for the unit it will be installed on.

## Glossary

- SP11: Surface Pro 11; the prefix of the project's packages and files (`sp11-surface-support`, `sp11.conf`).
- SKU: the model string Windows reports (`Surface_Pro_with_5G_11th_Edition_2077` on the tested unit); it decides
  the device tree.
- Denali: Microsoft's code name for the Surface Pro 11 board; the device tree files are named after it.
- Device tree, DTB: the file that tells the kernel what hardware the board has. On this chip Linux uses it instead
  of the ACPI tables Windows uses, and GRUB loads it with the kernel.
- X1E80100: Qualcomm's Snapdragon X Elite chip. X1P64100 is the smaller chip of the LCD model, which is not
  supported.
- ADSP, CDSP: the audio and compute digital signal processors inside the chip. The ADSP runs the audio, the
  battery manager and the sensor framework (SSC, the Snapdragon Sensor Core); nothing here uses the CDSP.
- Support RPM: `sp11-surface-support`, the package with the firmware, settings and helper scripts, versioned 3.x.
- Revision: the project's count of changes to Fedora's kernel, the `.sp11.<n>` in its version; it restarts at 1
  with each new Fedora kernel version.
- Patch set: the Surface Pro 11 kernel patches, kept as commits on the project's kernel fork and listed in
  [`docs/kernel-patches.md`](../kernel-patches.md).
- Steps: the numbered scripts under `scripts/`; "step 50" is `scripts/50-build-iso.sh`.
- Live root: the filesystem of Fedora's live image, unpacked for the build and copied by the installer.
- Sensors stack: the four RPMs `hexagonrpc`, `libssc`, `iio-sensor-proxy` and `sp11-sensors`
  ([`docs/guide/sensors.md`](sensors.md)).
- 5G SKU: the model with the Snapdragon X65 modem, which also provides GPS.
- Pen daemon: `sp11-iptsd`, the user-space driver that turns the touch controller's data into pen and
  multi-touch input.
