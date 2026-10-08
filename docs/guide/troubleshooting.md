# Troubleshooting

The diagnostic tools, the known limitations, the power button setting under KDE Plasma, and the one-time steps for
systems installed from earlier ISOs. The device results by date are in [`docs/verified.md`](../verified.md).

## Diagnostics

`sudo /usr/libexec/sp11/sp11-diag` writes `sp11-diag-<date>-<time>.txt` to the current directory, or to the path
given as its argument, and changes nothing. It records the kernel, security, input, Bluetooth, audio, sensors and
camera state, a section that diffs cleanly between two kernels, the power-domain and interconnect providers still
holding their boot-time votes, and the boot's kernel warnings and journal errors. The file names the Bluetooth
controller and every device BlueZ knows by address.

`sudo /usr/libexec/sp11/sp11-sensors-check`, run from a terminal in the desktop, covers the sensors stack and
tablet mode ([`docs/guide/sensors.md`](sensors.md)).

## Known limitations

- In the live session, audio and battery status are unavailable because the audio DSP stays off while running
  from USB-C (an ADSP restart resets the port). Both work once installed.
- Once in a boot, a few minutes after it, the compute DSP's firmware can report a `sleep_stats` fatal error.
  remoteproc restarts that DSP by itself, and nothing on Linux uses it.
- Auto-rotation and the light sensor stopping until iio-sensor-proxy is restarted, seen under KDE Plasma, whose
  clients claim and release the sensors around screen-off and wake. Fixed in `libssc` 0.4.4-3 (2026-10-07), part
  of the sensors RPMs since then; on an earlier release `sudo systemctl restart iio-sensor-proxy` brings them back
  ([`docs/sensors.md`](../sensors.md), Known issues).
- Under KDE Plasma the tablet woke within seconds of going to sleep, and with the cover closed slept and woke in a
  loop, while automatic brightness (or auto-rotation in tablet mode) kept a sensor stream open: the audio DSP's
  messages ended the sleep. Fixed in `iio-sensor-proxy` 3.9-3.sp11.2 with `sp11-sensors` 1.11 (2026-10-08), part
  of the sensors RPMs since then; with an earlier build, switching automatic brightness off (System Settings,
  Display & Monitor) avoids it ([`docs/sensors.md`](../sensors.md), Known issues).
- Plugging the charger in while the tablet sleeps wakes it, sometimes several times in the first minutes. Under
  KDE Plasma, with the cover closed, it goes back to sleep about 10 s after each wake.
- Up to `sp11-sensors` 1.11, after many sleeps in one boot `hexagonrpcd-adsp-sensorspd.service` was listed as
  failed (`start-limit-hit`): its guard allowed twelve starts per boot, and every wake restarted it. The sensors
  kept working. Fixed in 1.12 (2026-10-08), which no longer counts the restart after a wake.
- Under KDE Plasma, with the power button set to Sleep, waking the tablet with the power key puts it back to sleep
  a few seconds later: the power key's driver reports the press that woke it, and KDE takes it as a press to sleep.
  Set the power button to Lock screen (below); opening the cover wakes it without that either way
  ([`docs/hardware.md`](../hardware.md), Sleep).
- Upgrading `iio-sensor-proxy` from 3.9-3.sp11.1 can pause `dnf` for about 45 s and leave an `iio-sensor-proxy`
  core dump: the old proxy does not stop in time and systemd aborts it. The reboot after the install brings up the
  new one ([`docs/guide/sensors.md`](sensors.md)).
- Boot messages seen on the tested unit that mean nothing:
  - `qcom_pmic_glink … Failed to create device link` for the PD and USB nodes (probe deferral, retried);
  - `surface_hid … unexpected descriptor length` for one Surface Aggregator endpoint nothing depends on;
  - `unknown device posture for type-cover: 0`, once each time the keyboard is attached;
  - the ADSP's `Handover signaled, but it already happened` lines: about one per second while a sensor stream is
    open; since `iio-sensor-proxy` 3.9-3.sp11.2 no stream stays open during a sleep.

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
([`docs/hardware.md`](../hardware.md), Sleep). A kernel change that drops the waking press is described in
[`docs/kernel-patches.md`](../kernel-patches.md).

## Systems installed from earlier ISOs

Installations made from ISOs built before 2026-09-22 carry the ISO's build date as the modification time of every
file the installer copied (`ls -l /usr/bin/bash` shows it). `rpm -V` flags the times and Python recompiles its
bytecode at every start, but nothing malfunctions; updated packages and the next installation carry proper times.

The same installations run with SELinux *disabled*: the earlier kernels had AppArmor as their active security
module, so the live installer passed `--noselinux` to Anaconda, which put `selinux=0` into the boot arguments and
`SELINUX=disabled` into `/etc/selinux/config`. Support RPMs 2.5 to 2.7 undid that by themselves; 3.0 no longer
does. Such a system needs it once by hand:

- `sudo grubby --update-kernel=ALL --remove-args=selinux=0`;
- `SELINUX=enforcing` in `/etc/selinux/config`;
- `sudo touch /.autorelabel`;
- a reboot (the next boot relabels and reboots once).

Kernels of the earlier `kernel-sp11` package stay installed next to the Fedora-based ones until removed with
`sudo dnf remove kernel-sp11-<version>`. `kernel-sp11` RPMs built before 2026-09-17, such as the 7.2.0 one, leave
their boot entry behind when removed while another kernel stays, so run
`sudo kernel-install remove 7.2.0-jg-0sp11v23-qcom-x1e` first. `ls /boot/loader/entries` shows a leftover entry,
and the same command cleans it up after the fact.
