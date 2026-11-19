# 5G modem
The 5G SKU's Snapdragon X65 modem: its wiring, the device tree that brings it up, its PCIe link at boot, what
Linux makes of it, the QMI port that blocked suspend, mobile data, and the modem across a sleep. Its GNSS receiver
and the GeoClue feed: `docs/gnss.md`. Established on the tested unit from 2026-10-23 on, without a SIM (the eSIM
holds no profile); mobile data on 2026-10-29 with a nano-SIM.

## Hardware

- The modem: PCI `17cb:0308`, subsystem `17cb:0308`, on PCIe 5 (segment 5), an MHI device. It boots from its own
  flash: Windows' modem packages carry no firmware for it, and Linux loads none.
- Windows' GNSS driver ("Qualcomm(R) Location", `qcgnss.dll`) is a client of the modem (`PCI5 > RP1 > MHI1 > QMUX >
  GNSS`); the sensor DSP has no location service.
- Windows' DSDT names the board `PSUB = "CRD08380"`, Qualcomm's reference design, and the wiring is the CRD's
  (`x1-crd.dtsi`): the WWAN power-down device (`QCOM0CDA`) holds a PMIC pin, the modem's supply switch on TLMM 221,
  and TLMM 140 and 142 (by their names `WDPM` and `GDPM` probably W_DISABLE1# and W_DISABLE2#; not confirmed); the
  PCIe power extension (`QPPX`) lists the PCIe resets 143, 146, 149, 152, 155 (149: PCIe 5). The root port's wake
  interrupt is a virtual pin (0x280) that names no TLMM line (the CRD's wake is TLMM 151).
- Its two power-off methods, called by Windows' driver (`_MFF`, and `_MNF` "with 3000 ms delay"): wait 400 ms, the
  PMIC pin low (pin 0x104 of `PM01`, "GPIO 4C" in the debug string), 255 ms, TLMM 221 low, 1 ms (`_MNF`: 3000 ms),
  TLMM 140 low, 1 ms, TLMM 142 low. Powering on is the firmware's and not in the DSDT. Linux runs no such
  sequence at shutdown or reboot, and the PMIC pin is in no device tree: by Qualcomm's lettering it is
  `pm8550ve_2` GPIO 4, an output that reads high in a boot with the modem and in one without (2026-11-14).
- The platform extension's resources for PCIe 5 in D0 are PCIe 4's (Wi-Fi) with the other instance: `LDO3_E`,
  `LDO3_I`, `LDO3_J`, the PMIC clock `CLK7_A`, both power domains, the clocks with `tcsr_pcie_2l_5_clkref_en`, and
  TLMM 150 as CLKREQ# with a pull-up. The 5G tree gives the PHY `LDO3_E` and `LDO3_I`; `LDO3_J` and `CLK7_A` have
  no consumer in it.
- The firmware hands over TLMM 140, 142, 149 and 221 as outputs, high: the modem is powered and out of reset before
  Linux starts.

## Device tree

- `x1e80100-microsoft-denali-oled-5g.dts` (patch 0070, 7.2.11 revision 3): the OLED tree plus the CRD's PCIe 5
  block: `vreg_wwan` on TLMM 221 (on at boot), `pcie5` and `pcie5_phy` with `vreg_l3i_0p8` and `vreg_l3e_1p2`,
  reset on TLMM 149, CLKREQ# on 150; no wake pin up to 7.3.3 revision 4 (The link at boot); the OLED tree's
  compatibles, model "(OLED, 5G)".
- Up to revision 8 `vreg_wwan` (`SDX_VPH_PWR`) is also PCIe 5's `vddpe-3v3` supply, and the qcom driver switches
  its supplies off when a sleep takes the link down (host deinit): from 7.2.11 revision 4 to 8 the modem is off in
  a deep sleep. From revision 9 (patch 0080) the supply is `regulator-always-on` and no longer PCIe 5's, so the
  modem keeps its power through the sleep (Across a sleep).
- The build gives the tree to the 5G SKU only (`docs/hardware.md`): `SP11_DTB` follows the SKU in `load_hardware`,
  and step 20 checks that PCIe 5 is enabled in the 5G tree and disabled in the OLED tree. A `build/hardware.env`
  from before revision 3 records the OLED tree; `load_hardware` replaces it and says so.
- With the modem up, no RPMh power-domain or interconnect provider waits for `sync_state`.

## The link at boot

- The controller's probe (`pcie-qcom.c`, `pcie-designware-host.c`, the same in 7.2.15 and 7.3.3) asserts the
  modem's reset (TLMM 149), powers the controller and its PHY, releases the reset after 100 ms, starts link
  training and looks for the link ten times, 90 ms apart. With the link up it waits 100 ms more and scans the bus.
- Without the link after 0.9 s the controller's link state decides (`dw_pcie_wait_for_link()`): in Detect.Quiet
  or Detect.Active the probe goes on (`Device not found`), in Poll.Active or Poll.Compliance too (`Device found,
  but not active`), in any other state it fails with -110 (`Link failed to come up`). PRE_DETECT_QUIET is such
  a state there, while `dw_pcie_suspend_noirq()` and the Tegra driver, on the same controller core, count it
  among the Detect states.
- A failed probe asserts the reset again and switches the PHY and the clocks off, and nothing probes the
  controller again in that boot: the driver is built in and has no bind attribute. The platform bus's
  `/sys/bus/platform/drivers_probe` takes the controller's name and probes it once more; the write returns when
  that probe is done.
- Linux never resets or power-cycles the modem beyond those 100 ms: the firmware hands it over powered and out of
  reset, and from revision 9 on its supply belongs to no driver (Device tree). The Wi-Fi chip was in that position
  up to 7.2.12, when one boot in twelve came up without Wi-Fi; from 7.2.13 on its power sequencer resets it
  before the link trains (`docs/hardware.md`, Wi-Fi).
- In a boot with the modem the link is up 0.19 to 0.21 s after the reset's release, at the first 90 ms step: six
  boots of 7.2.15 on 2026-11-06, the 26 boots of 7.3.3 revisions 1 to 3 in the journal from 2026-11-08, 50 of
  revision 4's 58 up to 11-16, 23 of revision 5's 24 to 11-19 and the first two of 7.3.5 revision 1.
- In the other eight boots of revision 4 (2026-11-13 to 11-16; five after a reboot, three after a power-off of
  1.8 to 5.7 hours) the probe ended `Link failed to come up. LTSSM: PRE_DETECT_QUIET` and failed with -110.
  Revision 4 adds three patches of the display driver; the split against the earlier revisions is not explained.
- The PHY's driver differs between the series (`phy-qcom-qmp-pcie.c`): 7.2 resets a PCIe PHY at every start,
  7.3 leaves out the reset at the first probe when the firmware left the PHY started and ready
  (`910b828b22b7`). The controller's probe still resets the controller and the endpoint, so the link is down
  while the PHY keeps the firmware's state; on a Dell XPS 13 9345 (X1E80100) the NVMe link then never trained
  (`Device found, but not active`). Upstream's revert (`9a07dfa7f6fe`) is queued and in Fedora's patch from
  7.3.5, so 7.3.5 revision 1 resets the PHY as 7.2 did. Whether this unit's failed probes come from the left-out
  reset is not shown: the six recorded boots of 7.2.15 had the link, and the boots of 7.3.5 will tell.
- Such a boot has no WWAN port, and the clock controller and four interconnect providers keep waiting for
  `sync_state`, so their boot votes stay. PCIe 4's link came up in the boot of 2026-11-13 08:15.
- The pins, from debugfs: with the modem up the reset (TLMM 149) is high, CLKREQ# (150) high and TLMM 151, the
  CRD's wake pin, high. After a failed probe the reset is low and CLKREQ# low, and TLMM 151, an input with a
  pull-up as the firmware leaves it, goes low some seconds later: on 2026-11-16 it read low 10 s after the
  kernel's start in one boot, and high at 6 s and low at 7.6 s in another.
- A second probe with TLMM 151 low found the link at its first check, 0.2 s after the controller's `iATU` line, in
  the three boots it was tried in (2026-11-14 08:11, 11-16 15:24 and 19:35): the modem on the bus 8.0 to 10.2 s
  after the kernel's start, ModemManager's modem at 31.5 to 33.7 s against about 15 s in a boot with the link at
  the first probe. With the modem's driver started CLKREQ# and TLMM 151 read high again.
- A second probe with TLMM 151 high, 6.3 s after the kernel's start (2026-11-14 23:16 and 23:22), ended `Device
  found, but not active` and bound the controller without the modem. The root port's hot-plug driver (pciehp) was
  there for a link coming up later; no hot-plug message followed within 229 s.
- A reboot from a boot without the modem gave another such boot twice (2026-11-13 08:15 to 08:21, 11-14 23:16 to
  23:22). A shutdown of ten seconds brought the modem back (owner, 2026-11-14), as did a Windows session and,
  once, a reboot into revision 3.
- A check kit's boot service ran that sequence from user space: it waited up to 20 s for TLMM 151 to read low,
  then wrote to `drivers_probe`. In the 25 boots after its installation (2026-11-15 to 11-16) the first probe
  failed twice, and the modem came up at the service's first probe both times (`docs/verified.md`).
- From 7.3.3 revision 5 the controller's driver does it itself (0113). When the host initialization times out
  and the controller's node names the WAKE# line, a work item waits up to 20 s for the line and has the bus
  probe the controller again, up to three times, 5 s apart. Its lines in the kernel's log: `The endpoint was
  not ready, probing again once it asserts WAKE#`, `WAKE# asserted after <n> ms`, `Probing again (1 of 3)`.
