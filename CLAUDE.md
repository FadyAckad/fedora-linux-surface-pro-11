# CLAUDE.md — Fedora live ISO for Surface Pro 11 (5G, X1E80100, OLED)

Working notes for future sessions, kept by topic under `docs/`. Everything in them was verified in September 2026
on the tested unit described in `docs/hardware.md`; re-verify anything that depends on a newer Fedora, GRUB,
Anaconda or ooaklee release. Only this file is loaded automatically: read the document named below before working
on its area.

## Documents

- `docs/pipeline.md`: what each file of the repository is, the pipeline steps and their caches, the verification
  steps 35, 36, 46 and 60, the version and content-pin rules, the WSL host, shell pitfalls. Read before touching
  `sp11.conf`, `scripts/`, `rpm/` or `files/`.
- `docs/hardware.md`: the tested unit's identity, the Denali DTB and the SKU regexes, firmware, audio, Wi-Fi, the
  Bluetooth address, the pen, the live-only DSP blacklist, the Windows GRUB entry, the Bluetooth pairings shared
  with Windows. Read before anything that depends on the device.
- `docs/kernel.md`: the ooaklee kernel (OE), the stable update, `KERNEL_SP11_REV`, the LSM policy and SELinux,
  kernel install and removal. Read before touching step 20, `files/kernel-sp11-fedora.config`,
  `files/kernel-patches/` or SELinux.
- `docs/fedora-media.md`: the live media, GRUB, Anaconda's installation order, the kernel-install plugin, the live
  initramfs and root, and the Fedora 45 differences. Read before touching steps 50 and 60, GRUB, the installer
  path or a Fedora release switch.
- `docs/sensors.md`: the Snapdragon Sensor Core stack (hexagonrpc, libssc, iio-sensor-proxy, sp11-sensors), tablet
  mode and auto-rotation; its dated history is at the end. Read before touching steps 45, 46 and 75,
  `files/sensors/` or the hexagonrpc fork.
- `docs/verified.md`: what has been confirmed on the device, by date and package version. Read before stating
  that something works; add to it after a device round.

## Layout

- `sp11.conf` (versions, URLs, regexes, boot policy, content pins; sourced through `scripts/lib.sh`),
  `scripts/NN-*.sh` (the pipeline steps; "step 50" in the notes means `scripts/50-build-iso.sh`), `rpm/*.spec.in`
  (spec templates).
- `files/`: payload of the support RPM (`files/15-sp11-surface.install` is the kernel-install plugin), the kernel
  config fragment and `files/kernel-patches/`, the live GRUB menu template, and `files/sensors/` (the sensors
  stack's packaged files and the unpackaged posture probe).
- `docs/`: the working notes. `build/` (git-ignored): caches, work trees, RPMs and output; see `docs/pipeline.md`.

## Rules

- The repo is public under GPL-3.0-or-later (`LICENSE`; the support RPM's `License:` tag must agree). Tracked files
  carry no per-unit identifiers: Bluetooth/Wi-Fi/peripheral addresses, firmware versions, local paths and the
  owner's name stay out of `CLAUDE.md`, `README.md`, `docs/`, `files/` and `scripts/`. Per-unit values live in
  `build/hardware.env`, `build/bt-pairings/`, `build/sensors/` and, inside the built RPMs,
  `/etc/sp11/bluetooth-address` and the `sp11-sensors` registry. Check before staging:
  `git grep -nE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'` must show only the `AA:BB:CC:DD:EE:FF` placeholders.
- `CLAUDE.local.md` (git-ignored, loaded by Claude Code after this file) holds the owner's private working rules and
  hand-off notes. `.gitattributes` forces LF. `.gitignore` also blocks `hardware.env`, `*.hiv`, `*.iso`, `*.rpm` and
  the pairing tarball anywhere in the tree.

## Version bumps

Rationale and the enforcement (content pins and input hashes since 2026-09-22) in `docs/pipeline.md`.

- Support payload: `VERSION=` in `scripts/30-build-support-rpm.sh`.
- `files/kernel-sp11-fedora.config` or `files/kernel-patches/`: `KERNEL_SP11_REV` and `KERNEL_SP11_REV_SHA256` in
  `sp11.conf` (step 20 prints the value to set).
- In `sp11.conf`: `IPTSD_RPM_RELEASE` (the iptsd spec), `HEXAGONRPC_RPM_RELEASE` (the number, for the spec, its
  payload or the pinned commit), `LIBSSC_RPM_RELEASE` (the libssc spec), `IIO_SENSOR_PROXY_RPM_SUFFIX` (its
  template; `IIO_SENSOR_PROXY_BASE_SPEC_SHA256` for a new SRPM), `SENSORS_VERSION` (`files/sensors/`, the
  sp11-sensors spec, the registry export).

## Conventions

- Notes by topic, verified facts and lessons only; a compact dated history at the end of a topic, no round logs.
- Lines wrap at 116 columns with code spans kept whole, so phrases stay greppable.
- Keep the index above accurate when a document changes. Name documents by plain path in backticks, never
  `@path`: Claude Code inlines `@` imports into every session.

## References

rjindael/fedora-surface-pro-11 (Fedora bring-up notes); ooaklee/linux-surface-pro-11-oe (kernel, audio, iptsd
releases, ADRs); ooaklee/lexr.sh `internal/image/fedora/*.go` (remaster design reference);
denisix/ubuntu-surface-pro-11 (`SENSORS.md`: the SSC sensor stack on an SP11 under Ubuntu); linux-msm/hexagonrpc;
DylanVanAssche/libssc (codeberg); Fedora wiki "Snapdragon WoA Laptop Install"; Arch wiki "Bluetooth" (dual-boot
pairing).
