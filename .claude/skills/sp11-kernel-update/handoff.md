# Kernel update: hand-off

The folder (location and naming in `CLAUDE.local.md`) holds the five `KERNEL_PKGS` RPMs of the new uname with a
`.sha256` each (`sha256sum <rpm> > <rpm>.sha256`), `sp11-dsp-ping.py` from this skill's directory, the series as
`sp11-<new>-series.tar.gz` (`git format-patch --no-signature v<new>..<head>`, packed without a directory), and the
three files below. Before handing over, apply the tarball with `git am` onto `v<new>` in a throwaway clone
(`git clone --shared --no-checkout linux-sp11`, detached at the tag's commit, signing off): 58 commits and one
whitespace warning for 7.2.7 (74 commits since revision 9, 88 at 7.3.3), and the rehearsal's tree.

The folder, `README.txt` and the steps files follow the hand-off standard
([sp11-handoff](../sp11-handoff/SKILL.md)): a `#` title with topic, version and date; an intro (what changed, what
was verified off-hardware, what can break, the way back); numbered steps with one command per fenced `bash` block
and an `Expected:` after it; a closing line naming what to send back. The kernel's own conventions follow. Commands
are the ones earlier rounds ran on the device; expected lines come from the previous round's returned output (its
`sp11-diag` file has the kernel log), because a line the code prints under some condition may never appear on the
device. Placeholders: `<abi>` the new uname (`7.2.7-300.sp11.5.fc45.aarch64`), `<prev-abi>` the installed
revision's, `<new>`, `<rev>`, `<date>`, `<tree>`, `<n>` the series' commit count, `<folder>` the hand-off folder's
Windows path in WSL.

## `sp11-<new>-rev<rev>-steps.md` (on Fedora)

Cover, in this order, and keep the commands exactly as below:

1. `sha256sum -c *.sha256` — every file `OK`.
2. `df -h /boot` — at least 250M in `Avail` (each SP11 kernel takes about 195 MB there); otherwise stop.
3. `sudo dnf install ./kernel{,-core,-modules-core,-modules,-modules-extra}-<abi>.rpm` — five packages next to
   `<prev-abi>`, dracut runs, no error line.
4. `sudo sh -c 'grep -hE "^(title|devicetree|options)" /boot/loader/entries/*-<abi>.conf'` and
   `sudo grub2-editenv list` — `devicetree /dtb-<abi>/qcom/x1e80100-microsoft-denali-oled-5g.dtb` on the 5G SKU
   (`x1e80100-microsoft-denali-oled.dtb` on the others), the SP11 arguments (possibly followed by `$tuned_params`),
   `saved_entry` ending in `<abi>`.
5. After a reboot and 3 minutes: `uname -r`, `cat /proc/cmdline`, `getenforce` — `<abi>`, the SP11 arguments,
   `Enforcing`.
6. Speakers, with Bluetooth audio disconnected:
   `pw-play /usr/share/sounds/freedesktop/stereo/audio-channel-front-left.oga`, the same with `front-right`, then
   `sudo journalctl -k -b --no-pager | grep -E 'VI\+CPS feedback|feedback incomplete|All ports busy'` — the voice
   from the matching speaker; `SP11 stage SP/SPVI enabled with VI+CPS feedback accepted` lines (one each time
   playback starts); no `feedback incomplete`, no `All ports busy`.
7. Microphone: `pw-record /tmp/mic-test.wav` (speak five seconds, Ctrl+C), `pw-play /tmp/mic-test.wav`.
8. Touch and pen: `sudo journalctl -k -b --no-pager | grep 'SP11: '` — among others
   `SP11: accepting protocol 9 as QSPI controller` and `SP11: QSPI using GPI DMA descriptor mode`; by hand: touch,
   two-finger scrolling, pen inking.
9. DSPs: `ls -l /dev/fastrpc-*`, `sudo timeout 20 python3 ./sp11-dsp-ping.py 10 1` and `... 5 1` —
   `/dev/fastrpc-adsp` and `/dev/fastrpc-cdsp`; both `answered`.
10. Crypto engine (disabled since 7.3.3 revision 1): `cat /proc/device-tree/soc@0/crypto@1dfa000/status; echo;
    grep -c -- '-qce' /proc/crypto` — `disabled`, `0`. (Up to 7.2.15: `grep -E '^driver +: .*-qce$' /proc/crypto`
    listed `sha256-qce` and `hmac-sha256-qce`, nothing with `aes`, and the kernel log had no
    `self-tests ... failed`.)
