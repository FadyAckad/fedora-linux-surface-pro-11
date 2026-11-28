# SP11 patch set

The SP11 patch set is the branch `sp11/<version>` of the project's kernel fork (the submodule `linux-sp11`):
one commit per patch, with its original author, on the stable tag whose tree Fedora's source tarball carries. The
pipeline:

1. `sp11.conf` pins the base commit (`KERNEL_PATCH_BASE_COMMIT`); the submodule's gitlink pins the head.
2. Step 10 writes the pinned commits out as a series; step 20 checks it against the pinned tree and feeds it to
   `kernel.spec`'s `linux-kernel-test.patch` slot (`docs/kernel.md`).
3. `payload/kernel-local` sets the patch set's four new symbols and enables one driver Fedora leaves out.
4. Every change needs a new `KERNEL_SP11_REV`, which restarts at 1 with a new Fedora kernel version; a pushed
   branch is never rewritten: fixes go on top, a new base on a new branch.

License: GPL-2.0 like the kernel files they modify; `mshw0485_touch.c` and its headers carry SPDX lines.

## Where they come from

Dates and Fedora kernels: the revision table in `docs/kernel.md`. One row per revision, with the head of the fork
branch it was pushed as and the patches it added, by the numbers of its own branch; a rebase names the patches it
dropped or adapted by the numbers of the branch it started from (Contents uses `sp11/7.3.5`'s). Adapted commits
carry an `[sp11: ...]` note after their trailers that names the source and the change.

| Revision | Fork head | What it added |
|---|---|---|
| 1 to 4 | `sp11/7.2.5` `df9cc406` (3 and 4) | 61 patches extracted from ooaklee's linux_ms_dev_kit-sp11 v23.2 (`sp11-qcom-x1e-7.2.0-jg-0sp11v23`, `ce78e6ebc3d7`, with the 7.2.5 update): jglathe's 7.2.0 commits (`746b3477`) that touch code or nodes this machine uses, ooaklee's branch commits (OLED link-rate quirk, dwc3 PHY re-init, platform profile) and topic patches (touch and pen, audio, the Surface battery guard, the Denali device tree), this repository's POS tablet-mode switch. They reproduce 70 of the 80 files they touch byte for byte; the other 10 differ by the parts left out (Left out of v23.2). Revision 2's CDSP boot-order patch did not help and was dropped; 3 and 4 changed the configuration only. |
| 5 | `sp11/7.2.7` `8ed6c0df` | rebased onto `v7.2.7`: the DP EDID update, the DPU and DSI `dev_pm_opp_set_rate(0)` removals and the Denali QMP PHY supplies dropped as upstream in 7.2.6, three adapted; new: 0058, 7.2.6's SoundWire port check made to accept the amplifiers' CPS feedback port 13 (`docs/kernel.md`, Rebase) |
| 6 to 9 | `95a74f27` (6 to 8), `30c57e66` (9) | the cameras, 0059–0074 (`docs/camera.md`): ten commits of turbineBMW/surface-pro-11-linux's `sp11-camera-review` (bundle at `15e590c3`, sha256 `bacf60dc…`, on Linux 7.1.3) without its three ath12k rfkill commits, turbineBMW's OV13858 retry (`integration/review10-camera-switch`) and ooaklee's IMX681 exposure fix (`b1754869f458`, its `imx681.c` hunk), every driver file equal to turbineBMW's 7.3 port; this repository's front-camera light (7), the IMX681's frame length at `0x033d` (8), the OV13858's lowest pixel rate and the IMX681's controls under the handler's lock (9) |
| 10, 11, 7.2.11 revision 1 | `sp11/7.2.8` `c9a90d97`, `sp11/7.2.9` `0fdddb4d`, `sp11/7.2.11` `56b04f67` | the 74 commits rebased unchanged onto `v7.2.8`, `v7.2.9` and `v7.2.11` |
| 7.2.11 revision 2 | `e1de27e3` | 0075–0077, three battery-driver fixes carried unchanged from lkarlslund/linux-x1e-t14s (`t14s/jens-7.3`), pending upstream there |
| 7.2.11 revision 3 | `a4c9a6c7` | 0078, the 5G SKU's device tree (`docs/modem.md`) |
| 7.2.11 revisions 4 and 5 | `f9f03105` | 0079–0081 from mainline `v7.3-rc1` (`d4c79b63d82d`, `d0cd9c8d0fd5`, `6f5569203bb6`: D3 for native hot-plug root ports on non-x86, GENI UARTs released in system sleep, the crypto engine's bandwidth vote only while busy; `docs/sleep.md`); 0082, a busy modem powered down for a system suspend (mainline's `no_m3` of 7.3 is for devices without M3) |
| 7.2.11 revision 6 | not pushed | a device test: revision 7 plus Brian Masney's clock `sync_state` series (Left out of v23.2) |
| 7.2.11 revision 7 | `7f035fc3` | 0083–0089, from a comparison with jglathe's tree on 2026-10-26: the Type-C switch array fix, five fixes of Qualcomm's "drm/msm: Assorted fixes - October" (patches 2 to 6, each note with its message-id), this repository's 0089, the video codec in the Denali tree |
| 7.2.11 revision 8 | `86f4bc1a` | 0090, the 5G modem's MBIM data channels in `mhi-pci-generic`; mainline has no entry for this modem (`docs/modem.md`, Mobile data) |
| 7.2.11 revisions 9 to 12 | not pushed | 0091, the modem's supply kept on through a sleep (`docs/modem.md`, Across a sleep); the first forms of 0092, the country re-sent when a radio starts (`docs/hardware.md`, Wi-Fi) |
| 7.2.11 revision 13 | `2155c742` | 0091 and the final 0092: a known country kept when the 11d scan reports none, restored when a radio starts |
| 7.2.14 revision 1 | `sp11/7.2.14` `db86d659` | the 92 commits rebased unchanged onto `v7.2.14` |
| 7.2.14 revision 2 | `1ca86c76` | 0093, no power-on in the touch controller's resume callback; 0094, the PCIe controllers suspended and resumed asynchronously, which mainline's `pcie-qcom.c` lacks (2026-11-02; `docs/sleep.md`, Wake) |
| 7.2.15 revision 1 | `sp11/7.2.15` `395b0aab` | the 94 commits rebased unchanged onto `v7.2.15`; 0095, the PS8830 retimer told of the connection 30 ms before its mode (`docs/hardware.md`, USB-C data) |
| 7.2.15 revision 2 | `7a8c230b` | 0096, the QRTR SMD probe's send lock released before a failed open's unregistration (`docs/kernel.md`, Sync state and the CDSP) |
| 7.3.3 revisions 1 and 2 | `sp11/7.3.3` `476df635` | rebased onto `v7.3.3`: 0013, 0018–0021, 0031 and 0079–0081 dropped as upstream in 7.3, 0049, 0053 and 0061 adapted (`docs/kernel.md`, Rebase), 0088 new (the crypto engine's node disabled); revision 2: 0089, upstream's PDC bypass for the GPIO wake interrupts (`602cb14e310a`) again, which 7.3 reverted with its PDC rework (`77fbc756d9cb`; `docs/sleep.md`) |
| 7.3.3 revision 3 | `fe43e1a3` | 0090–0111, Xilin Wu's series "drm/msm/dp: Add static HDR support for DP and eDP" from the list (v2 of 2026-10-09, `20261009-msm-dp-hdr10-v2-0-1835d4966da3@radxa.com`, with two fixes of v1; `docs/display.md`); adapted where it meets SP11 patches: 0099 and 0100 keep 0033's delayed clock defaults, 0102 keeps 0036's link-rate quirk ahead of the capability read, 0107 keeps the peripheral flush for a stream outside PSR |
| 7.3.3 revision 4 | `216231c9` | 0112 and 0113, patches 7 and 9 of Dmitry Baryshkov's "drm/msm: fix SMMU fault dumps" v5 (`20261024-fd-kms-fix-smmu-v5-0-a5b0b284aead@oss.qualcomm.com`), 0113 without its `dpu_crtc_atomic_check()` hunk (0018 had it) and dropping the loop that held 0017's gamma lines, so nothing of 0017 is left; 0114, the DSPPs reserved with every mode set (`docs/display.md`). Under review on 2026-11-12: the next rebase takes upstream's version and checks 0114 against it |
| 7.3.3 revision 5 | `e53fd0c5` | 0115 and 0116, PCIe 5 probed again once the modem asserts WAKE# (`docs/modem.md`, The link at boot) |
| 7.3.5 revision 1 | `sp11/7.3.5` `1b01078e` | rebased onto `v7.3.5`: 0003 (the pmic_glink altmode worker) and 0071 (the charger supplies' change notice) dropped as upstream since 7.3.4; 0046, the AudioReach patch, on 7.3.4's unmap and position fixes (`docs/kernel.md`, Rebase) |
| 7.3.5 revisions 2 and 3 | `d18c8996` | 0115 and 0116, the TPM behind `qcom.tz.mssecapp` (`docs/hardware.md`, TPM); 0117, its registration from a work item. Revision 2 was committed as `8de86335` and pushed with revision 3 |
| 7.3.5 revision 4 | `67d93d33` | 0118–0121 from the fork's pull request 1 for the X1P64100 LCD model, of which this project has no unit: Dale Whinham's backlight and `x1p64100.dtsi`, Friedrich Schrödter's `scmi-cpufreq` change, the pull request's video codec. Merged by GitHub's rebase merge: new ids, no signature, the tested authors, dates, messages and changes |

The maps across the two rebases onto 7.3, for the older numbers in the rows above and in `docs/verified.md`:

- `sp11/7.2.15` to `sp11/7.3.3`: 0001–0012 unchanged, 0014–0017 to 0013–0016, 0022–0030 to 0017–0025, 0032–0078 to
  0026–0072, 0082–0096 to 0073–0087; 0088 new.
- `sp11/7.3.3` to `sp11/7.3.5`: 0001 and 0002 unchanged, 0004–0070 to 0003–0069, 0072–0116 to 0070–0114.

## Contents

The patches by number in `sp11/7.3.5`, with their origin and what each is needed for.

| Patches | What | Origin | Needed for |
|---|---|---|---|
| 0001 | EFI stub: signal the before-ExitBootServices event group | Johan Hovold (T14s workaround, applies to every arm64 machine) | boot (kept until a boot without it is tested) |
| 0002 | UCSI connector worker on a freezable workqueue | Abel Vesa | USB-C across suspend (the pmic_glink altmode worker's fix is upstream since 7.3.4) |
| 0003–0005 | rpmsg announce order, an rpmsg helper to open an endpoint during probe (needed by 0005), QRTR SMD open/close races | Stephan Gerhold | ADSP services (audio, battery, sensors); 0005's probe deadlock is fixed by 0085 |
| 0006 | x1e80100 machine driver match data (Dell XPS 13 channel map) | Abel Vesa | prerequisite of 0047 |
| 0007 | qcom_battmgr request input checks | Jens Glathe | battery |
| 0008 | WCN7850 Bluetooth: drop the unused baud-rate event | Cheng Jiang | Bluetooth |
| 0009, 0010 | QMP combo PHY: initial mode for static bridges | Jens Glathe | USB-C, DisplayPort alt mode |
| 0011, 0016–0019, 0025–0030 | msm display and GPU: X1E catalog, clock factor, gamma, resume clock, PSR SDP flush, standalone GPU/GMU device model | William Larson, Jens Glathe, Stephan Gerhold, Xilin Wu, Lars Karlslund, Akhil P Oommen | display, GPU acceleration, backlight, suspend |
| 0012 | Denali firmware paths in the OLED device tree | Jens Glathe | ADSP, CDSP, GPU firmware |
| 0013, 0014 | ath12k `disable-rfkill` device-tree property, set on the Denali Wi-Fi node | Dale Whinham | Wi-Fi (hard-blocked otherwise) |
| 0015 | Surface Aggregator: the DT default no longer assumes the EC closes its serial handle in D3 (SP11 suspend fix) | Dale Whinham | keyboard, touchpad, tablet switch after resume |
| 0020–0024 | PS8830 retimer: USB4 off, DP alt-mode states, config delay | Jens Glathe | USB-C, DisplayPort alt mode |
| 0031–0034 | apply clock defaults only once the PHY is powered (driver core, DP, eUSB2, dwc3-qcom) | Stephan Gerhold, Jens Glathe | USB, DisplayPort |
| 0035 | OLED panel: maximum link rate from ACPI when the DPCD reports 0 | Jérôme de Bretagne | display on the non-5G SKUs (the DMI match excludes the 5G SKU) |
| 0036, 0037 | dwc3 `snps,reinit-phy-on-resume` | Oliver White | USB after resume |
| 0038–0040 | Surface platform profile and fan without ACPI | Leon Silcott (ooaklee) | power profiles, fan readout |
| 0041, 0042 | GPI DMA and GENI SPI in QSPI mode | x1e-nixos, ooaklee | touchscreen, pen |
| 0043 | MSHW0485 touchscreen driver with the iptsd HIDRAW bridge | ooaklee, Leon Silcott, Justin White | touchscreen, multi-touch, pen |
| 0044–0047 | SoundWire feedback ports, AudioReach speaker protection graph, WSA8845 and LPASS macros, x1e80100 VI/CPS backends | geocausa (SP11X1e-audio), ported by Leon Silcott | speakers, microphone (the LPASS macros on upstream's PM-clock drivers since 7.3.3 revision 1) |
| 0048 | surface_battery: no second battery on the SP11 | Justin White | battery |
| 0049 | Denali device tree: touch controller, audio feedback links, volume keys, USB PHY re-init, no cluster idle states | x1e-nixos, ooaklee, Leon Silcott | touch, audio, volume keys, suspend |
| 0050 | POS tablet-mode switch for the Surface Pro 11 | this repository | tablet mode, auto-rotation |
| 0051 | SoundWire: accept the controller's highest master port again (7.2.6's port check refuses it) | this repository | speakers (the CPS feedback of the speaker protection) |
| 0052–0054 | CAMSS binding resources, OV13858 and VD55G0 bindings, the X1E80100 camera nodes (camera clock controller, CAMSS, CCI) | turbineBMW | cameras |
| 0055 | camera sensors: IMX681 driver, OV13858 device-tree support and Surface Pro 11 mode, VD55G0 (STMicroelectronics' GPL driver) | turbineBMW | cameras |
| 0056, 0057, 0060 | CAMSS: unwind failed stream starts, X1E80100 C-PHY links, the Denali C-PHY sequence observed on the device | turbineBMW | front camera |
| 0058, 0061 | Denali device tree: camera rails, clocks, CCI buses and CAMSS endpoints of the three cameras; the IR illuminator on the PM8550 flash controller | turbineBMW | cameras |
| 0059 | provenance record of the camera sources | turbineBMW | — |
| 0062 | OV13858: retry the first register write after power-up | turbineBMW | rear camera |
| 0063 | IMX681: exposure through the 24-bit coarse integration register | Leon Silcott (ooaklee) | front camera exposure |
| 0064 | Denali device tree: the front camera's privacy LED on GPIO 225 | this repository | the light next to the front camera while it streams |
| 0065 | IMX681: the frame length at `0x033d`, the sensor's line time, an exposure margin of 8 lines | this repository | a third more exposure at 30 fps; the vertical blanking sets the frame rate |
| 0066 | OV13858: the lowest pixel rate from the lowest link frequency | this repository | the rear camera's line and exposure times in libcamera |
| 0067 | IMX681: the controls applied at stream start under the control handler's lock | this repository | no race with control changes at stream start |
| 0068 | qcom_battmgr: the `capacity` property on X1E80100, lost when the variant got its own property table | Liviu Nicoara | the battery percentage from the kernel |
| 0069 | qcom_battmgr: `Full` instead of `Not charging` for a full battery on external power | Bjorn Andersson | the battery state on the charger |
| 0070 | Device tree of the 5G SKU: the OLED tree plus the Snapdragon X65 modem on PCIe 5 (supply switch on TLMM 221, reset 149, CLKREQ# 150), as on the CRD | this repository | the 5G modem and its GNSS receiver (`docs/modem.md`) |
| 0071 | MHI PCI: power a busy modem down for system suspend instead of aborting it | this repository | deep sleep shortly after a wake (no `s2idle` fallback) |
| 0072 | Type-C mux: initialize the orientation switch array | Haobo Cheng (posted 2026-08-04) | the orientation switch chain (not the reversed plug) |
| 0073–0077 | Adreno GMU shutdown idle check, boot-up bandwidth vote, devfreq idle time, scheduler priority, preemption records across suspend | Jie Zhang, Akhil P Oommen (posted 2026-10-24) | GPU stability around its idle power-downs, a little power while awake |
| 0078 | Denali device tree: the video codec with the Surface's firmware | this repository | hardware video decoding and encoding |
| 0079 | MHI PCI: the Surface Pro 11 5G modem's data channels for the MBIM driver | this repository | mobile data (`docs/modem.md`) |
| 0080 | 5G device tree: the modem's supply stays on through a system sleep | this repository | mobile data back within seconds of a wake (`docs/modem.md`, Across a sleep) |
| 0081 | ath12k: a known country kept when the 11d scan reports none, restored when a radio starts | this repository | the first Wi-Fi scan after a wake with the country known (`docs/hardware.md`, Wi-Fi) |
| 0082 | MSHW0485 touch: no power-on in the resume callback; the recovery work powers the controller, once | this repository | 0.8 s less in a wake's resume phase (`docs/sleep.md`, Wake) |
| 0083 | PCIe (qcom): the controllers suspend and resume asynchronously | this repository | the three links resumed side by side, about 0.65 s less in a wake |
| 0084 | PS8830 retimer: the connection announced 30 ms before its mode | this repository | USB 3 with the plug reversed (`docs/hardware.md`, USB-C data) |
| 0085 | QRTR SMD: the probe's send lock released before a failed open's unregistration | this repository | boots that sat 212 s in dracut-initqueue and ran without battery, Wi-Fi and sensors (`docs/kernel.md`, Sync state and the CDSP) |
| 0086 | Denali device tree: the crypto engine's node disabled | this repository | no user of the interconnect without a driver, since 7.3 marks the engine's driver `BROKEN` (`docs/kernel.md`, Sync state and the CDSP) |
| 0087 | X1E80100 pin controller: GPIO wake interrupts stay on the TLMM summary interrupt, not the PDC (7.2's state) | this repository | a suspend with the lid open that holds; 7.3's PDC wake path woke it at once (`docs/sleep.md`) |
| 0088, 0089 | DP: hot-plug state updates serialized, the debugfs connector pointer initialized | Xilin Wu (posted 2026-09-30; 0088 in msm-next) | prerequisites of 0090–0109 |
| 0090–0092 | DRM core: `max bpc` attached before a connector has a state, and by the bridge connector for non-HDMI chains | Xilin Wu (posted 2026-10-09) | 10 bits per colour on DP and eDP |
| 0093–0109 | DP and eDP: the output bit depth, the BT.2020 VSC packet, the HDR static metadata packet, `Colorspace` and `HDR_OUTPUT_METADATA`; stream enable, PHY power and the eDP capability read reworked | Xilin Wu (posted 2026-10-09) | HDR (`docs/display.md`) |
| 0110, 0111 | DPU: a mixer's DSPP pointer cleared when a mode set leaves it without one; a mode set asked for only by a CRTC that has a CTM or gamma LUT and no DSPP (in place of 0016's forced mode set) | Dmitry Baryshkov (posted 2026-10-24) | no mode set when a gamma table or CTM comes or goes |
| 0112 | DPU: the mixers' DSPPs reserved with every mode set while mixers with a free one are left | this repository | a compositor's first gamma table without a mode set and the panel's power cycle (`docs/display.md`) |
| 0113 | PCIe (qcom): the controller probed again, from a work item, once an endpoint whose link missed the probe asserts WAKE# | this repository | the 5G modem in a boot where it is not ready at the first probe (`docs/modem.md`, The link at boot) |
| 0114 | 5G device tree: the modem's WAKE# (TLMM 151) in PCIe 5's controller node, with its pin state | this repository | 0113's wait for the modem |
| 0115 | QSEECOM: a client device for the TrustZone application `qcom.tz.mssecapp` | this repository | 0116 |
| 0116 | TPM: `tpm_qcom_mssecapp`, the TPM 2.0 behind `qcom.tz.mssecapp` (ACPI start method 14's CRB) | this repository | the TPM under Linux (`docs/hardware.md`, TPM) |
| 0117 | TPM: `tpm_qcom_mssecapp` registers the chip from a work item | this repository | a kernel start that does not wait for the TPM's first self test |
| 0118 | LCD device tree: a `pwm-backlight` on the PMK8550 PWM with its supply and enable lines; the panel's compatible and enable line move from the common file into the two board files | Dale Whinham (dwhinham/linux-sp11) | the LCD model's brightness (reported by owners of LCD units, not tested here) |
| 0119 | `x1p64100.dtsi`: `hamoa.dtsi` without the two cores the X1P64100 lacks, for the LCD tree | Dale Whinham (dwhinham/linux-sp11) | the LCD model's ten cores without PSCI's refusal of CPUs 7 and 11 (reported) |
| 0120 | scmi-cpufreq: a frequency table made only of boost entries is used as regular frequencies | Friedrich Schrödter (dwhinham/linux-sp11) | frequency scaling on the LCD model's clusters 1 and 2 (reported) |
| 0121 | LCD device tree: the video codec enabled with `qcvss8380.mbn`, as in the OLED tree | Openanonwriter (the fork's pull request 1) | hardware video on the LCD model (reported) |

## Left out of v23.2

Nothing here drives hardware the feature table depends on; in parentheses, what the device check covered.

- Ubuntu's packaging, annotations, out-of-tree drivers and SAUCE patches: the eDP PHY regulator-load removal
  (display), the ps883x accessibility-check revert (USB-C), a UCSI connector-cleanup race fix (USB-C unplug).
- The ADSP attach series (remoteproc, SMP2P, pmic_glink probe order): mainline's PAS driver restarts the ADSP itself
  (`docs/kernel.md`; audio, battery, sensors, USB-C after boot).
- The clock `sync_state` series and a gcc UFS log change; the kernel arguments keep unused clocks and power domains
  on (boot, suspend). Its v3 (Brian Masney, 2026-06-26), tried in 7.2.11 revision 6, left the AOSS clock provider
  waiting for `sync_state` (its consumer, the QDSS trace hub `10004000.tpda`, has no driver loaded); without
  `clk_ignore_unused` and `pd_ignore_unused` the unused clocks went off and the boot worked, but `cxsd` stayed at 0
  in a sleep and the eDP pixel clock logged "rcg didn't update its configuration" twice at the display's enable.
- The PCIe ASPM API series and ath12k's MAC-from-device-tree hack (Wi-Fi and NVMe, also after resume).
- v23.2's camera stack (far too dark): revision 6 carries turbineBMW's instead (0052–0063 in the current
  numbering), revision 7 the privacy LED (0064).
- The spi-hid series (the MSHW0485 driver frames HID-over-SPI itself) and the uncalled
  `qcom_geni_spi_biosref_xfer()` helper.
- Debug output (DP, QMP combo, drm_dp_helper, UCSI), the DPU underflow colour, DP audio (Denali's sound card has no
  DisplayPort DAI).
- Other laptops' device trees, panels, EC and QSEECOM entries, EL2, X1P, Denali's ThinkPad T14s compatible and
  PMK8550 ADC (no driver in v23.2).