- It ran on the device on 2026-11-19, in revision 5's 24th boot (after 2.1 hours off): the first probe failed
  in `PRE_DETECT_QUIET`, the line was asserted 5.2 s into the work's wait, the second probe found the link, and
  the modem was on the bus 8.1 s after the kernel's start, ModemManager's modem at 31.8 s against about 15 s.
- The wait is not in the probe: the driver probes asynchronously, and `do_init_module()` waits for every
  asynchronous probe, so each module load of that time would wait with it.
- The 5G tree names the line in PCIe 5's controller node (0114: `wake-gpios` on TLMM 151, with its pin state)
  and not, as the CRD's, in the root port's: there the PCI core arms it as the port's wake-up interrupt
  (`pci_configure_of_wake_gpio()`), and whether the modem should wake the tablet is open.
- In `/sys/kernel/debug/gpio` nine PMIC chips come before the pin controller, and one read returns only the
  chips that fit its buffer: a tool reads on up to the end of the pin controller's section.
- A resume runs the same wait (`dw_pcie_resume_noirq()`): 61 sleeps in the journal of 2026-11-08 to 11-17, none
  with a link failure.

## Linux

- `mhi-pci-generic` binds the modem (`qcom-sdx65m`): the ports `wwan0mbim0`, `wwan0qcdm0` and `wwan0qmi0`, the
  data channels (Mobile data), and QRTR over the `IPCR` channel: node 2 (IPA control, TFTP, DIAG) and node 3, the
  modem's QMI services (DMS, NAS, WDS, WDA, UIM, the location service 16 and more).
