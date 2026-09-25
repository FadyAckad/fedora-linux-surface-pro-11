# CLAUDE.md — Fedora live ISO for Surface Pro 11 (5G, X1E80100, OLED)

Working notes for future sessions, kept by topic under `docs/`. Everything in them was verified in September 2026 on
the tested unit described in `docs/hardware.md`; re-verify anything that depends on a newer Fedora, Fedora kernel,
GRUB or Anaconda release. Only this file is loaded automatically: read the document named below before working on
its area. `docs/guide/` holds the user guides `README.md` links to: they state results and procedures for users and
link the note that holds the evidence. The notes are the source of truth: a new fact goes into its note first, and
a guide says only what concretely works.

## Documents

- `docs/pipeline.md`: what each file of the repository is, the pipeline steps and their caches, the verification
  steps 35, 36, 46 and 60, the version and content-pin rules, the WSL host, shell pitfalls. Read before touching
  `sp11.conf`, `scripts/`, `rpm/` or `payload/`.
- `docs/hardware.md`: the tested unit's identity, the Denali DTB and the SKU regexes, firmware, audio, Wi-Fi, the
  Bluetooth address, the pen, the live-only DSP blacklist, the Windows GRUB entry, the Bluetooth pairings shared
  with Windows. Read before anything that depends on the device.
- `docs/kernel.md`: Fedora's kernel source RPM rebuilt with the SP11 patch set, `kernel.spec`'s local-build slots,
  `KERNEL_SP11_REV`, the configuration, sync state and the CDSP, how the patch set was extracted and how to rebase
  it, kernel install and removal, SELinux. Read before touching steps 10 and 20, `payload/kernel-local`, the kernel
  fork pins (`KERNEL_PATCH_*` in `sp11.conf`) or SELinux.
- `docs/kernel-patches.md`: the patch manifest: the kernel fork's branch, where each commit comes from, what it is
  needed for, what was left out of v23.2.
- `docs/fedora-media.md`: the live media and Fedora's live menu, GRUB, Anaconda's installation order, the
  kernel-install plugin, the live initramfs and root, `kernel-uki-dtbloader`, the dnf repository override, and the
  Fedora 45 differences. Read before touching steps 50 and 60, GRUB, the installer
  path or a Fedora release switch.
- `docs/sensors.md`: the Snapdragon Sensor Core stack (hexagonrpc, libssc, iio-sensor-proxy, sp11-sensors), tablet
  mode and auto-rotation; its dated history is at the end. Read before touching steps 45, 46 and 75,
  `payload/sensors/` or the hexagonrpc fork.
- `docs/verified.md`: what has been confirmed on the device, by date and package version. Read before stating
  that something works; add to it after a device round.
- `docs/guide/*.md`: the user guides (`build`, `install`, `update`, `support-rpm-history`, `bluetooth-pairings`,
  `sensors`, `troubleshooting`, `design`, `new-release`, `layout`, `credits`), linked from `README.md`. Update the
  guide whose procedure or result changes.

## Layout

- `sp11.conf` (versions, URLs, regexes, boot policy, content pins; sourced through `scripts/lib.sh`),
  `scripts/NN-*.sh` (the pipeline steps; "step 50" in the notes means `scripts/50-build-iso.sh`), `rpm/*.spec.in`
  (spec templates).
- `payload/`: payload of the support RPM (`payload/15-sp11-surface.install` is the kernel-install plugin), the
  kernel's `payload/kernel-local`, and `payload/sensors/` (the sensors stack's packaged files and the unpackaged
  posture probe). The kernel patches are commits of the project's kernel fork (GPL-2.0, authors in each commit),
  pinned in `sp11.conf`.
- `docs/`: the working notes; `docs/guide/`: the user guides. `build/` (git-ignored): caches, work trees, RPMs and
  output; see `docs/pipeline.md`.
