# License and credits

The license of this repository, and the origin and license of everything the build downloads, patches or copies.

The scripts, templates and documentation in this repository are licensed under the GNU General Public License,
version 3 or later (`LICENSE`). Everything third-party is downloaded and packaged at build time:

- Kernel: Fedora's `kernel` source RPM (GPL-2.0), rebuilt with the patch set (the project's kernel fork, GPL-2.0
  like the kernel; each commit names its author), which was extracted from
  [ooaklee/linux_ms_dev_kit-sp11](https://github.com/ooaklee/linux_ms_dev_kit-sp11) (release v23): ooaklee's Surface
  Pro 11 work (touchscreen and pen after x1e-nixos's QSPI port, the audio work of geocausa's SP11X1e-audio as ported
  by Leon Silcott, device tree, platform profile, with Justin White, Jérôme de Bretagne and Oliver White), and the
  X1E fixes it carries from [jglathe/linux_ms_dev_kit](https://github.com/jglathe/linux_ms_dev_kit) and upstream
  developers (Stephan Gerhold, Abel Vesa, Akhil P Oommen, Konrad Dybcio, Johan Hovold, Dale Whinham and others;
  [`docs/kernel-patches.md`](../kernel-patches.md) lists them). ooaklee's releases are published through
  [ooaklee/linux-surface-pro-11-oe](https://github.com/ooaklee/linux-surface-pro-11-oe), which also provides the
  FullIO audio topology and UCM files, the iptsd integration templates (MIT,
  `userspace/iptsd-sp11/LICENSE.integration`) and `sp11-bt-set-addr.c`. That repository has no top-level license;
  the audio files and the helper carry no license statement, and the release notes say the topology contains
  vendor-derived bytes that must stay outside kernel packages.
- Pen daemon: [linux-surface/iptsd](https://github.com/linux-surface/iptsd) (GPL-2.0-or-later and MIT),
  unmodified.
- Wi-Fi board data: `board-2.bin` from Fedora's `atheros-firmware`, extracted with `ath12k-bdencoder`
  from [qca/qca-swiss-army-knife](https://github.com/qca/qca-swiss-army-knife).
- Sensors: [linux-msm/hexagonrpc](https://github.com/linux-msm/hexagonrpc) (GPL-3.0-or-later), built from
  [this project's fork](https://github.com/FadyAckad/hexagonrpc), branch `sp11-sensors`: upstream plus five
  commits (the sensor framework's registry writes, requests longer than 256 bytes, the registry's parent
  directory, and the fixes those write paths needed; meant for upstream, see hexagonrpc's issue #19 and
  pull request #21),
  [DylanVanAssche/libssc](https://codeberg.org/DylanVanAssche/libssc) (GPL-3.0-or-later) and Fedora's
  `iio-sensor-proxy` source RPM (GPL-3.0-or-later), the latter two unmodified; the approach follows
  [denisix/ubuntu-surface-pro-11](https://github.com/denisix/ubuntu-surface-pro-11). The sensor configuration
  and registry that `sp11-sensors` carries are proprietary Microsoft and Qualcomm files copied from your own
  Windows installation at build time, like the firmware below.
- Base media: Fedora Workstation live images, or a spin (`FEDORA_EDITION`). Bring-up notes:
  rjindael/fedora-surface-pro-11.
- ADSP/CDSP/GPU firmware: proprietary Qualcomm and Microsoft files copied from your own Windows
  DriverStore at build time. Never part of this repository; see
  [Status and scope](../../README.md#status-and-scope).

Upstream files modified during the build, with changes that are not upstream: the octet order in
`sp11-bt-set-addr.c` (the Bluetooth address in [`docs/guide/design.md`](design.md)), the ALSA UCM device matcher in
`x1e80100.conf`, which gains the `( with 5G)?` alternative, and the Mic device in `SP11-HiFi.conf`, which gains the
microphone gain; in the kernel, everything the SP11 patch set changes (none of it is in Linux 7.2.5;
[`docs/kernel-patches.md`](../kernel-patches.md) lists where each patch comes from).
