# GNSS
The 5G modem's GNSS receiver: its location service, why libqmi's and ModemManager's clients are refused, the fixes
it gives, and the support RPM's feed that passes them to GeoClue. The modem itself: `docs/modem.md`.

## The location service

- QMI LOC (service 16) on QRTR node 3: engine lock `none`, operation mode `standalone`. Windows' GNSS driver
  (`qcgnss.dll`) is a client of the same service.
- Event registration (`0x0021`): without a client type (TLV `0x11`) a client counts as non-framework (NFW), which
  must name itself (TLV `0x10`, at most 4 characters), otherwise `InvalidArgument` for any event mask
  (`location_service_v02.h`, Qualcomm's LOC IDL 2.177, in the open `loc_api_v02` sources). libqmi 1.36 sends the
  mask alone, so `qmicli`'s LOC monitoring and ModemManager's location are refused on this modem. Qualcomm's own
  client (`locClientRegisterEventMask`) registers as an application-framework (AFW) client with a client string,
  which the modem accepts.
- libqmi's LOC enums differ from the IDL here: session status 7 is `engine-locked` (libqmi: 6, like
  `phone-offline`), satellite status 1 to 3 idle, searching, tracking (libqmi: 0 to 2).
- Fixes without a SIM, near a window: the first fix 24 s after a cold start, three fixes within 26 s (horizontal
  uncertainty 171, 78, 53 m, 4 to 5 GPS satellites); later 6.7 s with 7 satellites (GPS and Galileo). Indoors away
  from a window 1 to 2 satellites and no fix in two minutes. The place decides, not ModemManager's state.
- No NMEA: the NMEA events are accepted but none arrives, and `--loc-get-nmea-types` answers `NotSupported`.

## The feed for GeoClue (support RPM, 5G builds)

- `/usr/libexec/sp11/sp11-gnss` behind `sp11-gnss.socket` (`/run/sp11-gnss/nmea.sock`, root:geoclue 0660), which
  `77-sp11-modem.rules` starts when the modem appears; GeoClue's `[network-nmea]` source connects to it
  (`/etc/geoclue/conf.d/90-sp11-gnss.conf`). While a client is connected the service runs a fix session (AFW
  registration as above, periodic fixes at 1 Hz) and writes each fix as GGA and RMC in one write; without one it
  stops the session and exits 60 s later. GeoClue starts its NMEA source only for a client that asks for the exact
  location: a client at city level starts no fix session. The feed logs no position.
- Accuracy: GeoClue 2.8.2 derives a fix's accuracy from GGA's HDOP alone (0, 1, 3, 50, 100, 300 m for an HDOP up
  to 1, 2, 5, 10, 20, above), so the feed writes the smallest HDOP whose accuracy covers the receiver's horizontal
  uncertainty; fixes less certain than 500 m are left out. Times come from the system clock, which GeoClue
  compares them with. With Wi-Fi at about 50 m as well, GeoClue's locations alternate between the two sources, both
  at 50 m: the HDOP table gives the feed no step between 3 m and 50 m.
- Across a sleep: GeoClue 2.8.2 does not notice when the NMEA socket closes (end of file reads as an empty line,
  its workaround for GLib issue 655), so it reads again at once, takes a full core and never reconnects until its
  client stops. Support 3.5's sleep hook stopped the service and showed exactly that; from 3.6 the hook pauses the
  feed instead (`SIGUSR1`: the session stops, the connections stay, status `paused`; `SIGUSR2` after the wake),
  waiting up to 5 s for the status (sd_notify; `Type=notify`, ready once its signal handlers are in place).
- SELinux: systemd labels the listening socket for the service it starts (`unconfined_service_t`), and `geoclue_t`
  may neither connect to that nor write a socket file under `/run`. `sp11-gnss.cil` gives `/run/sp11-gnss` its own
  type (`sp11_gnss_var_run_t`, a `pidfile` type, so systemd manages it) and lets `geoclue_t` write its socket and
  connect to `unconfined_service_t` sockets. The feed causes no denial.
- Off-hardware check: Fedora's GeoClue 2.8.2 in the Workstation 45 live root, as user `geoclue` with the drop-in,
  reported a fake receiver's position as "GPS GGA+RMC" with 50 m for 8.5 m, a city-level client started no fix
  session, and across the sleep hook's pause GeoClue kept its connection and got positions again after the
  resume; the feed ran against a fake location service over the kernel's QRTR.
- On the device (support 3.6, near a window): GeoClue reported "GPS GGA+RMC" with 50 m, 50 of 59 locations in
  120 s, Wi-Fi's 50 m in between; a deep sleep while an application asked for the location: the feed paused 28 ms
  after the hook's signal and 0.25 s before the suspend, resumed 60 ms after the wake on the same connection (134
  fixes after it), GeoClue's CPU time under a second. GeoClue takes the heading from the compass
  (`docs/sensors.md`, Compass).

## Open

- ModemManager waits 10 s at every start of the modem for a location indication this modem never sends
  (`docs/modem.md`, Across a sleep).

## History

- 2026-10-23: the event registration refused for any mask and the cause found in Qualcomm's IDL; GNSS fixes
  without a SIM; the feed in support 3.5 and GeoClue's GNSS location confirmed on the device; its missing
  reconnection after a sleep found and the feed paused across sleep instead (support 3.6).
