# SP11 patch set

The SP11 patch set is the branch `sp11/<version>` of the project's kernel fork (the submodule `linux-sp11`):
one commit per patch, with its original author, on the stable tag whose tree Fedora's source tarball carries. The
pipeline:

1. `sp11.conf` pins the base commit (`KERNEL_PATCH_BASE_COMMIT`); the submodule's gitlink pins the head.
2. Step 10 writes the pinned commits out as a series; step 20 checks it against the pinned tree and feeds it to
   `kernel.spec`'s `linux-kernel-test.patch` slot (`docs/kernel.md`).
3. `payload/kernel-local` sets the patch set's three new symbols and enables one driver Fedora leaves out.
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
  by the parts left out (below). In the numbering of the branch `sp11/7.2.15` (the map to `sp11/7.3.3` is under
  7.3.3 revision 1):
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

### 7.2.11 revision 9: the modem kept powered through a sleep, Wi-Fi's country restored after it

- 0091 (this repository): the 5G device tree keeps the modem's supply `vreg_wwan` on (`regulator-always-on`)
  and no longer hands it to PCIe 5 as `vddpe-3v3-supply`, so a deep sleep takes the link down but not the
  modem's power; the change the test tree of 2026-10-29 carried (`docs/modem.md`, Across a sleep).
- 0092 (this repository): ath12k sends the firmware the country its 11d scan found before (`ar->alpha2`) when
  a radio starts, as `reconfig_complete` does after a crash recovery; the firmware restarts in world roaming
  after every system suspend and the driver never told it (`docs/hardware.md`, Wi-Fi). A boot has no country
  yet; the 11d scan still runs and replaces a stale country before an association.
- The device round of 2026-10-31: 0091 and ModemManager's quick resume passed (mobile data 2.0 s after a wake,
  the night at 0.32 W); 0092's answer from the firmware was dropped by the `regd_updated` gate, so the first scan
  after a wake still ran in world roaming. Not pushed; revision 10 carries the fix.

### 7.2.11 revisions 10 and 11: the country re-send waits for the firmware's answer

- 0091 unchanged. 0092 reworked: after sending the country, `ath12k_mac_start` waits up to 500 ms for the
  firmware's regulatory answer (`regd_update_completed`), clears the `regd_updated` gate and applies the answer,
  so the interfaces added right after and the first scan see the country's channel list; a `00` country (the
  registration's default without an SMBIOS code) is not sent.
- Revision 10 waited for any regulatory event and lost the race once in two wakes: the firmware's own first
  event after the restart completed the wait, the world rules were applied, the answer was dropped. Revision 11
  loops on the completion until `ab->reg_info` carries the restored country, within the 500 ms, and applies it;
  without such an answer the start goes on with a warning and the behaviour of revision 8. On the device
  (2026-11-01) the answer was found and the world rules were still applied at both wakes.

### 7.2.11 revision 12: the country re-send with diagnostics

- 0092 again: every stored regulatory event, every apply to the wiphy and the restore's steps logged at info
  level; the regulatory event handler clears the `regd_updated` gate so that a changed country is applied, and
  sends the known country again (twice at most per start) when the firmware reports world roaming while a
  country is known. The device round (2026-11-01) showed the real cause at the sleep: the 11d scan, stopped by
  the link going down, reports `00`, which the driver takes over as the known country; neither guard mattered.

### 7.2.11 revision 13: the country kept across a sleep

- 0092 in its final form: `ath12k_reg_11d_new_cc_event` keeps a known country when the 11d scan reports `00`
  (and sends nothing to the firmware then); `ath12k_mac_start` sends the known country, waits up to 500 ms for
  the answer that carries it, clears the `regd_updated` gate and applies it; without an answer the start goes
  on with a warning. No diagnostics, no re-send, no gate release in the event handler. Passed its device round
  on 2026-11-01 (`DE` before the first scan at both wakes, Wi-Fi online after 13.2 and 13.5 s). Pushed 2026-11-01
  (head `2155c742`, tree `e202be02`).

