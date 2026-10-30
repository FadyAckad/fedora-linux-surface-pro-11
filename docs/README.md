# Documentation index

The documentation has two tiers. The guides under `docs/guide/` are for users and builders: procedures, results
and the reasons behind the design, written to stand on their own; `README.md` lists them by reader intent. The
notes under `docs/` are for maintainers: dense, verified facts, measurements and lessons, by topic, each with a
short dated history at its end. A guide states only what a note holds the evidence for.

## Guides

`overview` (how it works, glossary), `install`, `update`, `troubleshooting`, `build`, `build-rpms`, `sensors`,
`bluetooth-pairings`, `new-release`, `design`, `support-rpm-history`, `layout`, `credits`.

## Notes

Read the note named below before working on its area.

- `docs/pipeline.md`: the repository's files and the build tree, the verification steps 35, 36, 46 and 60, the
  version and content-pin rules, the WSL host, shell pitfalls. Read before touching `sp11.conf`, `scripts/`,
  `rpm/` or `payload/`.
- `docs/hardware.md`: the tested unit and how the build identifies it, firmware, audio, Wi-Fi, Bluetooth, pen,
  power supplies, video codec, USB-C, the live-only DSP blacklist, the Windows GRUB entry, the Bluetooth pairings
  shared with Windows. Read before anything that depends on the device.
- `docs/sleep.md`: deep sleep and its wake sources, what kept the memory awake and the drain measured, the wakes
  without a wake interrupt, the power key under KDE. Read before touching sleep or power.
- `docs/kernel.md`: Fedora's kernel rebuilt with the SP11 patch set: `kernel.spec`'s slots, the revision table and
  `KERNEL_SP11_REV`, the configuration, sync state and the CDSP, the rebase procedure, install and removal,
  SELinux. Read before touching steps 10 and 20, `payload/kernel-local`, the `KERNEL_PATCH_*` pins or SELinux.
- `docs/kernel-patches.md`: the patch manifest: each revision's provenance, every patch with its origin and
  purpose, what was left out of v23.2, the planned patch for the power key's waking press.
- `docs/fedora-media.md`: the live media, GRUB, Anaconda and the installer's viewer, kernel-install and BLS
  entries, the live initramfs and root, the Fedora 45 differences. Read before touching steps 50 and 60, GRUB, the
  installer path or a Fedora release switch.
- `docs/sensors.md`: the Snapdragon Sensor Core stack (hexagonrpc, libssc, iio-sensor-proxy, sp11-sensors): the
  inputs from Windows, packaging, runtime design, the compass, known issues. Read before touching steps 45, 46
  and 75, `payload/sensors/` or the hexagonrpc fork.
- `docs/tablet-mode.md`: the tablet-mode switch, the orientation matrix, what GNOME and KDE need for
  auto-rotation, the posture probe. Read before touching patch 0057 or the udev rule's matrix.
- `docs/modem.md`: the 5G SKU's modem: the wiring, the 5G device tree by SKU, the QMI port that blocked suspend,
  mobile data, the modem across a sleep. Read before touching the 5G tree, `77-sp11-modem.rules` or
  `mhi-pci-generic`.
- `docs/gnss.md`: the modem's location service and the GNSS feed for GeoClue with its SELinux module. Read before
  touching `payload/sp11-gnss*`.
- `docs/camera.md`: the three cameras: the kernel side, Fedora's libcamera, the raw-capture probe, what the device
  has shown. Read before touching `payload/camera/` or the kernel fork's camera commits.
- `docs/verified.md`: what has been confirmed on the device, by date and package version. Read before stating
  that something works; add to it after a device round.

## Conventions

- Notes hold verified facts and lessons only: the current state, rules and pins, pitfalls, the measurements that
  establish a fact, known issues with their status, and a one-line-per-date history. Superseded states and round
  logs are cut; git history keeps them.
- Lines wrap at 116 columns with code spans kept whole, so phrases stay greppable; table rows are the exception.
- The notes name documents by plain path in backticks; `README.md` and the guides use markdown links.
- Section names other files cite (`docs/hardware.md`, USB-C data; `docs/sensors.md`, Known issues;
  `docs/fedora-media.md`, Anaconda; `docs/kernel.md`, Sync state) stay as they are, or every citation moves. Two
  RPM spec templates cite `docs/sensors.md`, Known issues, and the templates are part of the RPM input hashes.
- Tracked files carry no per-unit identifiers (`CLAUDE.md`, Rules).
- The full standard, with what to update after a device round, and its validator:
  `.claude/skills/sp11-docs/` (`SKILL.md`, `validate.py`).
