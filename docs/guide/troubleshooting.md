# Troubleshooting

The diagnostic tools, the known limitations, what earlier releases of the RPMs fixed, and the power button setting
under KDE Plasma. The device results by date are in [`docs/verified.md`](../verified.md).

## Diagnostics

`sudo /usr/libexec/sp11/sp11-diag` writes `sp11-diag-<date>-<time>.txt` to the current directory, or to the path
given as its argument, and changes nothing. It records the kernel, security, input, Bluetooth, audio, sensors and
camera state, a section that diffs cleanly between two kernels, the power-domain and interconnect providers still
holding their boot-time votes, and the boot's kernel warnings and journal errors. The file names the Bluetooth
controller and every device BlueZ knows by address.

`sudo /usr/libexec/sp11/sp11-sensors-check`, run from a terminal in the desktop, covers the sensors stack and
tablet mode ([`docs/guide/sensors.md`](sensors.md)). Both list SELinux denials since support RPM 3.7 and
`sp11-sensors` 1.14; earlier versions searched only the kernel's messages and showed none.

## Known limitations

- In the live session, audio and battery status are unavailable because the audio DSP stays off while running
  from USB-C (an ADSP restart resets the port). Both work once installed.
- USB-C data works with the plug one way round; turned over, a USB 3 stick is not found on either port, while
  Windows finds it both ways ([`docs/hardware.md`](../hardware.md), USB-C data).
- Once in a boot, a few minutes after it, the compute DSP's firmware can report a `sleep_stats` fatal error.
  remoteproc restarts that DSP by itself, and nothing on Linux uses it.
- GPS (5G SKU) needs a view of the sky: near a window the first position came within about a minute, away from
  windows none in two minutes. Until then, and wherever GPS is weaker, GeoClue gives the Wi-Fi location
  ([`docs/gnss.md`](../gnss.md)).
- Mobile data (5G SKU, kernel revision 8 or later): Fedora's provider list offers no APN for some carriers (o2
  Germany: set `internet` in Settings > Mobile Network). The modem restarts after every sleep, so a SIM with a PIN
  asks for it again, and the connection returns about a minute after a wake only if it connects automatically
  ([`docs/modem.md`](../modem.md), Mobile data).
- Plugging the charger in while the tablet sleeps wakes it, sometimes several times in the first minutes. Under
  KDE Plasma, with the cover closed, it goes back to sleep about 10 s after each wake.
- Under KDE Plasma, with the power button set to Sleep, waking the tablet with the power key puts it back to sleep
  a few seconds later. Set the power button to Lock screen (below).
- Boot messages seen on the tested unit that mean nothing:
  - `qcom_pmic_glink … Failed to create device link` for the PD and USB nodes (probe deferral, retried);
  - `surface_hid … unexpected descriptor length` for one Surface Aggregator endpoint nothing depends on;
  - `unknown device posture for type-cover: 0`, once each time the keyboard is attached;
  - the ADSP's `Handover signaled, but it already happened` lines, about one per second while a sensor stream is
    open.

## Fixed in earlier releases

Systems running an older build of the RPMs can show these; the release named fixes each.

- Auto-rotation and the light sensor stopping until iio-sensor-proxy is restarted, under KDE Plasma: fixed in
  `libssc` 0.4.4-3 (2026-10-07). Until then `sudo systemctl restart iio-sensor-proxy` brings them back
  ([`docs/sensors.md`](../sensors.md), Known issues).
- The tablet waking within seconds of going to sleep under KDE Plasma, and sleeping and waking in a loop with the
  cover closed, while automatic brightness or auto-rotation kept a sensor stream open: fixed in `iio-sensor-proxy`
  3.9-3.sp11.2 with `sp11-sensors` 1.11 (2026-10-08). Until then, switching automatic brightness off (System
  Settings, Display & Monitor) avoids it.
- `hexagonrpcd-adsp-sensorspd.service` listed as failed (`start-limit-hit`) after many sleeps in one boot, the
  sensors still working: fixed in `sp11-sensors` 1.12 (2026-10-08).
- GeoClue without a heading from the compass: `sp11-sensors` 1.13 (2026-10-23). Five SELinux denials logged by
  iio-sensor-proxy at every start, the sensors working regardless: `sp11-sensors` 1.15 (2026-10-24).
- Upgrading `iio-sensor-proxy` from 3.9-3.sp11.1 can pause `dnf` for about 45 s and leave an `iio-sensor-proxy`
  core dump: the old proxy does not stop in time and systemd aborts it. The reboot after the install brings up the
  new one.

## The power button under KDE Plasma

The press that wakes the tablet from the power key reaches KDE as an ordinary press of the power button. With the
button set to Sleep, KDE puts the tablet back to sleep 1 to 6 s after such a wake. Set it to Lock screen instead:
the waking press then locks the session, which is already locked after a sleep, and the button locks the screen
while the tablet is awake. Sleep with the cover or from the application launcher. "Do nothing" also ignores the
press, but KDE then does not load its button handling at all, so Lock screen is the setting used here. In tablet
mode KDE's power management does not handle the power button (it unbinds its shortcut), so the setting applies with
the keyboard attached.

In System Settings, Power Management, set "When power button pressed" to "Lock screen" on each of the tabs On AC
Power, On Battery and On Low Battery. The same from a terminal in the desktop:

```bash
for p in AC Battery LowBattery; do kwriteconfig6 --file powerdevilrc --group "$p" --group SuspendAndShutdown --key PowerButtonAction 32; done
```

```bash
busctl --user call org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement org.kde.Solid.PowerManagement reparseConfiguration
```

To check, sleep from the launcher with the cover open, wake with the power key and wait 15 s: the tablet stays on
the lock screen. With the cover closed it goes back to sleep 10 s after any wake, by design
([`docs/sleep.md`](../sleep.md)). A kernel change that drops the waking press is described in
[`docs/kernel-patches.md`](../kernel-patches.md).