- `.claude/skills/sp11-kernel-update/`: the update to a new Fedora kernel as a Claude Code skill (`SKILL.md`, every
  command with its expected output in `reference.md`, hand-off templates, the DSP ping tool).

## Rules

- The repo is public under GPL-3.0-or-later (`LICENSE`; the support RPM's `License:` tag must agree). Tracked files
  carry no per-unit identifiers: Bluetooth/Wi-Fi/peripheral addresses, firmware versions, local paths and the
  owner's name stay out of `CLAUDE.md`, `README.md`, `docs/`, `payload/` and `scripts/`. Per-unit values live in
  `build/hardware.env`, `build/bt-pairings/`, `build/sensors/` and, inside the built RPMs,
  `/etc/sp11/bluetooth-address` and the `sp11-sensors` registry. Check before staging:
  `git grep -nE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'` must show only the `AA:BB:CC:DD:EE:FF` placeholders.
- `CLAUDE.local.md` (git-ignored, loaded by Claude Code after this file) holds the owner's private working rules and
  hand-off notes. `.gitattributes` forces LF. `.gitignore` also blocks `hardware.env`, `*.hiv`, `*.iso`, `*.rpm` and
  the pairing tarball anywhere in the tree.

## Version bumps

Rationale and the enforcement (content pins and input hashes since 2026-09-22) in `docs/pipeline.md`.

- Support payload: `VERSION=` in `scripts/30-build-support-rpm.sh`.
- `payload/kernel-local` or `KERNEL_PATCH_COMMIT` (new commits on the kernel fork): `KERNEL_SP11_REV` and
  `KERNEL_SP11_REV_SHA256` in `sp11.conf` (step 20 prints the value to set). A new Fedora kernel:
  `KERNEL_FEDORA_VERSION`, `KERNEL_FEDORA_RELEASE` and its lines in the `KERNEL_SRPM_SHA256` and
  `KERNEL_STOCK_CORE_SHA256` case tables, plus the patch set rebased on a new fork branch
  (`KERNEL_PATCH_BASE_COMMIT`, `KERNEL_PATCH_COMMIT`) under a new revision (`docs/kernel.md`). A pushed fork branch
  is never rewritten.
- In `sp11.conf`: `IPTSD_RPM_RELEASE` (the iptsd spec), `HEXAGONRPC_RPM_RELEASE` (the number, for the spec, its
  payload or the pinned commit), `LIBSSC_RPM_RELEASE` (the libssc spec), `IIO_SENSOR_PROXY_RPM_SUFFIX` (its
  template; `IIO_SENSOR_PROXY_BASE_SPEC_SHA256` for a new SRPM), `SENSORS_VERSION` (`payload/sensors/`, the
  sp11-sensors spec, the registry export).

## Conventions

- Notes by topic, verified facts and lessons only; a compact dated history at the end of a topic, no round logs.
- Lines wrap at 116 columns with code spans kept whole, so phrases stay greppable.
- Keep the index above accurate when a document changes. Here and in the notes, name documents by plain path in
  backticks, never `@path`: Claude Code inlines `@` imports into every session. `README.md` and the guides use
  markdown links instead, so they are clickable on GitHub.

## References

rjindael/fedora-surface-pro-11 (Fedora bring-up notes); ooaklee/linux_ms_dev_kit-sp11 (the kernel tree the patch
set was extracted from) and ooaklee/linux-surface-pro-11-oe (audio, iptsd releases, ADRs); Fedora's kernel dist-git
(src.fedoraproject.org/rpms/kernel, `kernel.spec`) and the Fedora wiki "Building a custom kernel";
ooaklee/lexr.sh `internal/image/fedora/*.go` (remaster design reference);
denisix/ubuntu-surface-pro-11 (`SENSORS.md`: the SSC sensor stack on an SP11 under Ubuntu); linux-msm/hexagonrpc;
DylanVanAssche/libssc (codeberg); Fedora wiki "Snapdragon WoA Laptop Install"; Arch wiki "Bluetooth" (dual-boot
pairing).
