# SP11 patch set

The SP11 patch set is the branch `sp11/<version>` of the project's kernel fork (`KERNEL_PATCH_REPO` in `sp11.conf`):
one commit per patch, with its original author, on the stable tag whose tree Fedora's source tarball carries. The
pipeline:

1. `sp11.conf` pins the base and the head commit (`KERNEL_PATCH_BASE_COMMIT`, `KERNEL_PATCH_COMMIT`).
2. Step 10 writes the pinned commits out as a series; step 20 checks it against the pinned tree and feeds it to
   `kernel.spec`'s `linux-kernel-test.patch` slot (`docs/kernel.md`).
3. `payload/kernel-local` sets the patch set's three new symbols and enables two drivers Fedora leaves out.
4. Every change needs a new `KERNEL_SP11_REV`, which restarts at 1 with a new Fedora kernel version; a pushed
   branch is never rewritten: fixes go on top, a new base on a new branch.

License: GPL-2.0 like the kernel files they modify; `mshw0485_touch.c` and its headers carry SPDX lines.

## Where they come from

Dates and Fedora kernels: the revision table in `docs/kernel.md`. Adapted commits carry an `[sp11: ...]` note
after their trailers that names the source and the change.

### Revision 1: the extraction from v23.2

- Source: ooaklee's linux_ms_dev_kit-sp11 release `sp11-qcom-x1e-7.2.0-jg-0sp11v23` (`ce78e6ebc3d7`) with the 7.2.5
  stable update (the v23.2 kernel of `docs/kernel.md`).
- Result: 61 patches reproducing 70 of the 80 files they touch byte for byte from v23.2; the other 10 differ only
  by the parts left out (below). In the numbering of the current branch `sp11/7.2.11`:
  - 0001–0041: jglathe's 7.2.0 commits (`746b3477`) that touch code or nodes this machine uses; 0014 lacks a
    jglathe-only X1P file, 0030 keeps only its Denali hunk.
  - 0042–0047: ooaklee's branch commits as they are (OLED link-rate quirk, dwc3 PHY re-init, platform profile).
  - 0048–0056: ooaklee's work as topic patches (touch and pen, audio, the Surface battery guard, the Denali device
    tree) whose headers name the source commits and authors.
  - 0057: this repository's POS tablet-mode switch.
- The patches moved into the fork as `sp11/7.2.5` (head `df9cc406`) with revisions 3 and 4; only the POS switch's
  author changed. Revision 2's CDSP boot-order patch did not help and was dropped.

### Revision 5: the rebase onto 7.2.7

- `sp11/7.2.7` (head `8ed6c0df`, tree `1ec390ba`): the 61 commits rebased onto `v7.2.7` in one step
  (`git rebase --onto v7.2.7 v7.2.5`) plus one new commit.
- Dropped, upstream in 7.2.6: the DP EDID update, the DPU and DSI `dev_pm_opp_set_rate(0)` removals, the Denali QMP
  PHY supplies.
- Adapted: 0031 keeps only the `msm_dp_ctrl_off_link_stream()` hunk that 7.2.6's version of the fix lacks; 0049's
  QSPI path returns `-EPROBE_DEFER` directly, since 7.2.6's `spi_geni_init()` lost the `out_pm` label it used;
  0052 takes 7.2.6's `q6apm_graph_start()` and keeps its guard in `q6apm_graph_stop()`.
- New: 0058, since 7.2.6's port check in `qcom_swrm_stream_alloc_ports()` refuses the controller's highest master
  port, the amplifiers' CPS feedback (13 of 13).
- Old numbers to new: 0001–0023 unchanged, 0025–0031 to 0024–0030, 0033 to 0031, 0035–0044 to 0032–0041, 0046–0061
  to 0042–0057.

### Revisions 6 to 9: the cameras

- Revision 6: twelve commits on top of revision 5 (0059–0070, `docs/camera.md`); every driver file equals
  turbineBMW's 7.3 port. Sources: ten commits of turbineBMW/surface-pro-11-linux's `sp11-camera-review` (bundle
  `kernel/sp11-camera-review.bundle` at `15e590c3`, sha256 `bacf60dc…`, on Linux 7.1.3) minus its three ath12k
  rfkill commits (0015 and 0016 here); turbineBMW's OV13858 retry (branch `integration/review10-camera-switch`);
  ooaklee's IMX681 exposure fix (linux_ms_dev_kit-sp11 `b1754869f458`, only its `imx681.c` hunk).
