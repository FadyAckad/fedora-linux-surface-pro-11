# Sensors

The accelerometer, gyroscope, magnetometer and ambient light sensor: what the stack is, how to install or update it
on an installed system, and how to check and reset it. How it works, and its device history, are in
[`docs/sensors.md`](../sensors.md). Building its RPMs is part of [`docs/guide/build.md`](build.md).

The sensors hang off the Snapdragon Sensor Core, the sensor framework inside the ADSP firmware, not off any bus
Linux can see. Four RPMs reach them with free software: `hexagonrpc` serves the framework its configuration and
registry, `libssc` talks to it, an SSC-enabled build of `iio-sensor-proxy` (Fedora's lacks it, as `libssc` is not
packaged) feeds the desktop, and `sp11-sensors` carries this unit's files. The readings need no kernel change;
GNOME's auto-rotation also needs the tablet-mode switch fix of the SP11 patch set. The stack is inert on the live
media, which runs without the ADSP, and active on the installed system from its first boot.

## Install or update

The four RPMs come from a build (`build/rpms/`, step 45 of [`docs/guide/build.md`](build.md)) or from the ISO's
`/sp11/rpms`. `sp11-sensors` carries this unit's sensor registry, exported once from Windows by
`scripts/75-export-sensor-registry.sh`. On an installed system that lacks the stack or runs an older build, run
this from the directory holding the RPMs:

```bash
sudo dnf install --setopt=disable_excludes='*' ./hexagonrpc-*.rpm ./libssc-0*.rpm ./iio-sensor-proxy-*.rpm ./sp11-sensors-*.rpm
```

Reboot after installing. The framework reads and writes its registry in a copy under
`/var/lib/sp11/hexagonrpc/sensors/persist`; `sudo /usr/libexec/sp11/sp11-sensors-reset` rebuilds that copy from
the package, effective at the next boot. After an ADSP crash the daemon does not attach again in the same boot, so
a failure costs one recoverable crash and a log rather than a loop; a reboot brings the stack back.

`sp11-sensors` excludes `iio-sensor-proxy` from dnf updates, since a later Fedora build would replace the
SSC-enabled one without a word. The exclusion also covers a local RPM of that package, hence
`--setopt=disable_excludes='*'` in the command above, the same override as for the kernel packages; a plain
`dnf upgrade` keeps the SP11 build. Never stop or restart the ADSP through `/sys/class/remoteproc` to "reset" the
sensors: that resets the SoC.

## Check

Run `sudo /usr/libexec/sp11/sp11-sensors-check` from a terminal in the desktop. It shows the stack from the boot
timeline to the desktop: one reading per sensor (`ssccli`), what iio-sensor-proxy sees (`monitor-sensor`) and the
tablet-mode state. GNOME offers its auto-rotate button while the keyboard is folded back or detached, and its
automatic screen brightness uses the same light sensor. Under KDE Plasma the check's query to GNOME's mutter ends in
a D-Bus error, and the rest of its output applies. The gyroscope and magnetometer have no desktop consumer; read
them with `ssccli --sensor gyroscope` / `--sensor magnetometer`.

Reference: denisix/ubuntu-surface-pro-11 (`SENSORS.md`) reports all 13 sensors of the framework working on a
Surface Pro 11 with this approach.
