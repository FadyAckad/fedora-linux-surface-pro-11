# Sensors

The accelerometer, gyroscope, magnetometer and ambient light sensor: what the stack is, how to install or update it
on an installed system, and how to check and reset it. How it works, and its device history, are in
[`docs/sensors.md`](../sensors.md); building its RPMs is part of [`docs/guide/build.md`](build.md).

The sensors are not on any bus Linux can see: they hang off the Snapdragon Sensor Core, the sensor framework
running inside the ADSP firmware, and Windows reads them through a QMI client. The same path works on Linux
with free software: `hexagonrpcd` serves the framework its configuration and registry over FastRPC, `libssc`
talks to it over QRTR, and upstream `iio-sensor-proxy` 3.9 has drivers for it that Fedora builds out only
because `libssc` is not packaged in Fedora. The readings need no kernel change; GNOME's auto-rotation also
needs the tablet-mode switch fix, the last patch of the SP11 patch set. The ISO carries the stack (inert on the
live media, which runs without the ADSP; active on the installed system from its first boot) and its four RPMs
under `/sp11/rpms`. Confirmed on the tested unit: readings from the light sensor, accelerometer, gyroscope,
magnetometer and compass, the orientation and the compass in iio-sensor-proxy, auto-rotation on the desktop and
automatic screen brightness.

## Install or update

The four RPMs come from a build (`build/rpms/`, step 45 of [`docs/guide/build.md`](build.md); `sp11-sensors` carries
this unit's sensor registry, exported once from Windows by `scripts/75-export-sensor-registry.sh`) or from the ISO's
`/sp11/rpms`. On an installed system that lacks the stack or runs an older build, from the directory holding the
RPMs:

```bash
sudo dnf install ./hexagonrpc-*.rpm ./libssc-0*.rpm ./iio-sensor-proxy-*.rpm ./sp11-sensors-*.rpm
```

Reboot after installing. The framework reads its registry when the file server first attaches after the ADSP
has booted, and writes into it while doing so; the fork serves those writes (upstream refuses them, and this
firmware then aborts the ADSP) into a copy of the registry under `/var/lib/sp11/hexagonrpc/sensors/persist`.
`sudo /usr/libexec/sp11/sp11-sensors-reset` rebuilds that copy from the package, effective at the next boot.
The framework compares the modification time of every configuration file with the stamp it recorded when it
parsed the file, so the package ships the files with Windows' times. A guard on the daemon's unit stops it
from attaching again after an ADSP crash in the same boot, so a failure costs one recoverable crash and a
log rather than a loop.

`sp11-sensors` excludes `iio-sensor-proxy` from dnf updates, since a later Fedora build would replace the
SSC-enabled one without a word. The exclusion also covers a local RPM of that package, so install the four
in one command as above, and install a later SP11 build of it with
`sudo dnf --setopt=disable_excludes='*' install ./iio-sensor-proxy-<version>.rpm`, the same override as for
the kernel packages. Never stop or restart the ADSP through `/sys/class/remoteproc` to "reset" the sensors:
that resets the SoC.

## Check

`sudo /usr/libexec/sp11/sp11-sensors-check`, run from a terminal in the desktop, shows the boot timeline,
the daemon and what the framework wrote, one reading per sensor (`ssccli`), what iio-sensor-proxy sees
(`monitor-sensor`) and the tablet-mode state GNOME uses. GNOME offers its auto-rotate button while the
keyboard is folded back or detached. Its automatic screen brightness uses the same light sensor
(confirmed on 2026-09-24). The gyroscope and magnetometer have no desktop consumer and are read with
`ssccli --sensor gyroscope` / `--sensor magnetometer`.

Reference implementation: denisix/ubuntu-surface-pro-11 (`SENSORS.md`), which reports all 13 sensors of the
framework working on a Surface Pro 11 with this approach.
