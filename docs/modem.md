# 5G modem and GNSS
The 5G SKU's Snapdragon X65 modem: its wiring, the device tree that brings it up, what Linux makes of it, and its
GNSS receiver, whose positions reach GeoClue through the support RPM's feed. Established on the tested unit on
2026-10-23 with a test device tree booted once per round; without a SIM (the eSIM holds no profile).

## Hardware

- The modem: PCI `17cb:0308`, subsystem `17cb:0308`, on PCIe 5 (segment 5), an MHI device. It boots from its own
  flash: Windows' modem packages carry no firmware for it, and Linux loads none.
- Windows' GNSS driver ("Qualcomm(R) Location", `qcgnss.dll`) is a client of the modem (`PCI5 > RP1 > MHI1 > QMUX >
  GNSS`); the sensor DSP has no location service.
- Windows' DSDT names the board `PSUB = "CRD08380"`, Qualcomm's reference design, and the wiring is the CRD's
  (`x1-crd.dtsi`): the WWAN power-down device (`QCOM0CDA`) switches the modem's supply with TLMM 221, then TLMM 140
  and 142 (by their names `WDPM` and `GDPM` probably W_DISABLE1# and W_DISABLE2#, the GNSS one: not confirmed) and
  a PMIC pin; the PCIe power extension (`QPPX`) lists the PCIe resets 143, 146, 149, 152, 155 (149: PCIe 5); the
  platform extension sets up TLMM 150 as PCIe 5's CLKREQ# and votes `LDO3_E` and `LDO3_I`. No wake pin shows up
  (the CRD's is TLMM 151).
- The firmware hands over TLMM 140, 142, 149 and 221 as outputs, high: the modem is powered and out of reset before
  Linux starts.

## Device tree

- `x1e80100-microsoft-denali-oled-5g.dts` (patch 0078, 7.2.11 revision 3): the OLED tree plus the CRD's PCIe 5
  block: `vreg_wwan` on TLMM 221 (on at boot), `pcie5` and `pcie5_phy` with `vreg_l3i_0p8` and `vreg_l3e_1p2`,
  reset on TLMM 149, CLKREQ# on 150; no wake pin; the OLED tree's compatibles, model "(OLED, 5G)".
- The build gives it to the 5G SKU only (`docs/hardware.md`): `SP11_DTB` follows the SKU in `load_hardware`, and
  step 20 checks that PCIe 5 is enabled in the 5G tree and disabled in the OLED tree. A `build/hardware.env` from
  before revision 3 records the OLED tree; `load_hardware` replaces it and says so.
- With the modem up, no RPMh power-domain or interconnect provider waits for `sync_state`.

## Linux

- `mhi-pci-generic` binds the modem through its generic entry (`qcom-sdx65m`): the ports `wwan0mbim0`,
  `wwan0qcdm0` and `wwan0qmi0`, the network devices `mhi_hwip0` and `mhi_swip0`, and QRTR over the `IPCR` channel:
  node 2 (IPA control, TFTP, DIAG) and node 3, the modem's QMI services (DMS, NAS, WDS, UIM, the location service
  16 and more).
- The QMI port never answers (`qmicli -d /dev/wwan0qmi0`: `Transaction timed out`). The same services answer over
  QRTR (`qmicli -d qrtr://3`) and as QMI over MBIM (`qmicli -p -d /dev/wwan0mbim0 --device-open-mbim`).
- ModemManager 1.24.2 makes a modem of it with the `generic` plugin and the MBIM port; without a SIM it stays
  `failed` (`esim-without-profiles`), power state low. Its `qcom-soc` plugin probes `qrtr3` and gives up (no QMI
  network port).
- The radio may go online (`--dms-set-operating-mode=online` accepted, `HW restricted: 'no'`): no FCC lock. Mobile
  data needs a SIM or an eSIM profile; not tested.

### The QMI port: ModemManager and suspend

- ModemManager's QMI probe of `wwan0qmi0` takes 45 s (the modem appears 53 s after boot), and the `qmi-proxy` it
  starts ignores SIGTERM, so systemd waits 45 s at shutdown (`State 'final-sigterm' timed out`) and kills it.
- A request queued on the port keeps the MHI controller's `pending_pkts` above zero; `mhi_pm_suspend()` then
  returns `-EBUSY` (`failed to suspend device: -16`), every suspend fails, deep and the s2idle fallback, and the
  tablet is back within seconds. Shown on purpose: one request held on the port made sleep fail, the same boot
  slept with the port idle or closed.
- `77-sp11-modem.rules` (support RPM, 5G builds) sets `ID_MM_PORT_IGNORE` on the port: ModemManager makes the modem
  at 30.8 s, stops in 19 ms, and the tablet sleeps (deep) with the modem powered. Anything else that writes to the
  port still blocks sleep until it closes it.

## GNSS