### 7.2.14 revision 1: a rebase without a change

- The 92 commits rebased unchanged onto `v7.2.14` (`sp11/7.2.14`, head `db86d659`, tree `46612749`, pushed
  2026-11-02); every number stays. The stable update itself brings the Wi-Fi power sequencer's reset of the chip
  at its probe, which the Wi-Fi boot campaign's test patch had planned (`docs/hardware.md`, Wi-Fi).

### 7.2.14 revision 2: the wake's resume path

- 0093 (this repository): `g6ts_resume()` in `mshw0485_touch.c` no longer runs `g6ts_power_on()`, whose 500 and
  300 ms delays held the PM core's resume phase; the recovery work the callback schedules powers the controller off
  and on again on its hardware path anyway, so the callback's power-on was undone 100 ms later (`docs/sleep.md`,
  Wake).
- 0094 (this repository): `qcom_pcie_probe()` enables asynchronous suspend and resume for the controller
  (`device_enable_async_suspend()`), as the PCI core does for the host bridges, ports and devices below it, so the
  three controllers' link resumes of 0.31 to 0.36 s overlap instead of following one another in the noirq phase.
  Mainline's `pcie-qcom.c` has no such change (2026-11-02).
- Passed its device round on 2026-11-02 (`docs/sleep.md`, Wake) and pushed the same evening (head `1ca86c76`,
  tree `e42be2f1`, the tree the kernel was built from).

### 7.2.15 revision 1: the rebase and the reversed USB-C plug

- The 94 commits rebased unchanged onto `v7.2.15` (`docs/kernel.md`, Rebase to a new Fedora kernel).
- 0095 (this repository): `ps883x_configure()` writes the PS8830 retimer's connection-status registers in two
  steps when the retimer comes out of reset: `0x01` (connection present) and, 30 ms later, the configuration
  (orientation and mode). Given the final word at once, the retimer brought up no USB 3 link with the plug
  reversed on either port; the two-step write, replayed on the live retimer of a stuck port, trained the link
  within a second (`docs/hardware.md`, USB-C data). Windows configures the chip the same way. A mode change on
  an existing connection is written at once, as before.
- Passed its device round on 2026-11-03: the stick at 5000 Mb/s turned over and the usual way on both ports, after
  a wake and in a second boot (`docs/verified.md`). Pushed the same day (head `395b0aab`, tree `a90da6df`, the
  tree the kernel was built from).

### 7.2.15 revision 2: the QRTR probe deadlock

- 0096 (this repository): `qcom_smd_qrtr_probe()` (0006's version of `net/qrtr/smd.c`) holds its send lock only
  across the endpoint registration and the channel open, no longer through the unregistration a failed open
  does. Held there, it deadlocked with a QRTR broadcast of the same moment: the name server, holding
  `qrtr_node_lock` and the node's `ep_lock`, blocked in the send on the lock; the probe then blocked in
  `qrtr_endpoint_unregister()` on `ep_lock`; every QRTR user queued behind `qrtr_node_lock`, and the glink edge's
  work behind the probed device's lock.
- The window is the 5 s the CDSP's IPCRTR open takes to time out in the initramfs (the CDSP announces the channel
  and never acknowledges the open; `failed to create endpoint`, `rpmsg_dev_probe: failed: -121`, the reason the
  initqueue ends at 7.1 s rather than 2.8 s in most boots). Three boots of 2026-11-05/06 had an ADSP service
  announced inside it: `dracut-initqueue` gave udev's queue up after 120 s, udevd survived its SIGKILL, the root
  was switched at 212 s, and the system ran without battery, Wi-Fi and sensors and could not shut down; the
  stacks of the stuck tasks (`/proc/<pid>/stack`, `sysrq w`) named the locks. With the lock released, a blocked
  sender finds no channel, drops its packet and the probe fails with `-121` as in the boots without a broadcast.
- Left as they are: the CDSP's unanswered open (5 s per boot that announces the channel early, no CDSP QRTR) and
  the name server's blocking send under `qrtr_node_lock`.