11. Cameras, as your user with no application using a camera (`cam` from `libcamera-tools`): `cam -l`, then
    `F=$(cam -l 2>/dev/null | sed -n 's/^\([0-9]*\): .*camera@1a)$/\1/p'); echo "front=$F"`,
    `cam -c "$F" -C300 >/dev/null 2>&1 & sleep 4; cat /sys/class/leds/white:camera-indicator/brightness; wait` and
    `cat /sys/class/leds/white:camera-indicator/brightness` — `Internal front camera`, `Internal back camera` and
    `'vd55g0'`; a number; `1` while the capture runs, with the light next to the front camera on, and `0` after it.
    By hand: the front and the rear camera in GNOME Snapshot.
12. By hand: Wi-Fi, the Bluetooth keyboard and pen, battery, brightness, volume keys, keyboard and touchpad,
    rotation with the keyboard folded back, power modes; optional: an external display on USB-C.
13. Suspend from the Power menu, one minute, wake: display, touch, pen, keyboard, Wi-Fi, sound and both cameras in
    GNOME Snapshot as before.
14. `sudo /usr/libexec/sp11/sp11-diag ./sp11-diag-<new>-sp11.<rev>.txt` and
    `grep -A2 'state_synced' ./sp11-diag-<new>-sp11.<rev>.txt` — the file written; `no provider waits for
    sync_state`.
15. Second boot, 3 minutes: `ls -l /dev/fastrpc-cdsp`, `sudo timeout 20 python3 ./sp11-dsp-ping.py 10 1` —
    the node; `answered`.
16. Only if the revision misbehaves: boot `<prev-abi>` from the GRUB menu, then
    `sudo dnf remove kernel{,-core,-modules-core,-modules,-modules-extra}-<abi>`,
    `sudo grubby --set-default /boot/vmlinuz-<prev-abi>` and `sudo grubby --default-kernel` — five packages
    removed; `/boot/vmlinuz-<prev-abi>`.

Add a check for every patch the rebase adapted or added (for 7.2.7, step 6 covers the SoundWire fix and step 8 the
adapted SPI patch). Send back: the terminal output of the steps, `sp11-diag-<new>-sp11.<rev>.txt`, one line per
by-hand check. Compare its `recent journal errors` section with the previous round's.

## `sp11-fork-<new>-steps.md` (in WSL, after the device test)

Intro: the series sits in the checkout's submodule `linux-sp11` exactly as built (authors and dates kept, unsigned,
the maintainer's own new patches without a sign-off); the steps sign it in place and push the new branch, with no
clone of the fork; the pushed head's tree must be `<tree>`, so nothing is rebuilt. Steps (7.3.3 revision 1):

1. `cd <checkout>/linux-sp11 && git status --short | head -n 3; git rev-parse HEAD 'HEAD^{tree}';
   git rev-list --count <base commit>..HEAD` — no status line; the rehearsal head, `<tree>`, `<n>`.
2. `git rebase --exec 'git commit --amend --no-edit -S' <base commit>` — `Successfully rebased and updated detached
   HEAD.` (the signing key asks for its passphrase, once with the agent).
3. For each of the maintainer's own new patches (here the last): `git commit --amend -s -S --no-edit` and
   `git log -1 --format='%h %G? %an %s%n%b' | tail -n 3` — the subject with `G` and `Signed-off-by: ...` last.
4. `git rev-parse 'HEAD^{tree}'; git log --format=%G? <base commit>..HEAD | sort | uniq -c` — `<tree>`; `<n> G`.
5. `git push git@github.com:<fork>.git HEAD:refs/heads/sp11/<new> && git rev-parse HEAD` — `* [new branch]`; the
   head to pin. Fallback, should the shallow repository refuse to push: the tarball with `git am -S` (`-s` for the
   maintainer's own patches) onto `v<new>` in a clone of the fork, then the same push.

Send back: the output, and the head commit.

## `README.txt`

Three to five lines: the revision, the kernel it is based on and that no intermediate version is needed, what
changed that the device test must watch, the fallback kernel; then the order: the device steps first, the fork steps
once they passed.
