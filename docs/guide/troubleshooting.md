# Troubleshooting

The diagnostic tools, the known limitations, and the one-time steps for systems installed from earlier ISOs. The
device results by date are in [`docs/verified.md`](../verified.md).

## Diagnostics

`sudo /usr/libexec/sp11/sp11-diag` writes `sp11-diag-<date>-<time>.txt` to the current directory (or to the path
given as its argument) and changes nothing. It records the kernel, its arguments, the device tree's compatible
string and the hardware IDs (`systemd-analyze chid`), the security modules with `getenforce` and the AVC denials of
the boot, the touchscreen driver and the pen's HIDRAW bridge with the iptsd units, the input devices, the boot's
suspend and resume history, the Bluetooth controller with `bluetoothctl info` for every device BlueZ knows, the
sound card's raw controls (`amixer -D hw:N`) and PipeWire's default source, the sensors stack (`sp11-sensors-check`,
when `sp11-sensors` is installed), a section that diffs cleanly between two kernels (every device bound to a driver,
the loaded modules, the remote processors, the FastRPC nodes, cpufreq, power supplies, hwmon, the platform
profile), the power-domain and interconnect providers still holding their boot-time votes and the devices they wait
for, and the boot's kernel warnings and journal errors. The file names the Bluetooth controller and every device
BlueZ knows by address.

`sudo /usr/libexec/sp11/sp11-sensors-check`, run from a terminal in the desktop, covers the sensors stack and
tablet mode ([`docs/guide/sensors.md`](sensors.md)).

## Known limitations

- In the live session, audio and battery status are unavailable because the audio DSP stays off while running
  from USB-C (an ADSP restart resets the port); both work once installed.
- Once in a boot, a few minutes after it, the compute DSP's firmware can report a `sleep_stats` fatal error;
  remoteproc restarts that DSP by itself, and nothing on Linux uses it.
- Boot messages seen on the tested unit that mean nothing: `qcom_pmic_glink … Failed to create device link` for the
  PD and USB nodes (probe deferral, retried), `surface_hid … unexpected descriptor length` for one Surface
  Aggregator endpoint nothing depends on, `unknown device posture for type-cover: 0` once each time the keyboard
  is attached, and the ADSP's `Handover signaled, but it already happened` lines since the sensors stack.

## Systems installed from earlier ISOs

Installations made from ISOs built before 2026-09-22 carry the ISO's build date as the modification time of
every file the installer copied (the remaster stamped the live image that way; `ls -l /usr/bin/bash` shows
it). It costs a bytecode recompile at every Python start and `rpm -V` flags the times; nothing malfunctions,
and updated packages and the next installation carry proper times.

Systems installed from ISOs built before 2026-09-22 (the earlier kernels had AppArmor as their active security
module) were installed with SELinux *disabled*: the live installer saw no SELinux and passed `--noselinux` to
Anaconda, which put `selinux=0` into the boot arguments and `SELINUX=disabled` into `/etc/selinux/config`. Support
RPMs 2.5 to 2.7 undid that by themselves; 3.0 no longer does, so such a system needs it once by hand:
`sudo grubby --update-kernel=ALL --remove-args=selinux=0`, `SELINUX=enforcing` in `/etc/selinux/config`,
`sudo touch /.autorelabel` and a reboot (the next boot relabels and reboots once). Confirmed on the tested unit on
2026-09-19; it was reinstalled from SELinux media on 2026-09-22.

Kernels of the earlier `kernel-sp11` package stay installed next to the Fedora-based ones until removed with
`sudo dnf remove kernel-sp11-<version>`; `kernel-sp11` RPMs built before 2026-09-17, such as the 7.2.0 one, leave
their boot entry behind when removed while another kernel stays, so run
`sudo kernel-install remove 7.2.0-jg-0sp11v23-qcom-x1e` first (`ls /boot/loader/entries` shows a leftover entry;
the same command cleans it up after the fact).