- Passed its device round on 2026-11-06: fourteen boots in a row ended the initqueue at 1.8 to 7.1 s (the CDSP's
  open still fails with `-121` in the 6.6 s boots, now without consequence), then the standard checks and a deep
  sleep (`docs/verified.md`). Pushed the same day (head `7a8c230b`, tree `085f9693`, the tree the kernel was
  built from).

### 7.3.3 revision 1: the rebase onto 7.3

- The 96 commits of `sp11/7.2.15` rebased onto `v7.3.3` (`docs/kernel.md`, Rebase to a new Fedora kernel): 87
  remain, plus one new patch.
- Dropped, upstream in 7.3: 0013 (`729e0af3c2b9`, the final form of the combo PHY's runtime-PM fix), 0018
  (`30ae66afcacf`), 0019 and 0020 (`cd054a6e272c`, `eb667d0fbdd3`, the author's final versions), 0021 (7.3 checks
  `clk_set_rate()`'s return, and `clk_set_rate(NULL)` is 0), 0031 (`cebfa9909e`), 0079 (`d4c79b63d82d`), 0080
  (`d0cd9c8d0fd5`, with the `no_console_suspend` fix `3098c989bd38` on top), 0081 (`6f5569203bb6`).
- Adapted (the `[sp11: ...]` notes name the changes): 0049 keeps 7.3's `qcom_geni_se` trace include, the
  `geni_spi` tracepoints and the register names of `geni-se.h` (the extracted patch had deleted the tracepoints
  and defined the set register as `SE_DMA_TX_IRQ_EN`, which 7.3's header names `SE_DMA_TX_IRQ_EN_SET`); 0053
  re-applies only its functional change to `lpass-wsa-macro.c` (the extracted patch had reverted 0019 and 0021,
  so the tested kernels ran the WSA macro on the clock handling that preceded the PM-clock conversion), sets the
  WSA884x PA event's fields under 7.3's `scoped_guard()` and drops the VA macro's Denali 19.2 MHz divider base:
  7.3's Denali tree asks for a 2.4 MHz DMIC rate (`35ce3c571297`), and both together gave a /8 divider instead of
  Windows' /4; 0061 drops its `camcc` node, upstream in 7.3 (`6a3568f938`, enabled by default; the Denali tree's
  `status = "okay"` stays, harmless).
- New: 0088 (this repository): the Denali tree disables the crypto engine's node, whose driver 7.3 marks `BROKEN`
  (`docs/kernel.md`, Sync state and the CDSP); `kernel-local` loses its six `CRYPTO_DEV_QCE` lines.
- Old numbers to new: 0001–0012 unchanged, 0014–0017 to 0013–0016, 0022–0030 to 0017–0025, 0032–0078 to
  0026–0072, 0082–0096 to 0073–0087; 0088 is new.
- The device round of 2026-11-08 passed the standard checks (microphone clear, GNSS fixes, mobile data, the crypto
  node `disabled`), with one finding: a suspend started with the lid open ended after 2 s, woken by the interrupt
  a lid opening reports (`/sys/power/pm_wakeup_irq`); with the lid closed the suspend held. Revision 2 below.

### 7.3.3 revision 2: GPIO wake interrupts off the PDC

- 0089 (this repository): reapplies upstream's `602cb14e310a` ("pinctrl: qcom: x1e80100: Bypass PDC wakeup parent
  for now"), which 7.3 reverted (`77fbc756d9cb`) together with its PDC rework (pass-through or secondary mode,
  chosen by an SCM write the firmware may refuse). With the lid's GPIO 2 (a `gpio-keys` wakeup source,
  `wakeup-event-action = EV_ACT_DEASSERTED`) routed through the PDC (port 70), a suspend with the lid open woke at
  once; 7.2 kept the GPIO wake interrupts on the TLMM's summary interrupt, where the lid woke the system only
  when opened. `nwakeirq_map` is 0 again.
