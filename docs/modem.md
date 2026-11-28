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

- `x1e80100-microsoft-denali-oled-5g.dts` (patch 0070): the OLED tree plus the CRD's PCIe 5 block: `vreg_wwan` on
  TLMM 221 (on at boot), `pcie5` and `pcie5_phy` with `vreg_l3i_0p8` and `vreg_l3e_1p2`, reset on TLMM 149, CLKREQ#
  on 150, WAKE# on 151 (patch 0114, The link at boot); the OLED tree's compatibles, model "(OLED, 5G)".
- `vreg_wwan` (`SDX_VPH_PWR`) is `regulator-always-on` and not PCIe 5's `vddpe-3v3` supply (patch 0080): the qcom
  driver switches a controller's supplies off when a sleep takes the link down (host deinit), so as the slot supply
  it took the modem's power in every deep sleep (7.2.11 revisions 4 to 8). Now the modem keeps its power through a
  sleep (Across a sleep).
- The build gives the tree to the 5G SKU only (`docs/hardware.md`): `SP11_DTB` follows the SKU in `load_hardware`,
  and step 20 checks that PCIe 5 is enabled in the 5G tree and disabled in the OLED tree. `load_hardware` takes the
  SKU's tree over another one recorded in `build/hardware.env` (one written before this choice records the OLED
  tree) and says so.
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
  reset, and its supply belongs to no driver (Device tree). The Wi-Fi chip was in that position up to 7.2.12, when
  one boot in twelve came up without Wi-Fi; from 7.2.13 on its power sequencer resets it before the link trains
  (`docs/hardware.md`, Wi-Fi).
- In a boot with the modem the link is up 0.19 to 0.21 s after the reset's release, at the first 90 ms step: every
  boot of 7.2.15 and of 7.3.3 revisions 1 to 3 in the journal, 50 of revision 4's 58 boots, 23 of revision 5's 24.
- In the other eight boots of revision 4 (2026-11-13 to 16; five after a reboot, three after a power-off of 1.8 to
  5.7 hours) the probe ended `Link failed to come up. LTSSM: PRE_DETECT_QUIET` and failed with -110. Revision 4 adds
  three patches of the display driver; the split against the earlier revisions is not explained.
- The PHY's driver differs between the series (`phy-qcom-qmp-pcie.c`): 7.2 resets a PCIe PHY at every start, 7.3
  leaves out the reset at the first probe when the firmware left the PHY started and ready (`910b828b22b7`), while
  the controller's probe still resets the controller and the endpoint; on a Dell XPS 13 9345 (X1E80100) the NVMe
  link then never trained (`Device found, but not active`). Fedora's 7.3.5 patch carries upstream's queued revert
  (`9a07dfa7f6fe`), so 7.3.5 resets the PHY as 7.2 did. Whether this unit's failed probes came from the left-out
  reset is not shown.
- Such a boot has no WWAN port, and the clock controller and four interconnect providers keep waiting for
  `sync_state`, so their boot votes stay.
- The pins, from debugfs: with the modem up the reset (TLMM 149) is high, CLKREQ# (150) high and TLMM 151, the CRD's
  wake pin, high. After a failed probe the reset is low and CLKREQ# low, and TLMM 151, an input with a pull-up as
  the firmware leaves it, goes low some seconds later (read low at 7.6 s and at 10 s after the kernel's start in two
  boots, 2026-11-16).
- A second probe with TLMM 151 low found the link at its first check, 0.2 s after the controller's `iATU` line, in
  all three boots it was tried in (2026-11-14 and 16): the modem on the bus 8.0 to 10.2 s after the kernel's start,
  ModemManager's modem at 31.5 to 33.7 s against about 15 s in a boot with the link at the first probe. With the
  modem's driver started CLKREQ# and TLMM 151 read high again. A boot service that waited for the line and then
  wrote to `drivers_probe` brought the modem in the two of its 25 boots whose first probe failed (2026-11-15 and
  16).
