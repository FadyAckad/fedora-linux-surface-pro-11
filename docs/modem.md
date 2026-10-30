# 5G modem
The 5G SKU's Snapdragon X65 modem: its wiring, the device tree that brings it up, what Linux makes of it, the QMI
port that blocked suspend, mobile data, and the modem across a sleep. Its GNSS receiver and the GeoClue feed:
`docs/gnss.md`. Established on the tested unit from 2026-10-23 on, without a SIM (the eSIM holds no profile);
mobile data on 2026-10-29 with a nano-SIM.

## Hardware

- The modem: PCI `17cb:0308`, subsystem `17cb:0308`, on PCIe 5 (segment 5), an MHI device. It boots from its own
  flash: Windows' modem packages carry no firmware for it, and Linux loads none.
- Windows' GNSS driver ("Qualcomm(R) Location", `qcgnss.dll`) is a client of the modem (`PCI5 > RP1 > MHI1 > QMUX >
  GNSS`); the sensor DSP has no location service.
- Windows' DSDT names the board `PSUB = "CRD08380"`, Qualcomm's reference design, and the wiring is the CRD's
  (`x1-crd.dtsi`): the WWAN power-down device (`QCOM0CDA`) switches the modem's supply with TLMM 221, then TLMM 140
  and 142 (by their names `WDPM` and `GDPM` probably W_DISABLE1# and W_DISABLE2#; not confirmed) and a PMIC pin;
  the PCIe power extension (`QPPX`) lists the PCIe resets 143, 146, 149, 152, 155 (149: PCIe 5); the platform
  extension sets up TLMM 150 as PCIe 5's CLKREQ# and votes `LDO3_E` and `LDO3_I`. No wake pin shows up (the CRD's
  is TLMM 151).
- The firmware hands over TLMM 140, 142, 149 and 221 as outputs, high: the modem is powered and out of reset before
  Linux starts.

## Device tree

- `x1e80100-microsoft-denali-oled-5g.dts` (patch 0078, 7.2.11 revision 3): the OLED tree plus the CRD's PCIe 5
  block: `vreg_wwan` on TLMM 221 (on at boot), `pcie5` and `pcie5_phy` with `vreg_l3i_0p8` and `vreg_l3e_1p2`,
  reset on TLMM 149, CLKREQ# on 150; no wake pin; the OLED tree's compatibles, model "(OLED, 5G)".
- `vreg_wwan` (`SDX_VPH_PWR`) is also PCIe 5's `vddpe-3v3` supply, and the qcom driver switches its supplies off
  when a sleep takes the link down (host deinit): from 7.2.11 revision 4 on the modem is off in a deep sleep
  (Across a sleep).
- The build gives the tree to the 5G SKU only (`docs/hardware.md`): `SP11_DTB` follows the SKU in `load_hardware`,
  and step 20 checks that PCIe 5 is enabled in the 5G tree and disabled in the OLED tree. A `build/hardware.env`
  from before revision 3 records the OLED tree; `load_hardware` replaces it and says so.
- With the modem up, no RPMh power-domain or interconnect provider waits for `sync_state`.

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
- From revision 8 (patch 0090) the modem's IDs get the generic channel set with the data channels named
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
  `connection.autoconnect yes` (GNOME's has `no`) about 2 s later. A SIM with a PIN asks for it again.
- Revision 5 powers a busy modem down for a suspend started within 15 s of a wake instead of aborting the suspend
  (patch 0082, `docs/sleep.md`).
- Kept powered through the sleep (a test tree, 2026-10-29: `vreg_wwan` with `regulator-always-on` and no longer
  PCIe 5's `vddpe-3v3-supply`; the link still goes down) the modem resumed without a reset or new ports:
  ModemManager's probe answered after 3.4 s, registration after 15.7 s (the 10 s wait included), mobile data
  after 16.7 s. In a 10-minute sleep `ddr` counted 569 of 608 s (579 of 619 s with the modem off), `cxsd` 0 in
  both; the battery's reading moved by the same 0.511 Wh in both runs, too coarse for the modem's own draw.
- Before revision 4 (the link up through the sleep) a night drew the same with the link, without it (the OLED
  tree) and with the radio in `low-power`, within the battery's resolution of about 0.06 W.

## Open

- The wake pin; whether the modem needs to wake the tablet at all.
- The modem kept powered through deep sleep: its cost through a night.
- ModemManager's 10 s wait for the location indication; eSIM profiles from Linux (lpac, not packaged in Fedora).

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
