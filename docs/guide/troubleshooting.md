# Troubleshooting

The diagnostic tools, the known limitations, and the one-time steps for systems installed from earlier ISOs. The
device results by date are in [`docs/verified.md`](../verified.md).

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
- Boot messages seen on the tested unit that mean nothing:
  - `qcom_pmic_glink … Failed to create device link` for the PD and USB nodes (probe deferral, retried);
  - `surface_hid … unexpected descriptor length` for one Surface Aggregator endpoint nothing depends on;
  - `unknown device posture for type-cover: 0`, once each time the keyboard is attached;
  - the ADSP's `Handover signaled, but it already happened` lines, since the sensors stack.

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
