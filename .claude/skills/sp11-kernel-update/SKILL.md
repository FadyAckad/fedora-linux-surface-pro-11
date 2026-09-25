---
name: sp11-kernel-update
description: Move the Surface Pro 11 kernel to a newer Fedora kernel release. Pins Fedora's source RPM and stock kernel-core, rebases the SP11 patch set of the kernel fork onto the new stable tag in a scratch clone, reviews and compile-checks the result, builds and verifies the next KERNEL_SP11_REV, hands it over for a device test, and re-pins the fork branch the maintainer pushes.
when_to_use: The maintainer asks to update the SP11 kernel to a newer Fedora kernel ("Fedora's kernel is at 7.2.8, update the SP11 kernel", "rebase the patch set onto 7.2.9"), or asks whether an intermediate stable version is needed first.
argument-hint: "[new Fedora kernel version, e.g. 7.2.8]"
---

# Update the SP11 kernel to a new Fedora kernel

Target version: $ARGUMENTS (none given: the newest `stable` Fedora kernel for `FEDORA_RELEASE`).

The result is the next SP11 kernel revision: Fedora's kernel source RPM of the new version, rebuilt with the SP11
patch set rebased onto the matching stable tag (branch `sp11/<new>` of the kernel fork) and `payload/kernel-local`.
Background and lessons: `docs/kernel.md` (Revisions; Rebase to a new Fedora kernel), the patch manifest
`docs/kernel-patches.md`, pins and caches in `docs/pipeline.md`. Every command of the steps below, with its
expected output: [reference.md](reference.md). Hand-off templates: [handoff.md](handoff.md).

## Rules

- Never commit, push or create a branch, in this repository or in the kernel fork. Rehearse the rebase in a scratch
  clone on a detached HEAD; the maintainer creates `sp11/<new>` from the series (`git am`, signed), pushes it and
  commits this repository. Commits prepared for the maintainer carry no `Co-Authored-By` trailer.
- Rebase straight from the pinned base to the new stable tag. A stable tag contains every earlier one of its series
  and Fedora's source RPM of a version is complete on its own, so an intermediate version brings the same conflicts
  plus a kernel nobody runs; build one only to bisect a regression the device test finds.
- A revision reaches the device only through a device test. `README.md`, `docs/guide/design.md`, the ISO name in
  `docs/guide/build.md` and `docs/verified.md` change after the test passed. The ISO is rebuilt only on request.
- Tracked files carry no per-unit identifiers or local paths (`CLAUDE.md`, Rules). The hand-off location and the
  maintainer's private working rules are in `CLAUDE.local.md`.

## 1. Target and inputs

1. Bodhi lists Fedora's kernel updates for `FEDORA_RELEASE`: take the version and release of the newest `stable`
   one, unless the maintainer named a version.
2. The stable tags of the pinned and the new version: the fork clone's must equal kernel.org's.
3. Download Fedora's source RPM and stock `kernel-core` from Koji into `build/cache/` (in a worktree, set up
   `build/` first, section 4), check them against Fedora's signed copies, and record the sha256 of the files the
   pipeline downloads.
4. Compare the old and new source RPMs: `kernel.spec` still has the local-build slots step 20 relies on, Fedora's
   `patch-<x.y>-redhat.patch` touches none of the patch set's files, and Fedora's configuration changes (the
   stock `kernel-core` configurations) touch no symbol `kernel-local` sets.
5. Fedora's `linux-<new>.tar.xz` must be the new tag's tree (`docs/kernel.md` records this per version).

## 2. Rebase rehearsal

1. Scratch clone of the maintainer's fork clone under the checkout's git-ignored `build/rebase/` (not `/tmp`, a
   6 GB tmpfs), with the fork commits' identity, signing off, detached at `KERNEL_PATCH_COMMIT`.
2. Survey first: the files the series touches, every stable commit of `v<old>..v<new>` that touches them and the
   release that brought it, and which SP11 patch each one meets.
3. `git rebase --empty=drop --onto v<new> v<old>`; commits whose content is upstream drop out by themselves.
4. A conflict: keep the SP11 behaviour in upstream's new form, `git add`, then `git rebase --continue`, which keeps
   the original author (a plain `git commit` records the current user as the author). Afterwards give every
   adapted commit an `[sp11: ...]` note after its trailers (amend on a detached checkout, re-stack the rest), and
   compare authors, dates and subjects with the old branch: only dropped and new commits may differ.
5. `git range-diff` of the two branches: review every changed pair; a patch listed as removed and added changed
   shape (partly upstream now).
6. A clean textual merge is not a correct one. Read every stable commit that touches an SP11 file next to the SP11
   code it meets: a removed label or function still referenced (7.2.6's `spi_geni_init()` lost `out_pm`), a changed
   check an SP11 path depends on (7.2.6's SoundWire `pn >= maxport` refused the CPS feedback port 13), new guards,
   runtime-PM or locking patterns. Then scan the stable changes of the subsystems the SP11 relies on (list in
   reference.md) for behaviour changes and note what the device test has to cover.
7. A needed fix is a new commit at the end of the series: the maintainer as author, as with the POS switch; a
   kernel-style message (75 columns, `Fixes:`); `scripts/checkpatch.pl --strict` clean but for the missing
   `Signed-off-by`, which is the maintainer's to add.

## 3. Host compile check

Before the hour-long mock build: Fedora's new stock configuration plus `kernel-local` through `olddefconfig` (every
`kernel-local` line must survive), then every directory the series touches and all arm64 device trees, from clean
objects. No error, no warning; about two minutes on the 12-core WSL host.

## 4. Pins and build directory

1. `sp11.conf`: `KERNEL_FEDORA_VERSION`, `KERNEL_FEDORA_RELEASE`, a line in the `KERNEL_SRPM_SHA256` case table
   (and its `known:` list) and one in `KERNEL_STOCK_CORE_SHA256`'s, `KERNEL_PATCH_BASE_COMMIT` (the tag's commit),
   `KERNEL_PATCH_COMMIT` (the rehearsal head for now, `# sp11/<new>, <n> commits`), `KERNEL_SP11_REV` plus one, and
   `KERNEL_SP11_REV_SHA256` as `kernel_rev_sha256` prints it.
