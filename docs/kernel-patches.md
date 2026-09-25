# SP11 patch set

The SP11 patch set is the branch `sp11/<version>` of the project's fork of the stable kernel (`KERNEL_PATCH_REPO` in
`sp11.conf`): one commit per patch, with its original author, on top of the stable tag whose tree Fedora's source
tarball carries. `sp11.conf` pins the base and the head commit (`KERNEL_PATCH_BASE_COMMIT`, `KERNEL_PATCH_COMMIT`).
`scripts/10-fetch-sources.sh` fetches them (a shallow partial clone of a few MB) and writes the series with
`git format-patch`; `scripts/20-build-kernel.sh` checks that the series rebuilds the pinned commit's tree and
concatenates it into Fedora's `linux-kernel-test.patch` (the slot `kernel.spec` provides for local builds, applied
with `git apply` after Fedora's own `patch-<x.y>-redhat.patch`). `payload/kernel-local` sets the one new
configuration symbol and enables two drivers Fedora's configuration leaves out. Nothing else about Fedora's kernel
changes. Every change needs a new `KERNEL_SP11_REV` (see `docs/kernel.md`). A pushed branch is never rewritten, so
every pinned commit stays fetchable: fixes go on top as new commits, a new kernel base on a new branch.

The patches are derived from the Linux kernel and, like the files they modify, licensed GPL-2.0 (the new
`mshw0485_touch.c` and headers carry their own SPDX lines). Authorship is in each commit; this repository does not
carry the patches.

## Where they come from

Revision 1 (2026-09-23) was extracted from the kernel the project had verified on the device: ooaklee's
linux_ms_dev_kit-sp11 release `sp11-qcom-x1e-7.2.0-jg-0sp11v23` (commit `ce78e6ebc3d7`) with the kernel.org 7.2.5
stable update, built as `7.2.5-jg-0sp11v23.2-qcom-x1e`. That tree is Ubuntu's qcom-x1e concept kernel with jglathe's
X1E tree (jglathe/linux_ms_dev_kit) and ooaklee's Surface Pro 11 work on top. The extraction kept 61 patches; in the
numbering of the current branch `sp11/7.2.7`:

- 0001–0041: commits of jglathe's 7.2.0 tree (`746b3477`) that change code or device-tree nodes this machine uses,
  as the original commits (author, message and diff; 0014 without a jglathe-only X1P file, 0030 with only its
  Denali hunk). Which commits qualify was decided from the built v23.2 tree: the source files compiled into the
  drivers the Denali OLED device tree binds, plus the Surface Aggregator, pmic_glink, HID and PCI (Wi-Fi) devices.
- 0042–0047: ooaklee's branch commits that apply as they are (OLED link-rate quirk, dwc3 PHY re-init, platform
  profile).
- 0048–0056: ooaklee's work as topic patches of the validated files (their headers name the source commits and
  authors): touch and pen, audio, the Surface battery guard, the Denali device tree.
- 0057: this repository's POS tablet-mode switch.

Revision 2 (2026-09-23) added a CDSP boot-order patch that did not help and was dropped again. Revisions 3 and 4
(2026-09-24) carry these 61 patches unchanged; they add configuration only (`payload/kernel-local`,
`docs/kernel.md`). On 2026-09-24 the patches moved from this repository into the fork as the branch `sp11/7.2.5`
(head `df9cc406`): its tree equals the former patch files applied to `v7.2.5`, and only the POS switch's author
changed, from a build placeholder to the fork's owner.

Revision 5 (2026-09-25) is the branch `sp11/7.2.7` (head `8ed6c0df`, tree `1ec390ba`): the 61 commits of
`sp11/7.2.5` rebased onto `v7.2.7` in one step (`git rebase --onto v7.2.7 v7.2.5`; a stable tag contains every
earlier one of its series, and of the stable changes since 7.2.5 only 7.2.6's touch the patch set's files), plus one
new commit. Four commits are in 7.2.6 and dropped out: the DP EDID update and the DPU and DSI
`dev_pm_opp_set_rate(0)` removals verbatim, the Denali QMP PHY supplies as the Denali hunk of the same fix for every
X1E board. Three were adapted, each with an `[sp11: ...]` note in its message: 0031 keeps only the hunk in
`msm_dp_ctrl_off_link_stream()`, which 7.2.6's version of the same fix lacks (mainline no longer has the function);
0049's QSPI path returns `-EPROBE_DEFER` directly, because 7.2.6's `spi_geni_init()` holds its runtime PM reference
in a scoped guard and no longer has the `out_pm` label (the textual merge was clean, the compile would not have
been); 0052 takes 7.2.6's form of `q6apm_graph_start()`, which counts a graph only once the DSP accepted its start,
as the SP11 version already did, and keeps 7.2.6's guard in `q6apm_graph_stop()`. 0058 is new: 7.2.6's port check in
`qcom_swrm_stream_alloc_ports()` refuses the controller's highest master port, which the SP11 maps both amplifiers'
CPS feedback to (port 13 of the WSA controller's 13). Old numbers to new: 0001–0023 unchanged, 0025–0031 to
0024–0030, 0033 to 0031, 0035–0044 to 0032–0041, 0046–0061 to 0042–0057.

Proven on the host before the first build: the series applied to kernel.org 7.2.5 reproduces 70 of the 80 files it
touches byte for byte from the v23.2 source; the other 10 differ only by the left-out parts listed below. The Denali
OLED device tree it builds has the same enabled nodes as v23.2's, minus the camera, the privacy LED, the PMK8550 ADC
(which the v23.2 kernel had no driver for) and the ThinkPad T14s compatible. The series applies to Fedora's
`kernel-7.2.5-300.fc45` sources with `git apply` and no offsets, and with Fedora's configuration plus `kernel-local`
every directory it touches compiles without an error or a warning, as do all Qualcomm arm64 device trees. (A file
comparison does not see a missing API: the first build of revision 1 stopped in `net/qrtr/smd.c`, whose race fix
needs the rpmsg helper that is now 0005.)

Proven on the host for revision 5: Fedora's `linux-7.2.7.tar.xz` holds exactly the `v7.2.7` tree (every path, mode
and blob); with Fedora's 7.2.7 configuration plus `kernel-local`, every directory the series touches compiles
without an error or a warning, as do all arm64 device trees; `git am` of the series onto `v7.2.7` reproduces the
branch's tree with the same authors, dates and messages.

