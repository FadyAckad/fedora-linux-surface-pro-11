# CLAUDE.md — Fedora live ISO for Surface Pro 11 (5G, X1E80100, OLED)

Working notes for future sessions, kept by topic under `docs/` and indexed in `docs/README.md`: read that index
first, then the note it names for the area being worked on. Everything in the notes was verified on the tested
unit described in `docs/hardware.md`; re-verify anything that depends on a newer Fedora, Fedora kernel, GRUB or
Anaconda release. The guides under `docs/guide/` are for users: they state results and procedures and link the
note that holds the evidence. The notes are the source of truth: a new fact goes into its note first, and a guide
says only what concretely works. Update the guide whose procedure or result changes.

## Layout

- `sp11.conf` (versions, URLs, regexes, boot policy, content pins; sourced through `scripts/lib.sh`),
  `scripts/NN-*.sh` (the pipeline steps; "step 50" in the notes means `scripts/50-build-iso.sh`), `rpm/*.spec.in`
  (spec templates).
- `payload/`: payload of the support RPM (`payload/15-sp11-surface.install` is the kernel-install plugin), the
  kernel's `payload/kernel-local`, `payload/sensors/` (the sensors stack's packaged files, the libssc and
  iio-sensor-proxy patches and the unpackaged posture probe) and `payload/camera/` (the unpackaged raw-capture
  probe). The kernel patches are commits of the project's kernel fork (GPL-2.0, authors in each commit), pinned in
  `sp11.conf`.
- `docs/`: the working notes, indexed in `docs/README.md`; `docs/guide/`: the user guides. `build/` (git-ignored):
  caches, work trees, RPMs and output; see `docs/pipeline.md`.
- `.claude/skills/sp11-kernel-update/`: the update to a new Fedora kernel as a Claude Code skill (`SKILL.md`, every
  command with its expected output in `reference.md`, hand-off templates, the DSP ping tool).
- `.claude/skills/sp11-handoff/`: the standard for hand-offs to the maintainer (folder, `README.txt`, steps file,
  validation, the way back, device sessions and their review) as a Claude Code skill.
- `.claude/skills/sp11-docs/`: the documentation standard (the reader tiers, the writing rules, what to update
  after a device round) and `validate.py`, the checks to run before handing documentation over.

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
  (`KERNEL_PATCH_BASE_COMMIT`, `KERNEL_PATCH_COMMIT`) under revision 1: the revision restarts with every Fedora
  kernel version (`docs/kernel.md`). A pushed fork branch is never rewritten.
- In `sp11.conf`: `IPTSD_RPM_RELEASE` (the iptsd spec), `HEXAGONRPC_RPM_RELEASE` (the number, for the spec, its
  payload or the pinned commit), `LIBSSC_RPM_RELEASE` (the libssc spec or its patches in `payload/sensors/libssc/`),
  `IIO_SENSOR_PROXY_RPM_SUFFIX` (its template or its patches in `payload/sensors/iio-sensor-proxy/`; for a new SRPM
  its pin `IIO_SENSOR_PROXY_SRPM` with URL and checksum, and `IIO_SENSOR_PROXY_BASE_SPEC_SHA256`),
  `SENSORS_VERSION` (`payload/sensors/`, the sp11-sensors spec, the registry export).
- The spec templates are part of the RPM input hashes: a comment change there needs the release bump too.

## Conventions

- The notes' conventions (what a note holds, the 116-column wrap, plain backticked paths in the notes and markdown
  links in the guides, the section names other files cite) are in `docs/README.md`; keep its index accurate when
  a document changes. Never `@path` imports: Claude Code inlines them into every session.

## References

- rjindael/fedora-surface-pro-11 (Fedora bring-up notes); ooaklee/linux_ms_dev_kit-sp11 (the kernel tree the
  patch set was extracted from) and ooaklee/linux-surface-pro-11-oe (audio, iptsd releases, ADRs).
- Fedora's kernel dist-git (src.fedoraproject.org/rpms/kernel, `kernel.spec`) and the Fedora wiki "Building a
  custom kernel"; the Fedora wiki "Snapdragon WoA Laptop Install"; ooaklee/lexr.sh `internal/image/fedora/*.go`
  (remaster design reference).
- denisix/ubuntu-surface-pro-11 (`SENSORS.md`: the SSC sensor stack on an SP11 under Ubuntu); linux-msm/hexagonrpc;
  DylanVanAssche/libssc (codeberg); Arch wiki "Bluetooth" (dual-boot pairing).
- lkarlslund/linux-x1e-jglathe and its kernel branches lkarlslund/linux-x1e-t14s (ThinkPad T14s; the battery-driver
  fixes of 7.2.11 revision 2), X1E sleep work from justririll/x1e-sleep and ramonjesusmiranda-debug/sp11-el2.
