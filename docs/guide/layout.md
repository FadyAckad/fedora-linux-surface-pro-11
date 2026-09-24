# Layout

What each file and directory of the repository is. The build tree's caches and outputs are described in
[`docs/pipeline.md`](../pipeline.md).

- `sp11.conf`: versions (the support RPM's is `VERSION=` in `scripts/30-build-support-rpm.sh`), URLs, regexes,
  boot policy and the content pins.
- `scripts/`: numbered pipeline steps, `lib.sh` (helpers), `build-all.sh`, the pairing export (`70`), and the
  sensors stack: `45`/`46` build and verify its RPMs inside `build-all.sh`, `75` exports this unit's registry from
  Windows, once, outside the pipeline.
- `rpm/`: spec templates for `sp11-surface-support`, `sp11-iptsd`, and for the sensors stack (`hexagonrpc`,
  `libssc`, `iio-sensor-proxy`, `sp11-sensors`); the kernel uses Fedora's own `kernel.spec`.
- `payload/`: payload of the support RPM, the kernel's configuration additions (`payload/kernel-local`), the README
  inside the ISO, and `payload/sensors/` (the files and helper scripts of `sp11-sensors`, hexagonrpc's sysusers
  entry and udev rule, and `sp11-sam-posture`, an unpackaged probe of the Surface Aggregator's cover and posture
  state).
- `images/`: the README's screenshot.
- `LICENSE`: GPL-3.0-or-later for the repository's content (see [`docs/guide/credits.md`](credits.md)).
- `CLAUDE.md`: entry point of the working notes (the index of `docs/`, rules for every session, references).
- `docs/`: the working notes by topic (`pipeline.md`, `hardware.md`, `kernel.md`, `kernel-patches.md`,
  `fedora-media.md`, `sensors.md`, `verified.md`): verified facts about the hardware, the Fedora media and the
  pipeline, its pitfalls, and what has been confirmed on the device, by date. `docs/guide/`: the user guides the
  README links to.
- `.gitattributes`: LF line endings for every file; the payload scripts break with CRLF.
- `build/`: caches, work trees, RPMs and output ISOs (git-ignored). `build/hardware.env`,
  `build/bt-pairings/` and `build/sensors/` hold your unit's identity, pairing keys and sensor calibration;
  keep them private.