## Contents

| Patches | What | Origin | Needed for |
|---|---|---|---|
| 0001 | EFI stub: signal the before-ExitBootServices event group | Johan Hovold (T14s workaround, applies to every arm64 machine) | boot (kept until a boot without it is tested) |
| 0002, 0003 | UCSI connector worker and pmic_glink altmode worker on freezable workqueues | Abel Vesa | USB-C across suspend |
| 0004–0006 | rpmsg announce order, an rpmsg helper to open an endpoint during probe (needed by 0006), QRTR SMD open/close races | Stephan Gerhold | ADSP services (audio, battery, sensors) |
| 0007 | x1e80100 machine driver match data (Dell XPS 13 channel map) | Abel Vesa | prerequisite of 0054 |
| 0008 | qcom_battmgr request input checks | Jens Glathe | battery |
| 0009 | WCN7850 Bluetooth: drop the unused baud-rate event | Cheng Jiang | Bluetooth |
| 0010, 0011, 0013 | QMP combo PHY: initial mode for static bridges, no PM suspend at boot | Jens Glathe, Loic Poulain | USB-C, DisplayPort alt mode |
| 0012, 0022–0025, 0031–0037 | msm display and GPU: X1E catalog, clock factor, gamma, resume clock, PSR SDP flush, standalone GPU/GMU device model, no OPP rate 0 when the DP link stream stops | William Larson, Jens Glathe, Stephan Gerhold, Xilin Wu, Lars Karlslund, Konrad Dybcio, Akhil P Oommen | display, GPU acceleration, backlight, suspend |
| 0014 | Denali firmware paths in the OLED device tree | Jens Glathe | ADSP, CDSP, GPU firmware |
| 0015, 0016 | ath12k `disable-rfkill` device-tree property, set on the Denali Wi-Fi node | Dale Whinham | Wi-Fi (hard-blocked otherwise) |
| 0017 | Surface Aggregator: the DT default no longer assumes the EC closes its serial handle in D3 (SP11 suspend fix) | Dale Whinham | keyboard, touchpad, tablet switch after resume |
| 0018 | ADSP audio PD remote heap region | Ekansh Gupta | the FastRPC setup the sensors stack was verified with |
| 0019–0021 | LPASS WSA and VA macros on the PM clock framework, optional NPL clock | Ajay Kumar Nandam | speakers, microphone (base of 0053) |
| 0026–0030 | PS8830 retimer: USB4 off, DP alt-mode states, config delay | Jens Glathe | USB-C, DisplayPort alt mode |
| 0038–0041 | apply clock defaults only once the PHY is powered (driver core, DP, eUSB2, dwc3-qcom) | Stephan Gerhold, Jens Glathe | USB, DisplayPort |
| 0042 | OLED panel: maximum link rate from ACPI when the DPCD reports 0 | Jérôme de Bretagne | display on the non-5G SKUs (the DMI match excludes the 5G SKU) |
| 0043, 0044 | dwc3 `snps,reinit-phy-on-resume` | Oliver White | USB after resume |
| 0045–0047 | Surface platform profile and fan without ACPI | Leon Silcott (ooaklee) | power profiles, fan readout |
| 0048, 0049 | GPI DMA and GENI SPI in QSPI mode | x1e-nixos, ooaklee | touchscreen, pen |
| 0050 | MSHW0485 touchscreen driver with the iptsd HIDRAW bridge | ooaklee, Leon Silcott, Justin White | touchscreen, multi-touch, pen |
| 0051–0054 | SoundWire feedback ports, AudioReach speaker protection graph, WSA8845 and LPASS macros, x1e80100 VI/CPS backends | geocausa (SP11X1e-audio), ported by Leon Silcott | speakers, microphone |
| 0055 | surface_battery: no second battery on the SP11 | Justin White | battery |
| 0056 | Denali device tree: touch controller, audio feedback links, volume keys, USB PHY re-init, no cluster idle states | x1e-nixos, ooaklee, Leon Silcott | touch, audio, volume keys, suspend |
| 0057 | POS tablet-mode switch for the Surface Pro 11 | this repository | tablet mode, auto-rotation |
| 0058 | SoundWire: accept the controller's highest master port again (7.2.6's port check refuses it) | this repository | speakers (the CPS feedback of the speaker protection) |

## Left out of v23.2, and the device check for each

Nothing here drives hardware the feature table depends on; each entry ends with what the device check of
2026-09-23 covered.

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
  2026-09-23), and the feature table lists cameras as not working; left out until a camera fix.
- The spi-hid series (unused: the MSHW0485 driver frames HID-over-SPI itself) and the uncalled
  `qcom_geni_spi_biosref_xfer()` helper.
- Debug output (DP, QMP combo, drm_dp_helper, UCSI feature print), the DPU underflow colour, DP audio (the Denali
  sound card has no DisplayPort DAI), other laptops' device trees, panels, EC and QSEECOM entries, EL2, X1P.
