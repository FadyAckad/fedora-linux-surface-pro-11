# Kernel update: hand-off

The folder (location and naming in `CLAUDE.local.md`) holds the five `KERNEL_PKGS` RPMs of the new uname with a
`.sha256` each (`sha256sum <rpm> > <rpm>.sha256`), `sp11-dsp-ping.py` from this skill's directory, the series as
`sp11-<new>-series.tar.gz` (`git format-patch --no-signature v<new>..<head>`, packed without a directory), and the
three files below. Before handing over, apply the tarball with `git am` onto `v<new>` in a throwaway clone
(`git clone --shared --no-checkout <fork clone>`, detached at the tag, signing off): 58 commits and one whitespace
warning for 7.2.7, and the rehearsal's tree.

Steps files follow the maintainer's format: a `#` title with topic, version and date; a short intro (what changed,
what was verified off-hardware, what can break, the way back); numbered steps with one command per fenced `bash`
block and an `Expected:` after it; a closing line naming what to send back. Commands are the ones earlier rounds
ran on the device; expected lines come from the previous round's returned output (its `sp11-diag` file has the
kernel log), because a line the code prints under some condition may never appear on the device. Placeholders:
`<abi>` the new uname (`7.2.7-300.sp11.5.fc45.aarch64`), `<prev-abi>` the installed revision's, `<new>`, `<rev>`,
`<date>`, `<tree>`, `<n>` the series' commit count, `<folder>` the hand-off folder's Windows path in WSL.

## `sp11-rev<rev>-steps.md` (on Fedora)

Cover, in this order, and keep the commands exactly as below:

1. `sha256sum -c *.sha256` — every file `OK`.
2. `df -h /boot` — at least 250M in `Avail` (each SP11 kernel takes about 195 MB there); otherwise stop.
3. `sudo dnf install ./kernel{,-core,-modules-core,-modules,-modules-extra}-<abi>.rpm` — five packages next to
   `<prev-abi>`, dracut runs, no error line.
4. `sudo sh -c 'grep -hE "^(title|devicetree|options)" /boot/loader/entries/*-<abi>.conf'` and
   `sudo grub2-editenv list` — `devicetree /dtb-<abi>/qcom/x1e80100-microsoft-denali-oled.dtb`, the SP11 arguments
   (possibly followed by `$tuned_params`), `saved_entry` ending in `<abi>`.
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
10. Crypto engine: `grep -E '^driver +: .*-qce$' /proc/crypto` and
    `sudo journalctl -k -b --no-pager | grep -E 'alg: |qce'` — `sha256-qce` and `hmac-sha256-qce`, nothing with
    `aes`; no `self-tests ... failed`.
11. By hand: Wi-Fi, the Bluetooth keyboard and pen, battery, brightness, volume keys, keyboard and touchpad,
    rotation with the keyboard folded back, power modes; optional: an external display on USB-C.
12. Suspend from the Power menu, one minute, wake: display, touch, pen, keyboard, Wi-Fi and sound as before.
13. `sudo /usr/libexec/sp11/sp11-diag ./sp11-diag-sp11.<rev>.txt` and
    `grep -A2 'state_synced' ./sp11-diag-sp11.<rev>.txt` — the file written; `no provider waits for sync_state`.
14. Second boot, 3 minutes: `ls -l /dev/fastrpc-cdsp`, `sudo timeout 20 python3 ./sp11-dsp-ping.py 10 1` —
    the node; `answered`.
15. Only if the revision misbehaves: boot `<prev-abi>` from the GRUB menu, then
    `sudo dnf remove kernel{,-core,-modules-core,-modules,-modules-extra}-<abi>`,
    `sudo grubby --set-default /boot/vmlinuz-<prev-abi>` and `sudo grubby --default-kernel` — five packages
    removed; `/boot/vmlinuz-<prev-abi>`.

Add a check for every patch the rebase adapted or added (for 7.2.7, step 6 covers the SoundWire fix and step 8 the
adapted SPI patch). Send back: the terminal output of the steps, `sp11-diag-sp11.<rev>.txt`, one line per by-hand
check. Compare its `recent journal errors` section with the previous round's.

## `sp11-fork-<new>-steps.md` (in WSL, after the device test)

Intro: the branch is created like the previous ones, `git am` onto the stable tag with one signed commit per patch;
the kernel under test was built from exactly these patches; the pushed head's tree must be `<tree>`, so nothing is
rebuilt; which patches carry the maintainer as author. Steps:

1. `mkdir -p ~/sp11-<new>-series && tar -xzf <folder>/sp11-<new>-series.tar.gz -C ~/sp11-<new>-series` and
   `ls ~/sp11-<new>-series | wc -l` — `<n>`.
2. `cd <fork clone> && git status --short && git rev-parse 'v<new>^{commit}'` — no status lines; the tag's commit.
3. `git switch -c sp11/<new> v<new>` and `git am ~/sp11-<new>-series/*.patch` — the new branch; `<n>` `Applying:`
   lines and the known whitespace warnings; the signing key asks for its passphrase.
4. `git rev-parse 'HEAD^{tree}'` and `git log --format=%G? v<new>..HEAD | sort | uniq -c` — `<tree>`; `<n> G`.
5. `git push -u origin sp11/<new>` and `git rev-parse HEAD` — `[new branch]`; the head to pin.

Send back: the output, and the head commit.

## `README.txt`

Three to five lines: the revision, the kernel it is based on and that no intermediate version is needed, what
changed that the device test must watch, the fallback kernel; then the order: the device steps first, the fork steps
once they passed.