- A second probe with TLMM 151 high, 6.3 s after the kernel's start (2026-11-14), ended
  `Device found, but not active` and bound the controller without the modem; the root port's hot-plug driver
  (pciehp) reported nothing within 229 s.
- A reboot from a boot without the modem gave another such boot twice. A shutdown of ten seconds brought the modem
  back (owner, 2026-11-14), as did a Windows session and, once, a reboot into revision 3.
- From 7.3.3 revision 5 the controller's driver probes again itself (0113). When the host initialization times out
  and the controller's node names the WAKE# line, a work item waits up to 20 s for the line (polled every 100 ms,
  the GPIO held only for the wait) and has the bus probe the controller again, up to three times, 5 s apart; a list
  keeps a probe that fails meanwhile from scheduling a second work item. Its lines in the kernel's log:
  `The endpoint was not ready, probing again once it asserts WAKE#`, `WAKE# asserted after <n> ms`,
  `Probing again (1 of 3)`.
- It ran on the device on 2026-11-19, in revision 5's 24th boot (after 2.1 hours off): the first probe failed in
  `PRE_DETECT_QUIET`, the line was asserted 5.2 s into the work's wait, the second probe found the link, and the
  modem was on the bus 8.1 s after the kernel's start, ModemManager's modem at 31.8 s.
- The wait is not in the probe: the driver probes asynchronously, and `do_init_module()` waits for every
  asynchronous probe, so each module load of that time would wait with it.
- The 5G tree names the line in PCIe 5's controller node (0114: `wake-gpios` on TLMM 151, with its pin state)
  and not, as the CRD's, in the root port's: there the PCI core arms it as the port's wake-up interrupt
  (`pci_configure_of_wake_gpio()`), and whether the modem should wake the tablet is open.
- In `/sys/kernel/debug/gpio` nine PMIC chips come before the pin controller, and one read returns only the
  chips that fit its buffer: a tool reads on up to the end of the pin controller's section.
- A resume runs the same wait (`dw_pcie_resume_noirq()`): 61 sleeps in the journal of 2026-11-08 to 17, none with a
  link failure.

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
- The bare `17cb:0308` entry of `mhi-pci-generic` names the data channels `IP_HW0` for `mhi_net` (plain IP), which
  cannot carry that: the connection came up with the carrier's addresses but carried nothing, the modem forwarded
  none of the packets it took (ModemManager's counters: 48 bytes per connection), and the NTBs it sent ended as IPv4
  header errors (`IpInHdrErrors`; an NTB starts with `NCMH`).
- Patch 0079 gives the modem's IDs the generic channel set with the data channels named `IP_HW0_MBIM`, for
  `mhi_wwan_mbim`, without `IP_SW0`: one network device, `wwan0`. ModemManager 1.24.2 lists
  `wwan0 (net), wwan0mbim0 (mbim)` and connects session 0 on `wwan0`. Its driver check for MBIM data ports knows
  only `cdc_mbim` and `mhi_net`, but no connect path calls it; upstream (c3ef78cc, 1.25.95-dev) accepts
  `mhi-pci-generic` there and no longer `mhi_net`.
- On the device (2026-10-29, o2 Germany): IPv4 and IPv6, 5 MB in 0.38 s, pages in Firefox with Wi-Fi off, name
  lookups over `wwan0`, GPS's QRTR path unchanged, the connection again after a deep sleep.
- The APN: Fedora's mobile-broadband-provider-info (20240407) knows 262/03 only through E-Plus-era entries
  (AldiTalk, blau.de, E-Plus, simyo, all `internet.eplus.de`), so GNOME offers no o2 entry; `internet` (Windows')
  and `internet.eplus.de` both work.

## Across a sleep

- The modem keeps its power through a deep sleep (patch 0080, from 7.2.11 revision 9); the link still goes down.
  ModemManager's quick suspend/resume (`--test-quick-suspend-resume`, from support 3.9 a drop-in on its unit in 5G
  builds: `/usr/lib/systemd/system/ModemManager.service.d/sp11-quick-suspend-resume.conf`) keeps the modem object
  across the sleep, which works only for a modem that stays powered: terse mode at the suspend, a state sync at the
  resume instead of a new probe. With revision 9 (2026-10-31): the sync done 1.4 s after the wake, NetworkManager's
  profile connected 2.0 s after it, after a 10-minute sleep and after an 8-hour night alike; no modem restart.
- The powered modem costs nothing the battery resolves: revision 9's night drew 0.32 W over 8 hours (`ddr` 94 %
  of the time), revision 5's with the modem off 0.33 W (`docs/sleep.md`).