2. In a worktree `build/` starts empty: hard-link the main checkout's caches, copy its git pins, link the support
   RPM and hard-link its live root (`sudo cp -al`) for step 36. The kernel's mock root is shared by all checkouts:
   no other kernel build may run.

## 5. Build and verify

1. Step 10 from the rehearsal clone: `KERNEL_PATCH_REPO=<clone> scripts/10-fetch-sources.sh`.
2. Step 20 detached (`setsid nohup`, 60 to 80 minutes); wait for its completion marker or the end of its process,
   not for error-looking lines in mock's `build.log`. Its checks on the packages must pass.
3. Step 36, with `SUPPORT_PREVIOUS_RPM` set to the current support RPM: the packages install next to the previous
   kernel in an overlay of the live root, the boot entry and default are right, and removing them brings the
   previous kernel back. Without that variable, when the live root already carries the current support RPM (after
   any ISO build), the menu check fails: the live root's menu is Fedora's own, and `20-grub.install`'s sync of
   `/etc/default/grub` never runs, because the SP11 plugin rewrites `/etc/kernel/cmdline` before it.
4. Beyond step 20: the source RPM's `linux-kernel-test.patch` holds the adapted and new code, the shipped modules
   carry the SP11 strings, the module list differs from the previous revision's only as Fedora's configuration
   explains.

## 6. Documents now

- `docs/kernel.md`: the revision in Sources and packages, the tarball fact and the size of Fedora's own patch for
  the version, what this rebase met in the rebase section, a History line.
- `docs/kernel-patches.md`: a paragraph for the revision (dropped, adapted and new patches, old-to-new numbers),
  the host proof paragraph, the renumbered Contents table. Patch numbers are cited in `docs/kernel.md`,
  `docs/hardware.md` and `docs/sensors.md` as well.
- `docs/guide/new-release.md`: the default revision.
- Any other note whose facts the update changed; a new fact goes into its note first (`CLAUDE.md`, Conventions).
- Lines of at most 116 columns with code spans whole; the MAC grep of `CLAUDE.md` before handing over.

## 7. Hand-off

A folder as `CLAUDE.local.md` describes: the five `KERNEL_PKGS` RPMs with a `.sha256` each, the device steps, the
fork steps, the series as a tarball, [sp11-dsp-ping.py](sp11-dsp-ping.py), `README.txt`. Templates, and what each
device check covers, in [handoff.md](handoff.md). Expected log lines come from the previous device round (the
maintainer's returned `sp11-diag` output), not from reading the code.

## 8. After the device test and the push

1. The maintainer pushes `sp11/<new>` and sends its head; its tree must be the tested one, every commit signed, and
   authors, dates and messages those of the tested series.
2. Pin that head in `KERNEL_PATCH_COMMIT`, set `KERNEL_SP11_REV_SHA256` to the value `kernel_rev_sha256` prints and
   keep the revision number; step 10 (now from GitHub) and step 20 (accepts the cached packages, reruns its checks).
3. `README.md`, `docs/guide/design.md`, `docs/guide/build.md` and `docs/verified.md` from the device results.
4. Ask whether the ISO should get the new kernel.
5. One commit message for the maintainer: an imperative subject of at most about 65 characters, one to three
   sentences; first check that the change set still applies onto the main checkout, which may have moved.

## Pitfalls

- `git commit` in the middle of a conflicted rebase makes the current user the author of the rebased commit.
- A partial clone fetches a missing object with its whole history on first use: lookups there run with
  `GIT_NO_LAZY_FETCH=1` (`docs/pipeline.md`, Shell pitfalls).
- A local clone as `KERNEL_PATCH_REPO` ignores the blob filter: the cache takes about 280 MB instead of 5 MB.
- `pkill -f PATTERN` also kills the shell whose command line contains PATTERN: stop processes by PID.
- `git hash-object --stdin-paths` inside `build/` resolves paths against this repository: compare the tarball with
  `git archive` and `diff -r` instead.
- Koji's `packages/` files are unsigned; the signed copies are under `data/signed/<key id>/`. rpm 6 keeps keys in a
  keystore, so `rpm --dbpath <dir> --import` followed by `-K` reports `NOKEY`: use `rpmkeys --root <dir>`.
- An interrupted compile check leaves objects whose warnings the next log lacks: delete the touched directories'
  objects and run it again.
- mock's `build.log` stays quiet while the kernel compiles, and bpftool's `-Wformat-security` probe prints an
  `error:` line that is not a failure.
- `rpm2cpio` names every file `./...`: `cpio` extracts nothing, silently, for a pattern without the `./`.
- A command piped into `tee` or `tail` reports their status, not its own: check `rc` before the pipe.