- The QMI port never answers (`qmicli -d /dev/wwan0qmi0`: `Transaction timed out`). The same services answer over
  QRTR (`qmicli -d qrtr://3`) and as QMI over MBIM (`qmicli -p -d /dev/wwan0mbim0 --device-open-mbim`).
- ModemManager 1.24.2 makes a modem of it with the `generic` plugin and the MBIM port; without a SIM it stays
  `failed` (`esim-without-profiles`), power state low. Its `qcom-soc` plugin probes `qrtr3` and gives up (no QMI
  network port).
- The radio may go online (`--dms-set-operating-mode=online` accepted, `HW restricted: 'no'`): no FCC lock. In
  the normal boot the operating mode reads `shutting-down` (`qmicli -d qrtr://3 --dms-get-operating-mode`);
  `low-power`, set the same way, held through a night.

### The QMI port: ModemManager and suspend

- ModemManager's QMI probe of `wwan0qmi0` takes 45 s (the modem appears 53 s after boot), and the `qmi-proxy` it
  starts ignores SIGTERM, so systemd waits 45 s at shutdown (`State 'final-sigterm' timed out`) and kills it.
- A request queued on the port keeps the MHI controller's `pending_pkts` above zero; `mhi_pm_suspend()` then
  returns `-EBUSY` (`failed to suspend device: -16`), every suspend fails, deep and the s2idle fallback, and the
  tablet is back within seconds. Shown on purpose: one request held on the port made sleep fail, the same boot
  slept with the port idle or closed.