- Passed its device round on 2026-11-09: the suspend with the cover open held 68 s, the night drew 0.25 W with the
  memory asleep 27112 of 28883 s (`docs/verified.md`); opening the cover no longer wakes the system
  (`docs/sleep.md`). Pushed the same day as `sp11/7.3.3` (head `476df635`, tree `9eb147a1`, the tree the kernel
  was built from), signed in place in the submodule without a clone of the fork.

### 7.3.3 revision 3: HDR on DisplayPort and eDP

- 0090–0111: 22 commits by Xilin Wu, carried from the mailing list and not merged upstream: the series
  "drm/msm/dp: Add static HDR support for DP and eDP" in its second version of 2026-10-09 (0092–0111,
  `20261009-msm-dp-hdr10-v2-0-1835d4966da3@radxa.com`) and two fixes of its first version that the second
  builds on (0090, in msm-next as `62c6146e5fde`, and 0091). Each commit's `[sp11: ...]` note names its posting.
- What they add: the connector properties `max bpc`, `Colorspace` and `HDR_OUTPUT_METADATA` on DP and eDP, the
  BT.2020 VSC packet and the HDR static metadata packet, 10 bits per colour as the condition for HDR, HDR
  streams kept out of PSR. On the way they rework the stream enable, the PHY's power bookkeeping and the read of
  an eDP panel's capabilities; outside the msm driver, 0092–0094 let the bridge connector attach `max bpc` to a
  non-HDMI chain.
- Adapted where they meet SP11 patches: 0099 and 0100 keep 0033's delayed clock defaults between the PHY's
  power-on and the link clocks, and a failure there powers the PHY off; 0102 keeps 0036's link-rate quirk ahead
  of the capability read; 0107 lets 0026 choose the direct SDP flush only while PSR is enabled, so a stream
  outside PSR keeps the peripheral flush that latches its packets.
- Upstream on 2026-11-12: under review, with changes asked for on the `max bpc` handling in the bridge chain and
  on the video test and VSC flush patches. The next rebase takes upstream's current version.
- No configuration change: the built configuration is revision 2's, and the four module packages hold the same
  modules.
- Passed its device round on 2026-11-12: the standard checks, nine switches between SDR and HDR, seven suspends
  with HDR on, 8 hours asleep at 0.31 W with the memory asleep 27167 of 28951 s (`docs/verified.md`,
  `docs/display.md`). Pushed the same day: `sp11/7.3.3` moved forward by the 22 commits (head `fe43e1a3`, tree
  `5aa74d68`, the tree the kernel was built from), signed in place in the submodule.

### 7.3.3 revision 4: no mode set for a gamma table

- 0112 and 0113: two commits by Dmitry Baryshkov, carried from the mailing list and not merged upstream: patches
  7 and 9 of the series "drm/msm: fix SMMU fault dumps" in its fifth version of 2026-10-24
  (`20261024-fd-kms-fix-smmu-v5-0-a5b0b284aead@oss.qualcomm.com`). 0112 clears a mixer's DSPP pointer when a
  mode set leaves the mixer without one. 0113 asks for a mode set only for a CRTC that has a CTM or a gamma LUT
  and lacks a DSPP, in `dpu_crtc_check_mode_changed()`, and drops the loop of `msm_atomic_check()` that forced
  one whenever either came or went and allowed it in userspace's place.
- 0113 is adapted: its `dpu_crtc_atomic_check()` hunk is left out, 0018 had made that change, and the loop it
  drops also held 0017's gamma lines. Of 0017 nothing is left in the tree.
- 0114 (this repository): `_dpu_rm_reserve_lms()` looks for mixers with a free DSPP first, whatever the topology
  asks for, and reserves the DSPPs with the mixers; when none are left, a CRTC that asks for no DSPP gets mixers
  without one, as before. A CRTC so has its DSPPs from its first mode set, and a CTM or gamma LUT set later is an
  ordinary commit.