- At every start of the modem ModemManager waits 10 s for a location indication this modem never sends
  (`couldn't load supported assistance data types`; `docs/gnss.md`); without the quick resume that start comes after
  every sleep, and mobile data then follows about 17 s after the wake.
- NetworkManager reconnects a profile with `connection.autoconnect yes` about 2 s after the modem is registered;
  without it the profile stays down until it is activated by hand (2026-11-02). GNOME's Mobile Data switch is that
  setting: the panel reads the switch from the default APN profile's `autoconnect` and writes it back on every
  change (gnome-control-center, `panels/wwan/cc-wwan-data.c`).
- A modem that lost its power in a sleep (7.2.11 revisions 4 to 8, `vreg_wwan` the slot supply) comes back through
  `mhi-pci-generic`'s recovery: `Resuming from non M3 state (RESET)` and `failed to resume device: -22`, its WWAN
  ports about 1.5 s later, its main processor on QRTR 13 s after the wake, its answer to ModemManager's MBIM open 33
  to 36 s after the wake (0.5 s after a driver reload without a power cycle). Patch 0071 restarts a modem busy at a
  suspend started within 15 s of a wake through that recovery instead of aborting the suspend (`docs/sleep.md`).

## Open

- The wake pin; whether the modem needs to wake the tablet at all.
- ModemManager's 10 s wait for the location indication at every start of the modem (a boot; a rebuilt
  ModemManager would be needed).
- eSIM profiles from Linux (lpac, not packaged in Fedora).
- The link at boot: why the modem is not ready at the first probe in some boots, none of them before 7.3.3 revision
  4; the PHY reset that 7.3 left out and Fedora's 7.3.5 restores is the one difference from 7.2 found so far. A boot
  with the controller bound and no modem has not occurred since the second probe waits for TLMM 151; a power cycle
  of the modem's supply has not been tried for one.

## History

- 2026-10-23: the modem found on PCIe 5 and brought up with a test device tree; the 45 s shutdown and the failed
  suspends traced to the QMI port; 7.2.11 revision 3 and support 3.5.
- 2026-10-27: a night's drain the same with and without the PCIe link and with the radio in `low-power`.
- 2026-10-29: mobile data with a nano-SIM: the modem's MBIM framing found, 7.2.11 revision 8 built with the data
  channels for `mhi_wwan_mbim`; a test tree kept the modem powered through a sleep.
- 2026-10-31: 7.2.11 revision 9 (the modem powered) with ModemManager's quick resume: mobile data back 2.0 s after a
  wake, the night at 0.32 W.
- 2026-11-13: a boot of 7.3.3 revision 4 without the modem, its PCIe link not up at the probe.
- 2026-11-14: the probe's link-state rule and Windows' power-off sequence read; a second probe brought the modem
  back.
- 2026-11-16: a boot service probing again once TLMM 151 reads low brought the modem in 25 boots; 7.3.3 revision 5
  built to do it in the driver.
- 2026-11-19: revision 5's second probe brought the modem up in a boot whose first probe had failed; 7.3.5 restores
  the PHY reset at the first probe.