- `77-sp11-modem.rules` (support RPM, 5G builds) sets `ID_MM_PORT_IGNORE` on the port: ModemManager makes the modem
  at 30.8 s, stops in 19 ms, and the tablet sleeps with the modem powered. Anything else that writes to the port
  still blocks sleep until it closes it.

## Mobile data

- Two SIM slots: ModemManager's slot 1 is the nano-SIM behind the SSD door (Windows' slot index 0), slot 2 the
  eSIM. ModemManager 1.24.2 switches them over MBIM (`--set-primary-sim-slot`); with a SIM in, the modem took slot
  1 after Windows had mapped it. A SIM with a PIN is locked again whenever the modem restarts (`unknown -> locked`).
- The modem frames its data as MBIM: the WDA data format of its PCIe endpoint (`qmicli -d qrtr://3
  --wda-get-data-format="ep-type=pcie,ep-iface-number=4"`; without the endpoint `InvalidArgument`) reads link
  layer `raw-ip`, uplink and downlink aggregation `mbim`, NDP signature 5460041 (`IPS` and 0, MBIM's NDP16 for IP
  session 0), at most 32 datagrams and 32768 bytes per downlink transfer. Asked for raw IP without aggregation, it
  answers `Successfully set data format` with `mbim` again.
- Up to revision 7 the bare `17cb:0308` entry named the data channels `IP_HW0` for `mhi_net` (`mhi_hwip0`, plain IP;
  `mhi_swip0` on `IP_SW0`): the connection came up with the carrier's addresses but carried nothing. The modem
  forwarded none of the packets it took (ModemManager's counters: 48 bytes per connection), and the NTBs it sent
  ended as IPv4 header errors (`IpInHdrErrors`; an NTB starts with `NCMH`).
- From revision 8 (patch 0079) the modem's IDs get the generic channel set with the data channels named
  `IP_HW0_MBIM`, for `mhi_wwan_mbim`, without `IP_SW0`: one network device, `wwan0`. ModemManager 1.24.2 lists
  `wwan0 (net), wwan0mbim0 (mbim)` and connects session 0 on `wwan0`. Its driver check for MBIM data ports knows
  only `cdc_mbim` and `mhi_net`, but no connect path calls it; upstream (c3ef78cc, 1.25.95-dev) accepts
  `mhi-pci-generic` there and no longer `mhi_net`.
- On the device (2026-10-29, o2 Germany): IPv4 and IPv6, 5 MB in 0.38 s, pages in Firefox with Wi-Fi off, name
  lookups over `wwan0`, GPS's QRTR path unchanged, a deep sleep and then the connection again
  (`docs/verified.md`).
- The APN: Fedora's mobile-broadband-provider-info (20240407) knows 262/03 only through E-Plus-era entries
  (AldiTalk, blau.de, E-Plus, simyo, all `internet.eplus.de`), so GNOME offers no o2 entry; `internet` (Windows')
  and `internet.eplus.de` both work.

## Across a sleep

- From 7.2.11 revision 4 on the modem loses its power with its PCIe link in a deep sleep (`docs/sleep.md`). On
  resume `mhi-pci-generic` logs `Resuming from non M3 state (RESET)` and `failed to resume device: -22`, then
  recovers it: its WWAN ports return about 1.5 s later, its main processor appears on QRTR 13 s after the wake,
  and it answers ModemManager's MBIM open 33 to 36 s after the wake (0.5 s after a driver reload without a power
  cycle).
- ModemManager drops the modem at every suspend and probes it again on resume; it then waits 10 s, at every start
  of the modem, for a location indication this modem never sends (`couldn't load supported assistance data
  types`; `docs/gnss.md`), registers after 47 to 51 s, and NetworkManager reconnects a profile with
  `connection.autoconnect yes` about 2 s later; without it the profile stays down until it is activated by hand
  (2026-11-02, with the modem registered 0.1 s after the wake). GNOME's Mobile Data switch is that setting: the
  panel reads the switch from the default APN profile's `autoconnect` and writes it back on every change
  (gnome-control-center, `panels/wwan/cc-wwan-data.c`). A SIM with a PIN asks for it again.
- Revision 5 powers a busy modem down for a suspend started within 15 s of a wake instead of aborting the suspend
  (patch 0071, `docs/sleep.md`).
- Kept powered through the sleep (a test tree, 2026-10-29: `vreg_wwan` with `regulator-always-on` and no longer
  PCIe 5's `vddpe-3v3-supply`; the link still goes down) the modem resumed without a reset or new ports:
  ModemManager's probe answered after 3.4 s, registration after 15.7 s (the 10 s wait included), mobile data
  after 16.7 s. In a 10-minute sleep `ddr` counted 569 of 608 s (579 of 619 s with the modem off), `cxsd` 0 in
  both; the battery's reading moved by the same 0.511 Wh in both runs, too coarse for the modem's own draw.
  7.2.11 revision 9 (patch 0080) makes this the 5G tree's wiring.
- ModemManager's quick suspend/resume (`--test-quick-suspend-resume`, a systemd drop-in on its unit) keeps the
  modem object across a sleep: terse mode at the suspend, a state sync at the resume instead of the re-probe and
  its 10 s wait. With revision 9 (2026-10-31): the sync done 1.4 s after the wake, NetworkManager's profile
  connected 2.0 s after it, after a 10-minute sleep and after an 8-hour night alike; no modem restart. Only for a
  modem that stays powered (revision 9 on); in the support RPM from 3.9 (5G builds:
  `/usr/lib/systemd/system/ModemManager.service.d/sp11-quick-suspend-resume.conf`).
- The powered modem costs nothing the battery resolves: revision 9's night drew 0.32 W over 8 hours (`ddr` 94 %
  of the time), revision 5's with the modem off 0.33 W (`docs/sleep.md`).
- Before revision 4 (the link up through the sleep) a night drew the same with the link, without it (the OLED
  tree) and with the radio in `low-power`, within the battery's resolution of about 0.06 W.

## Open

- The wake pin; whether the modem needs to wake the tablet at all.
- ModemManager's 10 s wait for the location indication at every start of the modem (a boot; a rebuilt
  ModemManager would be needed).
