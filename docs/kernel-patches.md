# SP11 patch set

The SP11 patch set is the branch `sp11/<version>` of the project's fork of the stable kernel (`KERNEL_PATCH_REPO` in
`sp11.conf`): one commit per patch, with its original author, on top of the stable tag whose tree Fedora's source
tarball carries. `sp11.conf` pins the base and the head commit (`KERNEL_PATCH_BASE_COMMIT`, `KERNEL_PATCH_COMMIT`).
`scripts/10-fetch-sources.sh` fetches them (a shallow partial clone of a few MB) and writes the series with
`git format-patch`; `scripts/20-build-kernel.sh` checks that the series rebuilds the pinned commit's tree and
concatenates it into Fedora's `linux-kernel-test.patch` (the slot `kernel.spec` provides for local builds, applied
with `git apply` after Fedora's own `patch-<x.y>-redhat.patch`). `files/kernel-local` sets the one new configuration
symbol and enables two drivers Fedora's configuration leaves out. Nothing else about Fedora's kernel changes. Every
change needs a new `KERNEL_SP11_REV` (see `docs/kernel.md`). A pushed branch is never rewritten, so every pinned
commit stays fetchable: fixes go on top as new commits, a new kernel base on a new branch.

The patches are derived from the Linux kernel and, like the files they modify, licensed GPL-2.0 (the new
`mshw0485_touch.c` and headers carry their own SPDX lines). Authorship is in each commit; this repository does not
carry the patches.

## Where they come from

Revision 1 (2026-09-23) was extracted from the kernel the project had verified on the device: ooaklee's
linux_ms_dev_kit-sp11 release `sp11-qcom-x1e-7.2.0-jg-0sp11v23` (commit `ce78e6ebc3d7`) with the kernel.org 7.2.5
stable update, built as `7.2.5-jg-0sp11v23.2-qcom-x1e`. That tree is Ubuntu's qcom-x1e concept kernel with jglathe's
X1E tree (jglathe/linux_ms_dev_kit) and ooaklee's Surface Pro 11 work on top. The extraction kept:

- 0001–0045: commits of jglathe's 7.2.0 tree (`746b3477`) that change code or device-tree nodes this machine uses,
  as the original commits (author, message and diff; 0014 without a jglathe-only X1P file, 0031 and 0045 with only
  their Denali hunks). Which commits qualify was decided from the built v23.2 tree: the source files compiled into
  the drivers the Denali OLED device tree binds, plus the Surface Aggregator, pmic_glink, HID and PCI (Wi-Fi)
  devices.
- 0046–0051: ooaklee's branch commits that apply as they are (OLED link-rate quirk, dwc3 PHY re-init, platform
  profile).
- 0052–0060: ooaklee's work as topic patches of the validated files (their headers name the source commits and
  authors): touch and pen, audio, the Surface battery guard, the Denali device tree.
- 0061: this repository's POS tablet-mode switch.

Revision 2 (2026-09-23) added a CDSP boot-order patch that did not help and was dropped again. Revisions 3 and 4
(2026-09-24) carry these 61 patches unchanged; they add configuration only (`files/kernel-local`, `docs/kernel.md`).
On 2026-09-24 the patches moved from this repository into the fork as the branch `sp11/7.2.5` (head `df9cc406`): its
tree equals the former patch files applied to `v7.2.5`, and only 0061's author changed, from a build placeholder to
the fork's owner.

Proven on the host before the first build: the series applied to kernel.org 7.2.5 reproduces 70 of the 80 files it
touches byte for byte from the v23.2 source; the other 10 differ only by the left-out parts listed below. The Denali
OLED device tree it builds has the same enabled nodes as v23.2's, minus the camera, the privacy LED, the PMK8550 ADC
(which the v23.2 kernel had no driver for) and the ThinkPad T14s compatible. The series applies to Fedora's
`kernel-7.2.5-300.fc45` sources with `git apply` and no offsets, and with Fedora's configuration plus `kernel-local`
every directory it touches compiles without an error or a warning, as do all Qualcomm arm64 device trees. (A file
comparison does not see a missing API: the first build of revision 1 stopped in `net/qrtr/smd.c`, whose race fix
needs the rpmsg helper that is now 0005.)

## Contents

