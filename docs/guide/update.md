# Update an installed system

Updating the support RPM, installing a new SP11 kernel next to the current one, and what dnf does with kernels. The
RPMs come from `build/rpms/` after a build, or from the ISO the system was installed from, which carries every RPM
it installed (kernel, support, iptsd and the sensors stack) under `/sp11/rpms`. Systems installed from ISOs built
before 2026-09-22 need the one-time steps in [`docs/guide/troubleshooting.md`](troubleshooting.md).

## Support RPM

New support-RPM versions install over the old one. Copy the RPM to Fedora and run:

```bash
sudo dnf upgrade ./sp11-surface-support-<version>-1.fc<release>.aarch64.rpm
```

The package regenerates the GRUB menu itself; upgrading `sp11-iptsd` restarts the pen daemon. Rebuild
the ISO afterwards so new installations get the same version. What each version changed:
[`docs/guide/support-rpm-history.md`](support-rpm-history.md).

## Kernel

A new SP11 kernel installs next to the current one, like Fedora's own kernels, from the directory holding its
packages (support RPM 3.0 or later; with an earlier support RPM, whose dnf exclusion also hides local kernel RPMs,
add `--setopt=disable_excludes='*'`):

```bash
sudo dnf install ./kernel{,-core,-modules-core,-modules,-modules-extra}-<version>-<release>.sp11.<revision>.fc45.aarch64.rpm
```

It gets its own boot entry with the Denali DTB and the kernel arguments and becomes the default; the
previous kernel stays in the GRUB menu. dnf keeps at most three kernels per package name
(`installonly_limit`) and removes the oldest one in the transaction that installs a fourth (never the running one).
Check `df -h /boot` before installing another kernel (each SP11 kernel takes about 195 MB there), because a dracut
failure inside the install leaves the new kernel without a boot entry and only the transaction's output says so.

Stock Fedora kernels are hidden from every configured repository (support RPM 3.0), since they lack the SP11 patch
set; `dnf upgrade` leaves the kernel alone until an SP11 build of a newer Fedora kernel is installed from local
RPMs. The override is `/usr/share/dnf5/repos.override.d/90-sp11-kernel.repo`, and
`dnf --setopt=disable_excludes='*' ...` lifts it for one command. Kernels of the earlier `kernel-sp11` package stay
installed next to the new ones until removed; see [`docs/guide/troubleshooting.md`](troubleshooting.md).

## Sensors stack

The four sensors RPMs are updated together, in one transaction: [`docs/guide/sensors.md`](sensors.md).