- Why: a CRTC got its DSPPs only in a mode set that already carried a CTM or a gamma LUT, and 0017 forced a
  full mode set whenever one came or went. At the login screen's start that happened twice, each powering the
  panel off and on: mutter's first commit drops the table Plymouth set, and its own follows in a commit that
  allows no mode set (`docs/display.md`). With 0113 and without 0114 a first table on a CRTC without DSPPs
  fails instead (`-EINVAL` from `drm_atomic_check_only()`).
- The cost: a CRTC holds DSPPs it may never use. X1E80100 has a DSPP on four of its six mixers; the panel takes
  two mixers, a second display the other two with a DSPP, a third gets none and neither CTM nor gamma LUT.
- Upstream on 2026-11-12: the series is under review. Open on patch 9: it forces a mode set on a disabled CRTC
  that carries a CTM or gamma LUT, and whether dropping one should release the DSPPs. The next rebase takes
  upstream's current version and checks 0114 against it.
- No configuration change: the built configuration is revision 3's but for the build salt, and the four module
  packages hold the same modules.
- Passed its device round on 2026-11-13: three recorded boots (revision 3 with two mode sets before the login
  screen settles, revision 4 with none, and with one at a login into HDR), Night Light, an HDR switch, three
  suspends and the standard checks (`docs/verified.md`, `docs/display.md`). Pushed the same day: `sp11/7.3.3`
  moved forward by the three commits (head `216231c9`, tree `ac3d82da`, the tree the kernel was built from),
  signed in place in the submodule.

## Contents

The patches by number, with their origin and what each is needed for.