- Adapted in revision 6: 0064 (C-PHY) is rebased around 7.2's CSID test pattern generator routing
  (`4b14db418b6e`, `51fe835c485b`); 0065 and 0068 add their lines to this series' Denali tree; 0062 puts the
  IMX681 Kconfig and Makefile entries after MAX9271's, clear of Fedora's IMX471 hunks in `patch-7.2-redhat.patch`.
- Revision 7, 0071 (this repository): the front camera's light (TLMM GPIO 225, active high) as the IMX681's
  `privacy` GPIO LED, switched by the V4L2 core with the stream.
- Revision 8, 0072: the IMX681's frame length at the 24-bit register `0x033d` the sensor uses, not the ignored
  `0x0340`. Revisions 6 to 8 pushed together 2026-09-28 (head `95a74f27`, tree `9d1a0c38`).
- Revision 9: 0073, the OV13858's lowest pixel rate from the lowest link frequency (the 270 MHz modes had reported
  432 instead of 216 MHz, halving libcamera's line and exposure times); 0074, the IMX681's controls applied at
  stream start under the control handler's lock (`v4l2_ctrl_handler_setup()`). Pushed 2026-09-28 (head
  `30c57e66`, tree `5ef459c8`).

### Revisions 10, 11 and 7.2.11 revision 1: rebases without a change

- The 74 commits rebased unchanged onto `v7.2.8` (`sp11/7.2.8`, head `c9a90d97`, tree `6b506039`, pushed
  2026-10-05), `v7.2.9` (`sp11/7.2.9`, head `0fdddb4d`, tree `c94f9d28`, 2026-10-08) and `v7.2.11`
  (`sp11/7.2.11`, head `56b04f67`, tree `a7a10207`, 2026-10-19); every number stays.

### 7.2.11 revision 2: three battery-driver fixes

- 0075–0077, carried unchanged from lkarlslund/linux-x1e-t14s (branch `t14s/jens-7.3`, which carries them as
  pending upstream fixes); found by a comparison with lkarlslund/linux-x1e-jglathe on 2026-10-22. Pushed 2026-10-22
  (head `e1de27e3`, tree `0977cb32`).

### 7.2.11 revision 3: the 5G SKU's device tree

- 0078 (this repository): `x1e80100-microsoft-denali-oled-5g.dts`, the OLED tree plus the Snapdragon X65 modem on
  PCIe 5, wired as on Qualcomm's CRD (`docs/modem.md`). The OLED tree is unchanged (its DTB is revision 2's byte
  for byte) and goes to the SKUs without a modem. Pushed 2026-10-23 (head `a4c9a6c7`, tree `870d479a`).

### 7.2.11 revisions 4 and 5: deep sleep

- Revision 4: 0079–0081, carried unchanged from mainline (all in `v7.3-rc1`), chosen by the sleep rounds of
  2026-10-27 (`docs/sleep.md`): 0079 (`d4c79b63d82d`) lets native hot-plug root ports enter D3 on non-x86, so a
  sleep takes the PCIe links down; 0080 (`d0cd9c8d0fd5`) makes an open GENI UART release its clocks, interconnect
  votes and CX level in system sleep; 0081 (`6f5569203bb6`) makes the crypto engine vote for memory bandwidth only
  while busy.
- Left out: mainline's fix of 0080 (`3098c989bd38`), which concerns only serial consoles with
  `no_console_suspend`; a change to the bandwidth monitors (`icc_bwmon`), whose votes are active-only and drop out
  of the sleep set by themselves.
- Revision 5: 0082 (this repository): `mhi-pci-generic` no longer aborts a system suspend when the modem refuses
  M3 (pending transfers, as while ModemManager probes the modem restarted by the last wake); it powers MHI down as
  for hibernation and restarts the modem through its recovery on resume. Mainline has no such change (its `no_m3`
  support of 7.3 is for devices without M3). Both pushed 2026-10-28 (head `f9f03105`, tree `bc657515`).

### 7.2.11 revision 7: Type-C switch array, GPU fixes, video codec

- 0083–0089, found by the 2026-10-26 comparison with jglathe's linux_ms_dev_kit, which carries all but 0089. The
  six posted ones are carried from their postings, each note giving its message-id; 0085's last hunk applies with
  less context (7.2 calls `a6xx_gmu_rpmh_dep_votes_init()` above it), the change being the same as in jglathe's
  tree.
- 0083: the Type-C switch lookup initializes the array it checks for duplicates (a fix of 7.2.5's duplicate check;
  it does not fix the reversed USB-C plug, `docs/hardware.md`). 0084–0088: five fixes of Qualcomm's "drm/msm:
  Assorted fixes - October" series (patches 2 to 6, posted 2026-10-24). 0089 (this repository): the Denali tree
  enables Iris, the video codec, with the Surface's `qcvss8380.mbn` (shipped by support 3.8).
