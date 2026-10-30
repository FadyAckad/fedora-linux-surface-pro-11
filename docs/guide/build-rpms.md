# Build one set of RPMs alone

Building the kernel, support, pen daemon or sensors RPMs for a system that is already installed, without a new
ISO. Installing the result: [`docs/guide/update.md`](update.md); the full pipeline:
[`docs/guide/build.md`](build.md).

Every set needs a full `scripts/build-all.sh` run first: it provides the host setup, the downloads and the live
root the checks install into. Use that run's `FEDORA_TARGET` and `FEDORA_EDITION` with every command below, and run
step 10 again after a change to `sp11.conf`, since it moves the checkouts to the pinned commits and fetches the
image the settings name:

```bash
scripts/10-fetch-sources.sh
```

## Kernel

Build when `sp11.conf` names a newer Fedora kernel or `KERNEL_SP11_REV` than the installed system runs. A patch set
or `payload/kernel-local` of your own needs a new revision first ([`docs/guide/new-release.md`](new-release.md)):

```bash
scripts/20-build-kernel.sh
```

Step 20 builds when `build/rpms/` holds no `kernel-core` of the configured version (about an hour, with WSL running
throughout); otherwise it only repeats its checks. Then step 36 installs the packages next to the live root's
kernel, as `dnf install` does, and checks the boot entries, the initramfs, the GRUB default and menu, and the way
back. Pass the support RPM of `build/rpms/` as `SUPPORT_PREVIOUS_RPM`, so that it is installed first and writes the
GRUB menu an installed system has; the live root's own menu, Fedora's, fails the menu check:

```bash
SUPPORT_PREVIOUS_RPM=$(ls build/rpms/sp11-surface-support-*.rpm) scripts/36-verify-kernel-install.sh
```

The step ends with `kernel packages verified on an installed system next to` and the live root's kernel. That
kernel must not be the kernel under test, so after an ISO build with the new kernel the step does not apply. The
five packages the ISO installs (`kernel`, `kernel-core`, `kernel-modules-core`, `kernel-modules`,
`kernel-modules-extra`) go from `build/rpms/` to the installed system.

## Support RPM

Build once `VERSION=` in `scripts/30-build-support-rpm.sh` is newer than the installed system's; bump it with every
change to the payload, because `dnf upgrade` acts on the version alone:

```bash
scripts/30-build-support-rpm.sh
```

The step builds when `build/rpms/` holds no support RPM of that version for the target Fedora release, stops when
the payload changed without a new version, and then runs step 35. To check the upgrade the installed system will
make, pass the support RPM that system runs: a copy kept from its build (a new build removes the older RPM from
`build/rpms/`) or the one on its ISO under `/sp11/rpms`:

```bash
SUPPORT_PREVIOUS_RPM=<rpm> scripts/35-verify-support-rpm.sh
```

The result is `build/rpms/sp11-surface-support-<version>-1.fc<release>.aarch64.rpm`.

## Pen daemon

Build once `sp11.conf` pins another iptsd commit or `IPTSD_RPM_RELEASE`:

```bash
scripts/40-build-iptsd-rpm.sh
```

Step 40 builds when `build/rpms/` holds no `sp11-iptsd` of the pinned version, release and commit, in a mock
buildroot of the target release when the host runs another Fedora. Upgrading it on the installed system restarts
the pen daemon.

## Sensors stack

```bash
FEDORA_TARGET=beta scripts/45-build-sensors-rpms.sh
```

This builds `hexagonrpc` (from this project's fork, [`docs/guide/credits.md`](credits.md)), `libssc`,
`iio-sensor-proxy` (Fedora's own source RPM with `-Dssc-support=enabled` and this project's sleep patch) and
`sp11-sensors` in a mock buildroot of the target release (the first run takes a while), and verifies them in the
extracted live root. `SENSORS_VERSION` in `sp11.conf` versions `sp11-sensors`; a changed payload at the same
version stops the step, as does a change in Fedora's iio-sensor-proxy spec until the template is refreshed.
Installing them: [`docs/guide/sensors.md`](sensors.md).