| Patches | What | Origin | Needed for |
|---|---|---|---|
| 0001 | EFI stub: signal the before-ExitBootServices event group | Johan Hovold (T14s workaround, applies to every arm64 machine) | boot (kept until a boot without it is tested) |
| 0002, 0003 | UCSI connector worker and pmic_glink altmode worker on freezable workqueues | Abel Vesa | USB-C across suspend |
| 0004–0006 | rpmsg announce order, an rpmsg helper to open an endpoint during probe (needed by 0006), QRTR SMD open/close races | Stephan Gerhold | ADSP services (audio, battery, sensors). 0006's probe holds its send lock from the endpoint registration through a failed channel open into the unregistration; a QRTR broadcast in that window deadlocks with it (the CDSP's IPCRTR open times out after 5 s in the initramfs): three boots of 2026-11-05/06 waited 212 s in dracut-initqueue, udevd unkillable, and ran without battery, Wi-Fi and sensors, every QRTR user blocked, until a long power press; fixed by 0087 |
| 0007 | x1e80100 machine driver match data (Dell XPS 13 channel map) | Abel Vesa | prerequisite of 0054 |
| 0008 | qcom_battmgr request input checks | Jens Glathe | battery |
| 0009 | WCN7850 Bluetooth: drop the unused baud-rate event | Cheng Jiang | Bluetooth |
| 0010, 0011 | QMP combo PHY: initial mode for static bridges | Jens Glathe | USB-C, DisplayPort alt mode |
| 0012, 0017–0020, 0026–0031 | msm display and GPU: X1E catalog, clock factor, gamma, resume clock, PSR SDP flush, standalone GPU/GMU device model | William Larson, Jens Glathe, Stephan Gerhold, Xilin Wu, Lars Karlslund, Akhil P Oommen | display, GPU acceleration, backlight, suspend |
| 0013 | Denali firmware paths in the OLED device tree | Jens Glathe | ADSP, CDSP, GPU firmware |
| 0014, 0015 | ath12k `disable-rfkill` device-tree property, set on the Denali Wi-Fi node | Dale Whinham | Wi-Fi (hard-blocked otherwise) |
| 0016 | Surface Aggregator: the DT default no longer assumes the EC closes its serial handle in D3 (SP11 suspend fix) | Dale Whinham | keyboard, touchpad, tablet switch after resume |
| 0021–0025 | PS8830 retimer: USB4 off, DP alt-mode states, config delay | Jens Glathe | USB-C, DisplayPort alt mode |
| 0032–0035 | apply clock defaults only once the PHY is powered (driver core, DP, eUSB2, dwc3-qcom) | Stephan Gerhold, Jens Glathe | USB, DisplayPort |
| 0036 | OLED panel: maximum link rate from ACPI when the DPCD reports 0 | Jérôme de Bretagne | display on the non-5G SKUs (the DMI match excludes the 5G SKU) |
| 0037, 0038 | dwc3 `snps,reinit-phy-on-resume` | Oliver White | USB after resume |
| 0039–0041 | Surface platform profile and fan without ACPI | Leon Silcott (ooaklee) | power profiles, fan readout |
| 0042, 0043 | GPI DMA and GENI SPI in QSPI mode | x1e-nixos, ooaklee | touchscreen, pen |
| 0044 | MSHW0485 touchscreen driver with the iptsd HIDRAW bridge | ooaklee, Leon Silcott, Justin White | touchscreen, multi-touch, pen |
| 0045–0048 | SoundWire feedback ports, AudioReach speaker protection graph, WSA8845 and LPASS macros, x1e80100 VI/CPS backends | geocausa (SP11X1e-audio), ported by Leon Silcott | speakers, microphone (the LPASS macros on upstream's PM-clock drivers since 7.3.3 revision 1) |
| 0049 | surface_battery: no second battery on the SP11 | Justin White | battery |
| 0050 | Denali device tree: touch controller, audio feedback links, volume keys, USB PHY re-init, no cluster idle states | x1e-nixos, ooaklee, Leon Silcott | touch, audio, volume keys, suspend |
| 0051 | POS tablet-mode switch for the Surface Pro 11 | this repository | tablet mode, auto-rotation |
| 0052 | SoundWire: accept the controller's highest master port again (7.2.6's port check refuses it) | this repository | speakers (the CPS feedback of the speaker protection) |
| 0053–0055 | CAMSS binding resources, OV13858 and VD55G0 bindings, the X1E80100 camera nodes (camera clock controller, CAMSS, CCI) | turbineBMW | cameras |
| 0056 | camera sensors: IMX681 driver, OV13858 device-tree support and Surface Pro 11 mode, VD55G0 (STMicroelectronics' GPL driver) | turbineBMW | cameras |
| 0057, 0058, 0061 | CAMSS: unwind failed stream starts, X1E80100 C-PHY links, the Denali C-PHY sequence observed on the device | turbineBMW | front camera |
| 0059, 0062 | Denali device tree: camera rails, clocks, CCI buses and CAMSS endpoints of the three cameras; the IR illuminator on the PM8550 flash controller | turbineBMW | cameras |
| 0060 | provenance record of the camera sources | turbineBMW | — |
| 0063 | OV13858: retry the first register write after power-up | turbineBMW | rear camera |
| 0064 | IMX681: exposure through the 24-bit coarse integration register | Leon Silcott (ooaklee) | front camera exposure |
| 0065 | Denali device tree: the front camera's privacy LED on GPIO 225 | this repository | the light next to the front camera while it streams |
| 0066 | IMX681: the frame length at `0x033d`, the sensor's line time, an exposure margin of 8 lines | this repository | a third more exposure at 30 fps; the vertical blanking sets the frame rate |
| 0067 | OV13858: the lowest pixel rate from the lowest link frequency | this repository | the rear camera's line and exposure times in libcamera |
| 0068 | IMX681: the controls applied at stream start under the control handler's lock | this repository | no race with control changes at stream start |
| 0069 | qcom_battmgr: the `capacity` property on X1E80100, lost when the variant got its own property table | Liviu Nicoara | the battery percentage from the kernel |
| 0070 | qcom_battmgr: `Full` instead of `Not charging` for a full battery on external power | Bjorn Andersson | the battery state on the charger |
| 0071 | qcom_battmgr: a change notice from the AC, USB and wireless supplies when the charging source changes | Brandon Williams (turbineBMW) | UPower's on-battery state after the charger is plugged in or out |
| 0072 | Device tree of the 5G SKU: the OLED tree plus the Snapdragon X65 modem on PCIe 5 (supply switch on TLMM 221, reset 149, CLKREQ# 150), as on the CRD | this repository | the 5G modem and its GNSS receiver (`docs/modem.md`) |
| 0073 | MHI PCI: power a busy modem down for system suspend instead of aborting it | this repository | deep sleep shortly after a wake (no `s2idle` fallback) |
| 0074 | Type-C mux: initialize the orientation switch array | Haobo Cheng (posted 2026-08-04) | the orientation switch chain (not the reversed plug) |
| 0075–0079 | Adreno GMU shutdown idle check, boot-up bandwidth vote, devfreq idle time, scheduler priority, preemption records across suspend | Jie Zhang, Akhil P Oommen (posted 2026-10-24) | GPU stability around its idle power-downs, a little power while awake |
| 0080 | Denali device tree: the video codec with the Surface's firmware | this repository | hardware video decoding and encoding |
| 0081 | MHI PCI: the Surface Pro 11 5G modem's data channels for the MBIM driver | this repository | mobile data (`docs/modem.md`) |
| 0082 | 5G device tree: the modem's supply stays on through a system sleep | this repository | mobile data back within seconds of a wake (`docs/modem.md`, Across a sleep) |
| 0083 | ath12k: a known country kept when the 11d scan reports none, restored when a radio starts | this repository | the first Wi-Fi scan after a wake with the country known (`docs/hardware.md`, Wi-Fi) |
| 0084 | MSHW0485 touch: no power-on in the resume callback; the recovery work powers the controller, once | this repository | 0.8 s less in a wake's resume phase (`docs/sleep.md`, Wake) |
| 0085 | PCIe (qcom): the controllers suspend and resume asynchronously | this repository | the three links resumed side by side, about 0.65 s less in a wake |
| 0086 | PS8830 retimer: the connection announced 30 ms before its mode | this repository | USB 3 with the plug reversed (`docs/hardware.md`, USB-C data) |
| 0087 | QRTR SMD: the probe's send lock released before a failed open's unregistration | this repository | boots that sat 212 s in dracut-initqueue and ran without battery, Wi-Fi and sensors (0006's deadlock) |
| 0088 | Denali device tree: the crypto engine's node disabled | this repository | no user of the interconnect without a driver, since 7.3 marks the engine's driver `BROKEN` (`docs/kernel.md`, Sync state and the CDSP) |
| 0089 | X1E80100 pin controller: GPIO wake interrupts stay on the TLMM summary interrupt, not the PDC (7.2's state) | this repository | a suspend with the lid open that holds; 7.3's PDC wake path woke it at once (`docs/sleep.md`) |
| 0090, 0091 | DP: hot-plug state updates serialized, the debugfs connector pointer initialized | Xilin Wu (posted 2026-09-30; 0090 in msm-next) | prerequisites of 0092–0111 |
| 0092–0094 | DRM core: `max bpc` attached before a connector has a state, and by the bridge connector for non-HDMI chains | Xilin Wu (posted 2026-10-09) | 10 bits per colour on DP and eDP |
| 0095–0111 | DP and eDP: the output bit depth, the BT.2020 VSC packet, the HDR static metadata packet, `Colorspace` and `HDR_OUTPUT_METADATA`; stream enable, PHY power and the eDP capability read reworked | Xilin Wu (posted 2026-10-09) | HDR (`docs/display.md`) |
| 0112, 0113 | DPU: a mixer's DSPP pointer cleared when a mode set leaves it without one; a mode set asked for only by a CRTC that has a CTM or gamma LUT and no DSPP (in place of 0017's forced mode set) | Dmitry Baryshkov (posted 2026-10-24) | no mode set when a gamma table or CTM comes or goes |
| 0114 | DPU: the mixers' DSPPs reserved with every mode set while mixers with a free one are left | this repository | a compositor's first gamma table without a mode set and the panel's power cycle (`docs/display.md`) |

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
- v23.2's camera stack (far too dark): revision 6 carries turbineBMW's instead (0053–0064 in the current
  numbering), revision 7 the privacy LED (0065).
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