- Revision 6 (2026-10-28, a device test only) also carried Brian Masney's clock `sync_state` series between 0088
  and the codec; it is left out (below). Pushed 2026-10-29 (head `7f035fc3`, tree `d9bc0070`).

### 7.2.11 revision 8: the 5G modem's MBIM data channels

- 0090 (this repository): `mhi-pci-generic` matches the modem by its subsystem (`17cb:0308`, subsystem
  `17cb:0308`) and gives it the generic channel set with the hardware data channels named `IP_HW0_MBIM`, for
  `mhi_wwan_mbim`, without the software data channels, and a 32 kB MRU. The modem frames its data as MBIM NTBs,
  which `mhi_net`, the bare entry's data driver, cannot carry (`docs/modem.md`, Mobile data). Mainline has no entry
  for this modem.
- A module build of the same `pci_generic.c` on revision 7 passed the device test first; revision 8 passed the
  same day and was pushed (head `86f4bc1a`, tree `f5de3f91`).

## Contents

The patches by number, with their origin and what each is needed for.

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
| 0059–0061 | CAMSS binding resources, OV13858 and VD55G0 bindings, the X1E80100 camera nodes (camera clock controller, CAMSS, CCI) | turbineBMW | cameras |
| 0062 | camera sensors: IMX681 driver, OV13858 device-tree support and Surface Pro 11 mode, VD55G0 (STMicroelectronics' GPL driver) | turbineBMW | cameras |
| 0063, 0064, 0067 | CAMSS: unwind failed stream starts, X1E80100 C-PHY links, the Denali C-PHY sequence observed on the device | turbineBMW | front camera |
| 0065, 0068 | Denali device tree: camera rails, clocks, CCI buses and CAMSS endpoints of the three cameras; the IR illuminator on the PM8550 flash controller | turbineBMW | cameras |
| 0066 | provenance record of the camera sources | turbineBMW | — |
| 0069 | OV13858: retry the first register write after power-up | turbineBMW | rear camera |
| 0070 | IMX681: exposure through the 24-bit coarse integration register | Leon Silcott (ooaklee) | front camera exposure |
| 0071 | Denali device tree: the front camera's privacy LED on GPIO 225 | this repository | the light next to the front camera while it streams |
| 0072 | IMX681: the frame length at `0x033d`, the sensor's line time, an exposure margin of 8 lines | this repository | a third more exposure at 30 fps; the vertical blanking sets the frame rate |
| 0073 | OV13858: the lowest pixel rate from the lowest link frequency | this repository | the rear camera's line and exposure times in libcamera |
| 0074 | IMX681: the controls applied at stream start under the control handler's lock | this repository | no race with control changes at stream start |
| 0075 | qcom_battmgr: the `capacity` property on X1E80100, lost when the variant got its own property table | Liviu Nicoara | the battery percentage from the kernel |
| 0076 | qcom_battmgr: `Full` instead of `Not charging` for a full battery on external power | Bjorn Andersson | the battery state on the charger |
| 0077 | qcom_battmgr: a change notice from the AC, USB and wireless supplies when the charging source changes | Brandon Williams (turbineBMW) | UPower's on-battery state after the charger is plugged in or out |
| 0078 | Device tree of the 5G SKU: the OLED tree plus the Snapdragon X65 modem on PCIe 5 (supply switch on TLMM 221, reset 149, CLKREQ# 150), as on the CRD | this repository | the 5G modem and its GNSS receiver (`docs/modem.md`) |
| 0079 | PCI: D3 for native hot-plug root ports on non-x86 | Manivannan Sadhasivam (mainline `d4c79b63d82d`) | the PCIe links down in sleep, so the memory reaches its low-power mode |
| 0080 | GENI serial: force runtime suspend in system sleep | Praveen Talari (mainline `d0cd9c8d0fd5`) | the UARTs' QUP and CX votes released in sleep |
| 0081 | Crypto engine: runtime PM, memory bandwidth only while busy | Udit Tiwari (mainline `6f5569203bb6`) | the crypto engine's 394 MB/s memory vote gone in sleep |
| 0082 | MHI PCI: power a busy modem down for system suspend instead of aborting it | this repository | deep sleep shortly after a wake (no `s2idle` fallback) |
| 0083 | Type-C mux: initialize the orientation switch array | Haobo Cheng (posted 2026-08-04) | the orientation switch chain (not the reversed plug) |
| 0084–0088 | Adreno GMU shutdown idle check, boot-up bandwidth vote, devfreq idle time, scheduler priority, preemption records across suspend | Jie Zhang, Akhil P Oommen (posted 2026-10-24) | GPU stability around its idle power-downs, a little power while awake |
| 0089 | Denali device tree: the video codec with the Surface's firmware | this repository | hardware video decoding and encoding |
| 0090 | MHI PCI: the Surface Pro 11 5G modem's data channels for the MBIM driver | this repository | mobile data (`docs/modem.md`) |

## Left out of v23.2

Nothing here drives hardware the feature table depends on; in parentheses, what the device check covered.

- Ubuntu's packaging, annotations, out-of-tree drivers and SAUCE patches: the eDP PHY regulator-load removal
  (display), the ps883x accessibility-check revert (USB-C), a UCSI connector-cleanup race fix (USB-C unplug).
- The ADSP attach series (remoteproc, SMP2P, pmic_glink probe order): mainline's PAS driver restarts the ADSP itself
  (`docs/kernel.md`; audio, battery, sensors, USB-C after boot).
- The clock `sync_state` series and a gcc UFS log change; the kernel arguments keep unused clocks and power domains
  on (boot, suspend). Its v3 (Brian Masney, 2026-06-26) was tested in 7.2.11 revision 6: with `clk_ignore_unused`
  it left only the AOSS clock provider waiting for `sync_state` (its consumer, the QDSS trace hub `10004000.tpda`,
  has no driver loaded); boots without that argument, and without `pd_ignore_unused` too, switched the unused
  clocks off and worked, but `cxsd` stayed at 0 in a 10-minute sleep, and the eDP pixel clock logged "rcg didn't
  update its configuration" twice (`disp_cc_mdss_dptx3_pixel0_clk_src`) at the display's enable.
- The PCIe ASPM API series and ath12k's MAC-from-device-tree hack (Wi-Fi and NVMe, also after resume).
- v23.2's camera stack (far too dark): revision 6 carries turbineBMW's instead (0059–0070), revision 7 the privacy
  LED (0071).
- The spi-hid series (the MSHW0485 driver frames HID-over-SPI itself) and the uncalled
  `qcom_geni_spi_biosref_xfer()` helper.
- Debug output (DP, QMP combo, drm_dp_helper, UCSI), the DPU underflow colour, DP audio (Denali's sound card has no
  DisplayPort DAI).
- Other laptops' device trees, panels, EC and QSEECOM entries, EL2, X1P, Denali's ThinkPad T14s compatible and
  PMK8550 ADC (no driver in v23.2).

## Planned: drop the power key's waking press

Not started. The workaround in use is KDE's power button set to Lock screen (`docs/guide/troubleshooting.md`).

- The problem: `drivers/input/misc/pm8941-pwrkey.c` (bound to `qcom,pmk8350-pwrkey`, `pon_pwrkey` under
  `pmk8550_pon: pon@1300` in `hamoa-pmics.dtsi`) reports the press that woke the system, so a desktop whose power
  button means sleep sleeps again 1 to 6 s after every power-key wake (`docs/sleep.md`). The precedent is ACPI's
  `drivers/acpi/button.c`: it sets `button->suspended` in `.suspend`, clears it in `.resume`, and meanwhile reports
  only `acpi_pm_wakeup_event()`, no key.
- The driver in 7.2.11: a threaded handler (`IRQF_ONESHOT`) reads `PON_RT_STS` and reports press and release,
  with a press synthesized for a release without one; `.suspend` and `.resume` only arm and disarm the interrupt
  as a wake source. Fedora builds it as a module; `pm_wakeup_irq()` is not exported, `pm_wakeup_dev_event()` is.
- The commit: flag the sleep in `.suspend` when the device may wake the system; while the flag is set, account
  the wake with `pm_wakeup_dev_event()`, keep `last_status` current and report no key, the synthesized press
  included; clear the flag at the release that ends the waking press and after a wake from another source. The
  IRQ thread is not frozen and can run before `.resume`, so a flag cleared there alone races with the waking
  press: compare a `.complete` callback, a noirq check of the interrupt's pending state, and clearing on the first
  release. Make it opt-in (a device-tree property or a module parameter set for Denali): phones use the waking
  press to turn the screen on.
- In this project: a commit on top of the pinned `sp11/<version>` branch with a `[sp11: ...]` note, a host compile
  check of `drivers/input/misc` and the DTBs (`docs/kernel.md`, Rebase, step 4), the new pins, steps 10, 20 and
  36, a revision entry here and in `docs/kernel.md`'s table, the device round, the push after it.
- Device checks: no `Power key pressed short.` line from `systemd-logind` for the waking press, and KDE with the
  button on Sleep stays awake; `cat /sys/power/pm_wakeup_irq` still names the power key's interrupt; a press while
  awake still runs KDE's button action; after a wake by the cover the first press counts.
