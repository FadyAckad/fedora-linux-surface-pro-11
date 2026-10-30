---
name: sp11-docs
description: The documentation standard of the Surface Pro 11 Fedora ISO repository. The three reader tiers (README, guides, notes), what each holds, the writing rules for notes and guides, the conventions other files depend on, what to update after a device round, how to split or cut, and the validator to run before handing over.
when_to_use: Before writing or editing README.md, CLAUDE.md, docs/README.md, a note under docs/ or a guide under docs/guide/; after a device round, a version bump or a new feature that the docs must record; when asked to clean up, shorten, split or restructure the docs.
---

# The SP11 documentation standard

Set by the maintainer across the cleanups of 2026-09-22, 2026-09-25, 2026-10-08 and 2026-10-30. The goal: a
person who opens the repository with no knowledge finds their way in and understands what it does, and a
maintainer or a session finds every verified fact where the index says it is. Validate with
[validate.py](validate.py) before handing over.

## Tiers, by reader

| Tier | Files | Reader | Holds |
|---|---|---|---|
| Front door | `README.md` | anyone | what it is, for whom, "you build it yourself", current versions, the feature table, quick start, reporting results, the documentation list by intent |
| Guides | `docs/guide/*.md` | users and builders | procedures, results, design decisions; each guide stands on its own |
| Notes | `docs/*.md` | maintainers and sessions | verified facts, measurements, lessons, known issues, a dated history; indexed by `docs/README.md` |

`CLAUDE.md` holds only the rules, the layout and the version-bump list and says to read `docs/README.md` first:
one index, shared by humans and sessions. The notes are the source of truth: a new fact goes into its note first,
and a guide states only what a note holds the evidence for.

## What goes where

- A measurement, a mechanism, a pitfall, a pin, a decision's evidence: the topic note.
- A procedure, a command, an expected output, a warning, a setting: the guide; `design.md` is the one guide that
  carries reasons.
- The current state (versions, what works): `README.md`; the device results by date: `docs/verified.md`.
- Why the build does something: `docs/guide/design.md`, linking the note with the mechanism.
- Words a newcomer does not know: the glossary in `docs/guide/overview.md`.
- A topic that outgrows its note (a section with its own history, cited by other files): its own note, indexed in
  `docs/README.md` and `README.md`, with every citation moved (2026-10-30: `sleep`, `tablet-mode`, `gnss`,
  `guide/build-rpms`).

## Writing the notes

- One `#` title, a one-paragraph scope line under it naming the sibling notes, `##` topics, `###` subtopics;
  bullets of at most six lines, one idea per sentence; numbered steps for procedures; small tables for
  comparisons.
- Keep: the current state, rules and pins, lessons and pitfalls (one or two sentences each), the measurements that
  establish a fact (with date and revision), known issues with their status, and a `## History` of one line per
  date at the end.
- Cut: discovery narratives, verification bookkeeping ("proven on the host", item-by-item check lists),
  superseded states, intermediate experiments once the mechanism and the fix are stated, per-round references,
  speculation and hedges. Git history is the archive; there is no archive folder. A fixed issue keeps one entry
  with the fixing release under the note's Known issues.
- Facts only from the device, the host or the sources; a fact from memory or another repository is not a fact of
  this note. Name what was measured, when, on which revision.
- `docs/verified.md` is a log: one entry per round with the packages installed, what was checked and the result;
  from 7.2.11 revision 1 on the entries cite "the standard checks" defined at its top. Rounds older than the
  current kernel series are one entry each under "Earlier rounds".

## Writing the guides

- Keep every procedure, command, expected output, warning and link; lose internals and rationale. Commands in
  fenced `bash` blocks, one per block, so each can be copied on its own.
- Markdown links to the notes, as in [`docs/hardware.md`](../../../docs/hardware.md), with the section named
  after the link when one applies ("`docs/hardware.md`, USB-C data").
- Current limitations and fixed-in-an-earlier-release are separate sections in `troubleshooting.md`; material
  that applies only to installations nobody new can have leaves the guides (the changelog keeps its lines).
