---
name: sp11-handoff
description: The standard for a hand-off to the SP11 maintainer for a device round. The folder and its name, README.txt, the steps file's format, checksums, packing scripts, validation before handing over, a way back for every change, what comes back. Also the rules for a Claude session on the installed Fedora system that prepares commands for the maintainer, and for reviewing such a session's hand-off.
when_to_use: Before handing RPMs, an ISO, a kernel, scripts or a test kit to the maintainer to run on the Surface; when reviewing or refining a hand-off another session prepared (a device session's findings, kit and steps); when a session on the device writes commands for the maintainer to run.
---

# Hand-offs to the maintainer

The maintainer carries every hand-off folder from Windows to the Surface's Fedora on a USB stick, runs its steps
file there and sends the output back. The folders' location and the maintainer's private rules are in
`CLAUDE.local.md`; tracked files name no local paths. The kernel update adds its own templates on top of this
standard (`.claude/skills/sp11-kernel-update/handoff.md`).

## Rules

- Nothing changes the device without the maintainer: a session never installs or runs a command that changes the
  system there; it hands such commands over. A session on the device may run read-only diagnostics itself.
- Every step that changes the system says so and gives its way back: a rollback command, an uninstall, the fallback
  kernel left installed. A script that changes the system ships with its own undo.
- Validate before handing over, on the host:
  - RPMs through the pipeline's verification steps: 35 for the support RPM (both install paths), 36 for a kernel,
    46 for the sensors stack.
  - Scripts through a smoke test in a sandbox: a fake root, stub commands, no write outside it, a refusal when run
    as a user or in test mode without a sandbox. New cases must fail on the old version.
  - Every command of the steps file that can run on the host, on the same input, with its patterns checked against
    real output. Run grep checks through `bash -c` with GNU grep: the tool shell's `grep` is ugrep.
  - The folder's own first steps (checksums, unpacking, the kit's tests) on a copy, as written.
- Expected output comes from a previous round's returned output or from running the command on the same input,
  never from reading the code: a line the code prints only under some condition may never appear on the device.
- Fix only what happens or can happen on this device; list the rest without a change.
- A hand-off folder may hold this unit's data (logs, `sp11-diag` output). Anything meant to go beyond the
  maintainer, such as a kit for an issue's reporter, is a separate archive without it, and the steps file says
  which.

## The folder

- Name: `sp11-<topic>[-<version>]-<date>`, the date of the hand-off. List the location before writing: other
  sessions rename folders there. The same folder under `build/handoff/` is the record; the maintainer's returned
  output goes to `build/handoff/<folder>-results/`.
- Deliverables (RPMs, an ISO, a tarball), each with a `.sha256` written in its folder
  (`sha256sum <file> > <file>.sha256`), so that `sha256sum -c *.sha256` works there.
- Scripts lose their exec bits on the way (the Windows copy, the USB stick). A single helper runs through its
  interpreter (`python3 ./tool`, `bash ./tool.sh`); a kit of several scripts, test stubs included, goes as a
  `.tar.gz` packed with `--owner=0 --group=0 --numeric-owner` and is unpacked by the steps.
- `<topic>-steps.md` and `README.txt`; for an investigation also `<topic>-findings.md`.
- Text files LF (`grep -c $'\r'` reads 0), lines of at most 116 columns with commands kept whole; the MAC grep of
  `CLAUDE.md` finds only placeholders in anything shareable.
- After copying it to the location, `sha256sum -c *.sha256` in the copy.

## README.txt

First line `Surface Pro 11: <topic>, <date>`, then three to five lines: what it is and what changed against what
the device runs, what the round must watch, the fallback. A last line `Order: ...` names the steps files in the
order to run them (the device first, then any WSL steps such as the fork's).

## The steps file

- Title `# Surface Pro 11: <topic> (<date>)`.
- Intro paragraphs: what it is and what changed; `Verified off-hardware: ...`, with what the host ran and its
  counts; `Unverified: ...`; `What can break: ...`; `The way back: ...`, naming the step or part that undoes it.
- `## Part X: <name>` headings when the round has phases or moves between Fedora and Windows; the steps are
  numbered 1 to N across all parts, in the order to run them.
- Each command in its own fenced block, `bash` on Fedora and `powershell` in Windows: no prompt, no comment after
  the command, nothing to fill in unless the step gives an example value and says what to replace.
- After each step's commands, `Expected: ...` with the concrete lines; checks without a command as `By hand: ...`.
  When the expected line is missing, the step says what to do (send the output, stop, go on).
- A step that changes the system says so in its heading or first line, with its way back.
- The last line: `Send back: ...`, naming the outputs and files.

## Pitfalls on the device

- A glob under a root-only directory expands in the user's shell before sudo: write
  `sudo sh -c 'grep ... /boot/loader/entries/*.conf'`.
- A script installed outside the package paths is called by its absolute path (`sudo /usr/local/sbin/<tool>`):
  sudo's `secure_path` decides what a bare name finds.
- `amixer -c N` opens the UCM's remapped controls: use `amixer -D hw:<card>`.
- `systemd-run --unit=NAME` fails while a failed unit of that name is loaded: add `--collect`.
- Every boot starts with the clock 2 h early until NTP corrects it, so a boot without network keeps early times
  (2026-10-20): order boots by the journal's index (`journalctl --list-boots -o json`), and take a boot's start from
  the kernel's `setting system clock to` line.
- A command piped into `tail` or `grep` reports their status, not its own.
- The maintainer's shell on the device is zsh (2026-10-22): a pipeline that `timeout` ends prints zsh's job lines
  (`[1]    <pid> exit 124    timeout ...` and `<pid> terminated  tee ...`), not bash's `Terminated`; the WSL
  host's tool shell is bash, so take such expected lines from a device round.

## Device sessions

A Claude session on the installed Fedora system reads the journal and sysfs but cannot build, and has root only
through the maintainer. It runs read-only diagnostics itself and hands everything else over under the rules above.
Its results come to the WSL session as a folder in this standard: `<topic>-findings.md` (the symptom with its log
evidence, what is ruled out, the hypotheses, what was built, the open items), its logs in `logs/` with a `README.md`
saying how each was produced and that they are private, and a kit and steps file if it wrote them.

Reviewing such a folder on the WSL host:

1. Copy it into the checkout first, as a verbatim record under `build/handoff/`. Files in the hand-off location
   can carry mode 0000 for the WSL user: read any it refuses through Windows (`cmd.exe /c type`).
2. Check every conclusion against the logs, the boot order and the before and after of each boot in particular.
3. Run the kit's tests, then fix what the review found, with new test cases that fail on the old version.
4. Bring the steps file to this standard; build work (a kernel, RPMs) leaves the maintainer's steps and becomes the
   WSL session's own hand-off.
5. Record the corrections at the top of the findings file, so the device session's next round starts from them.