- The location service (QMI LOC, service 16) on QRTR node 3: engine lock `none`, operation mode `standalone`.
- Event registration (`0x0021`): without a client type (TLV `0x11`) a client counts as non-framework (NFW), which
  must name itself (TLV `0x10`, at most 4 characters), otherwise `InvalidArgument` for any event mask
  (`location_service_v02.h`, Qualcomm's LOC IDL 2.177, in the open `loc_api_v02` sources). libqmi 1.36 sends the
  mask alone, so `qmicli`'s LOC monitoring and ModemManager's location are refused on this modem. Qualcomm's own
  client (`locClientRegisterEventMask`; Windows' `qcgnss.dll` uses `locClientOpen`) registers as an
  application-framework (AFW) client with a client string, which the modem accepts.
- libqmi's LOC enums differ from the IDL here: session status 7 is `engine-locked` (libqmi: 6, like
  `phone-offline`), satellite status 1 to 3 idle, searching, tracking (libqmi: 0 to 2).
- Without a SIM, near a window: first fix 24 s after a cold start, three fixes within 26 s (horizontal uncertainty
  171, 78, 53 m, 4 to 5 GPS satellites); later 6.7 s with 7 satellites (GPS and Galileo). Indoors away from a
  window 1 to 2 satellites and no fix in two minutes. The place decides, not ModemManager: in a boot with the rule
  (ModemManager's power state `low` in round 4) the first fix near a window came about 70 s after the session
  started, then within a second of each new session.
- No NMEA: the NMEA events are accepted but none arrives, and `--loc-get-nmea-types` answers `NotSupported`.

### The feed for GeoClue (support RPM, 5G builds)

- `/usr/libexec/sp11/sp11-gnss` behind `sp11-gnss.socket` (`/run/sp11-gnss/nmea.sock`, root:geoclue 0660), which
  `77-sp11-modem.rules` starts when the modem appears; GeoClue's `[network-nmea]` source connects to it
  (`/etc/geoclue/conf.d/90-sp11-gnss.conf`). While a client is connected the service runs a fix session (AFW
  registration as above, periodic fixes at 1 Hz) and writes each fix as GGA and RMC in one write; without one it
  stops the session and exits 60 s later. GeoClue starts its NMEA source only for a client that asks for the exact
  location: a client at city level starts no fix session. It logs no position.
- GeoClue 2.8.2 does not notice when the NMEA socket closes: end of file reads as an empty line (its workaround for
  GLib issue 655), so it reads again at once, takes a full core and never reconnects until its client stops.
  Support 3.5's sleep hook stopped the service and showed exactly that (no reconnection after the wake on the
  device, 5 s of CPU in 5 s off-hardware). So the feed never closes a connected GeoClue: from 3.6 the hook pauses it
  instead (`SIGUSR1`: the session stops, the connections stay, status `paused`; `SIGUSR2` after the wake), waiting
  up to 5 s for the status (sd_notify; `Type=notify`, ready once its signal handlers are in place, so the hook never
  signals a feed that could not take it).
- GeoClue 2.8.2 derives a fix's accuracy from GGA's HDOP alone (0, 1, 3, 50, 100, 300 m for an HDOP up to 1, 2, 5,
  10, 20, above), so the feed writes the smallest HDOP whose accuracy covers the receiver's horizontal uncertainty;
  fixes less certain than 500 m are left out. Times come from the system clock, which GeoClue compares them with.
- SELinux: systemd labels the listening socket for the service it starts (`unconfined_service_t`), and `geoclue_t`
  may neither connect to that nor write a socket file under `/run`. `sp11-gnss.cil` gives `/run/sp11-gnss` its own
  type (`sp11_gnss_var_run_t`, a `pidfile` type, so systemd manages it) and lets `geoclue_t` write its socket and
  connect to `unconfined_service_t` sockets.
- Off-hardware: Fedora's GeoClue 2.8.2 in the Workstation 45 live root, as user `geoclue` with the drop-in, reported
  a fake receiver's position as "GPS GGA+RMC" with 50 m for 8.5 m, a city-level client started no fix session,
  and across the sleep hook's pause GeoClue kept its connection, stayed idle and got positions again after the
  resume; the feed ran against a fake location service over the kernel's QRTR.
- On the device (support 3.5, near a window): GeoClue reported "GPS GGA+RMC" with 50 m, 50 of 59 locations in 120 s,
  Wi-Fi's 50 m in between; the socket labelled `sp11_gnss_var_run_t`; deep sleep with the modem and a fix session,
  the session stopped before it. With 3.6, a deep sleep while an application asked for the location: the feed paused
  28 ms after the hook's signal and 0.25 s before the suspend, resumed 60 ms after the wake on the same connection
  (134 fixes after it), GeoClue's CPU time under a second. The feed causes no SELinux denial. With Wi-Fi at about
  50 m as well, GeoClue's locations alternate between the two sources, both at 50 m: its HDOP table gives the GNSS
  feed no step between 3 m and 50 m.

## Open

- Battery drain while asleep with the modem powered.
- The wake pin; whether the modem needs to wake the tablet at all.

## History

- 2026-10-23: the modem found on PCIe 5 and brought up with a test device tree (round 1); its services reached over
  QRTR, the radio may go online, the 45 s shutdown traced to ModemManager's `qmi-proxy` (round 2); the event
  registration refused for any mask and the cause found in Qualcomm's IDL (round 3); GNSS fixes without a SIM, and
  the rule for ModemManager (round 4); the failed suspends traced to the QMI port and confirmed (round 5). 7.2.11
  revision 3 and support 3.5 built, the 5G device tree chosen by SKU; GeoClue's GNSS location confirmed on the
  device, its missing reconnection after sleep found and the feed paused across sleep instead (support 3.6).