- The versions a guide names (the kernel revision, the support RPM, the ISO name) match `sp11.conf` and step 30
  at the time of writing.

## README.md

- Opens in plain words: what it is, for whom, that there is no ISO to download and why, what you get.
- A current-versions table from `sp11.conf` and step 30; a feature table whose rows are only those the owner
  confirmed in use (a new capability shown by a tool goes into a note below the table, not into a row).
- The documentation list by intent: start here, building, background, then one line for the notes.
- Everything in it concretely works; nothing in it is a plan.

## Conventions every file follows

- Lines wrap at 116 columns with code spans kept whole, so phrases stay greppable; table rows are the exception.
- The notes and `CLAUDE.md` name documents by plain path in backticks, never `@path` (Claude Code would inline
  them); `README.md` and the guides use markdown links, clickable on GitHub.
- Tracked files carry no per-unit identifiers: no Bluetooth, Wi-Fi or peripheral addresses, firmware versions,
  local paths or the owner's name (`CLAUDE.md`, Rules; the validator runs the MAC grep).
- Section names other files cite stay as they are, or every citation moves. Cited today: `docs/hardware.md`
  (USB-C data, Video codec, Wi-Fi, Audio), `docs/sensors.md` (Known issues, Compass), `docs/kernel.md` (Sync
  state, SELinux, Rebase), `docs/fedora-media.md` (Anaconda), `docs/modem.md` (Mobile data, Across a sleep).
- Every note is listed in `docs/README.md` with a "read before" line; every guide is linked from `README.md`.

## Constraints outside docs/

- `rpm/libssc.spec.in` and `rpm/iio-sensor-proxy.spec.in` cite "docs/sensors.md, Known issues" in comments, and
  the spec templates are part of the RPM input hashes: a comment edit there forces a release bump, so that
  section name is fixed.
- `scripts/50-build-iso.sh`, `scripts/60-verify-rootfs.sh`, `scripts/30-build-support-rpm.sh`,
  `scripts/36-verify-kernel-install.sh`, `payload/sp11-diag` and `sp11.conf` cite notes by path, some with a
  section ("docs/fedora-media.md, Anaconda"); the validator checks them.
- The kernel-update skill (`.claude/skills/sp11-kernel-update/SKILL.md`, section 6 and 8) lists the documents a
  kernel update touches; keep that list true when documents move.

## After a device round, a version bump or a new feature

1. `docs/verified.md`: one entry (packages, what was checked, the result), citing the standard checks.
2. The topic note: the facts the round established, into the topic's bullets, and one History line.
3. `README.md`: the versions table and, for a row the owner confirmed in use, the feature table; the ISO name
   examples in `README.md` and `docs/guide/build.md`.
4. `docs/guide/design.md` (the patch count and revision), `docs/guide/new-release.md` (the default revision),
   `docs/guide/support-rpm-history.md` (a line per support RPM version), `docs/guide/troubleshooting.md` (a
   limitation that appeared or a fix that landed).
5. `docs/README.md` and `README.md`'s list, when a document's scope changed or a document was added.
6. `python3 .claude/skills/sp11-docs/validate.py` from the repository root; it must print no finding.

## Splitting and cutting

- Split by reader or by topic, never by age: a section that has its own history, its own citations and a reader
  who needs only it becomes a note; the old section's citations move with it (the validator finds the stale
  ones).
- Before a cut, check what cites the section (scripts, spec templates, skills, other notes) and whether the cut
  text is the only place a fact lives; a fact that lives nowhere else moves into a topic bullet before the cut.
- Count words before and after and say so in the hand-over; a cleanup that removes no words removed no ramble.

## Pitfalls

- `grep` in the Claude Code tool shell is ugrep; reproduce a check with `bash -c` or python when the result looks
  odd.
- A heredoc with an unquoted delimiter expands `$` and backticks; write docs with `<<'EOF'`.
- The 116-column awk check must skip fenced code and table rows, or it flags every command and table.
- The in-file references "(Known issues)", "(Runtime design)", "(Compass)" are section names of the same note;
  renaming a section breaks them silently, so grep for the old name across `docs/` after a rename.
