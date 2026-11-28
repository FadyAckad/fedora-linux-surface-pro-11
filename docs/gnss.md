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
  stops the session and exits 60 s later. The feed logs no position.
- A refused registration or start is retried every 10 s; when the location service leaves QRTR (a modem restart)
  the session starts again once it is back. GeoClue starts its NMEA source only for a client that asks for the
  exact location: a client at city level starts no fix session.
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
- SELinux: systemd 262 labels a socket unit's listening socket with the domain its service will run in
  (`service_determine_exec_selinux_label`: `SELinuxContext=`, else the transition for the executable;
  `SELinuxContextFromNet=` acts on `Accept=yes` instances only). In Fedora 45's policy `geoclue_t` may connect to
  `avahi_t`, `pcscd_t`, `sssd_t`, `systemd_socket_proxyd_t` and, as a `daemon`, `init_t` sockets, and may write
  no socket file under `/run`: no existing type serves the feed.
- Up to support 3.22 `sp11-gnss.cil` let `geoclue_t` connect to any `unconfined_service_t` socket, the domain
  the feed ran in. From 3.23 it gives the feed its own domain: `sp11_gnss_exec_t` on the script, `sp11_gnss_t` by
  transition from `init_t` (with `nnp_transition`: the unit sets `NoNewPrivileges=`), `sp11_gnss_var_run_t` on
  `/run/sp11-gnss`; `geoclue_t`'s one connect rule names `sp11_gnss_t`.
- The domain's rules are those of Fedora's daemon, binary, library and locale interfaces, `kernel_dgram_send` and
  `kernel_read_vm_overcommit_sysctls`. systemd's notify socket carries `kernel_t` on the device, not `init_t`
  (2026-11-27). Python 3.15 reads `/proc/sys/vm/overcommit_memory` at start, which Fedora grants no domain by
  default; its `site` module looks up the running user even under `-I` (`addusersitepackages`), for the unit's
  dynamic user a query to systemd's user database, so the feed starts with `-IS` (the standard library alone).
- `%post` loads the module, relabels the script (rpm labels it before the module exists) and restarts
  `sp11-gnss.socket` while the feed is inactive. A running feed keeps its socket's old label until the next boot:
  restarting the socket would restart the service (`Requires=`) and close GeoClue's connection, which GeoClue
  2.8.2 does not survive (Across a sleep, above).
- rpm labels each package's files with the contexts loaded when its install starts (rpm 6.1, `selinux_psm_pre`):
  in a downgrade to 3.22 the older feed gets `sp11_gnss_exec_t`, which 3.22's module then removes, and on the
  device the feed read as `unlabeled_t` (its socket still listened after a restart). From 3.23 `%postun` relabels
  the feed and restarts its socket after an upgrade or a downgrade.
- On the device (a first build of support 3.23, 2026-11-27): `%post` relabelled the script and restarted the
  socket; the feed ran in `sp11_gnss_t`, GeoClue connected and got 45 fixes; the one denial was `sendto` on the
  notify socket (`kernel_t`), so `READY=1` never arrived and systemd ended the start after its timeout. That build
  lacked `kernel_dgram_send` and the relabel in `%postun`; 3.23 was rebuilt with both.
- On the device (support 3.23, second build, 2026-11-27): the install relabelled the feed and restarted its
  socket; with GNOME Maps near a window the feed became `active` in `sp11_gnss_t` and delivered fixes without a
  denial; across a deep sleep it paused (46 fixes) and resumed (`StatusText=running`); closing Maps stopped the
  session.
- Off-hardware (2026-11-27): the module loads into the Workstation 45 live root's policy (45.23); the feed ran
  against a fake location service over the host's QRTR under socket activation (registration, fixes, the pause's
  statuses, the idle exit). Up to 3.22 the feed caused no denial on the device.
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
- ModemManager instead of the feed would need libqmi's client fields for Register Events (on its main branch since
  2026-07-28, in no release up to 1.38.0; Fedora 45 ships 1.36.0), ModemManager registering as an AFW client
  (1.24.2 and its main branch register for NMEA only) and NMEA from this modem.

## History

- 2026-10-23: the event registration refused for any mask and the cause found in Qualcomm's IDL; GNSS fixes
  without a SIM; the feed in support 3.5 and GeoClue's GNSS location confirmed on the device; its missing
  reconnection after a sleep found and the feed paused across sleep instead (support 3.6).
- 2026-11-27: the feed in its own SELinux domain, GeoClue's access limited to it, the NFW retry of the registration
  and the restart after 120 s without a report removed (support 3.23); a first build timed out at the start (no
  notify rule for `kernel_t`), the second was confirmed on the device.