| Patches | What | Origin | Needed for |
|---|---|---|---|
| 0001 | EFI stub: signal the before-ExitBootServices event group | Johan Hovold (T14s workaround, applies to every arm64 machine) | boot (kept until a boot without it is tested) |
| 0002, 0003 | UCSI connector worker and pmic_glink altmode worker on freezable workqueues | Abel Vesa | USB-C across suspend |
| 0004–0006 | rpmsg announce order, an rpmsg helper to open an endpoint during probe (needed by 0006), QRTR SMD open/close races | Stephan Gerhold | ADSP services (audio, battery, sensors) |
| 0007 | x1e80100 machine driver match data (Dell XPS 13 channel map) | Abel Vesa | prerequisite of 0058 |
| 0008 | qcom_battmgr request input checks | Jens Glathe | battery |
| 0009 | WCN7850 Bluetooth: drop the unused baud-rate event | Cheng Jiang | Bluetooth |
| 0010, 0011, 0013 | QMP combo PHY: initial mode for static bridges, no PM suspend at boot | Jens Glathe, Loic Poulain | USB-C, DisplayPort alt mode |
| 0012, 0022–0026, 0032–0040 | msm display and GPU: X1E catalog, clock factor, gamma, resume clock, PSR SDP flush, standalone GPU/GMU device model, no OPP rate 0 | William Larson, Jens Glathe, Stephan Gerhold, Xilin Wu, Lars Karlslund, Konrad Dybcio, Akhil P Oommen | display, GPU acceleration, backlight, suspend |
| 0014 | Denali firmware paths in the OLED device tree | Jens Glathe | ADSP, CDSP, GPU firmware |
| 0015, 0016 | ath12k `disable-rfkill` device-tree property, set on the Denali Wi-Fi node | Dale Whinham | Wi-Fi (hard-blocked otherwise) |
| 0017 | Surface Aggregator: the DT default no longer assumes the EC closes its serial handle in D3 (SP11 suspend fix) | Dale Whinham | keyboard, touchpad, tablet switch after resume |
| 0018 | ADSP audio PD remote heap region | Ekansh Gupta | the FastRPC setup the sensors stack was verified with |
| 0019–0021 | LPASS WSA and VA macros on the PM clock framework, optional NPL clock | Ajay Kumar Nandam | speakers, microphone (base of 0057) |
| 0027–0031 | PS8830 retimer: USB4 off, DP alt-mode states, config delay | Jens Glathe | USB-C, DisplayPort alt mode |
| 0041–0044 | apply clock defaults only once the PHY is powered (driver core, DP, eUSB2, dwc3-qcom) | Stephan Gerhold, Jens Glathe | USB, DisplayPort |
| 0045 | Denali QMP PHY supplies (in 7.2.6) | Manivannan Sadhasivam | USB |
| 0046 | OLED panel: maximum link rate from ACPI when the DPCD reports 0 | Jérôme de Bretagne | display on the non-5G SKUs (the DMI match excludes the 5G SKU) |
| 0047, 0048 | dwc3 `snps,reinit-phy-on-resume` | Oliver White | USB after resume |
| 0049–0051 | Surface platform profile and fan without ACPI | Leon Silcott (ooaklee) | power profiles, fan readout |
| 0052, 0053 | GPI DMA and GENI SPI in QSPI mode | x1e-nixos, ooaklee | touchscreen, pen |
| 0054 | MSHW0485 touchscreen driver with the iptsd HIDRAW bridge | ooaklee, Leon Silcott, Justin White | touchscreen, multi-touch, pen |
| 0055–0058 | SoundWire feedback ports, AudioReach speaker protection graph, WSA8845 and LPASS macros, x1e80100 VI/CPS backends | geocausa (SP11X1e-audio), ported by Leon Silcott | speakers, microphone |
| 0059 | surface_battery: no second battery on the SP11 | Justin White | battery |
| 0060 | Denali device tree: touch controller, audio feedback links, volume keys, USB PHY re-init, no cluster idle states | x1e-nixos, ooaklee, Leon Silcott | touch, audio, volume keys, suspend |
| 0061 | POS tablet-mode switch for the Surface Pro 11 | this repository | tablet mode, auto-rotation |

## Left out of v23.2, and the device check for each

Nothing here drives hardware a README feature depends on; the check says what round A confirms.

- Ubuntu's packaging, configuration annotations, out-of-tree drivers and SAUCE patches (AppArmor, lockdown, FAN
  networking, ...), including three that touch hardware this machine uses: the eDP PHY regulator-load removal (Johan
  Hovold's patch as Ubuntu carries it; upstream behaviour is what every other X1E laptop runs — display), the revert
  of the ps883x accessibility check (USB-C) and a UCSI connector-cleanup race fix (USB-C unplug).
- The ADSP attach series (remoteproc, SMP2P, pmic_glink probe-order hack): mainline's PAS
  driver shuts the UEFI-started ADSP down and boots the full firmware, as on every other X1E laptop — audio,
  battery, sensors, USB-C after boot.
- The clock `sync_state` series and a gcc UFS log change — boot, suspend (the kernel arguments keep unused clocks
  and power domains on).
- The PCIe ASPM API series and ath12k's MAC-from-device-tree hack — Wi-Fi and NVMe, also after resume.
- The camera stack (IMX681, CAMSS, CCI, C-PHY, privacy LED): on v23.2 its picture was far too dark to use (checked
  2026-09-23), and the README lists cameras as not working; left out until a camera fix.
- The spi-hid series (unused: the MSHW0485 driver frames HID-over-SPI itself) and the uncalled
  `qcom_geni_spi_biosref_xfer()` helper.
- Debug output (DP, QMP combo, drm_dp_helper, UCSI feature print), the DPU underflow colour, DP audio (the Denali
  sound card has no DisplayPort DAI), other laptops' device trees, panels, EC and QSEECOM entries, EL2, X1P.