- eSIM profiles from Linux (lpac, not packaged in Fedora).
- The link at boot: why the modem is not ready at the first probe in some boots, none of them before
  revision 4; the PHY reset that 7.3 left out and Fedora's 7.3.5 restores is the one difference from 7.2 found
  so far (The link at boot). A boot with the controller bound and no modem has not occurred since the second
  probe waits for TLMM 151; a power cycle of the modem's supply has not been tried for one.

## History

- 2026-10-23: the modem found on PCIe 5 and brought up with a test device tree; its services reached over QRTR,
  the radio may go online; the 45 s shutdown traced to ModemManager's `qmi-proxy` and the failed suspends to the
  QMI port; 7.2.11 revision 3 and support 3.5 built, the 5G device tree chosen by SKU.
- 2026-10-27: the drain through a night measured with and without the PCIe link and with the radio in `low-power`:
  no difference within the battery's resolution.
- 2026-10-29: mobile data with a nano-SIM: nothing carried over `mhi_net`, the modem's MBIM framing found and
  refusing raw IP; a module build with the data channels for `mhi_wwan_mbim` passed, 7.2.11 revision 8 built with
  it and confirmed. The return after a wake timed; a test tree keeping the modem powered through deep sleep
  brought mobile data back after 17 s instead of 52 s.
- 2026-10-31: 7.2.11 revision 9 with the test tree's change (0091) and ModemManager's quick suspend/resume on the
  device: mobile data back 2.0 s after a wake, the night at 0.32 W.
- 2026-11-13: one boot on 7.3.3 revision 4 without the modem, its PCIe link not coming up at the probe; the
  boots before and after it had the modem.
- 2026-11-14: that boot read against the sources: the probe's single wait of 0.9 s and its link-state rule;
  Windows' power-off sequence for the modem and PCIe 5's resources read from the DSDT. The journal's boots
  counted and a second probe tried on the device: six of revision 4's 30 boots without the modem, one of them
  brought back by the second probe.
- 2026-11-16: the check kit's service, waiting for TLMM 151 before its probe, in 25 boots: the first probe
  failed in two and the modem came up in both. 7.3.3 revision 5 built: the controller's driver probes again
  itself once the modem asserts the line.
- 2026-11-19: revision 5's second probe ran for the first time, in a boot whose first probe had failed, and
  brought the modem up 8.1 s after the kernel's start. 7.3.5 revision 1 installed, on Fedora's 7.3.5, whose patch
  restores the PCIe PHY's reset at the first probe that 7.3 had left out; its first two boots had the link at
  the first probe.
