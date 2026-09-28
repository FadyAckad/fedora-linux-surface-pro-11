# sp11-camera-update: commands and expected output

Run from the checkout's root unless a step says otherwise. `S=.claude/skills/sp11-camera-update`,
`C=build/camera-wip/libcamera-up` (the scratch clone), `R=45` (`FEDORA_RELEASE`). Values below are those of
libcamera 0.7.2-3.sp11.6 on Fedora 45 (2026-09-28).

## 1. State

What is pinned and built:

```bash
grep -E '^LIBCAMERA_' sp11.conf; ls build/rpms/ | grep -E '^libcamera-(ipa-|tools-)?[0-9]'; ls build/cache/ | grep '^libcamera'
```

Expected: `LIBCAMERA_RPM_SUFFIX="sp11.6"`, `LIBCAMERA_SRPM="libcamera-0.7.2-3.fc${FEDORA_RELEASE}.src.rpm"`, its
Koji URL, `LIBCAMERA_SRPM_SHA256="65ae0bad…"`, `LIBCAMERA_BASE_SPEC_SHA256="e4b392db…"`; the three RPMs at
`0.7.2-3.sp11.6.fc45`; `libcamera-0.7.2-3.fc45.src.rpm`.

Fedora's current build for the release (a newer one means section 2):

```bash
dnf -q repoquery --releasever=45 --qf '%{name}-%{version}-%{release}\n' libcamera
```

Expected: `libcamera-0.7.2-3.fc45` (or the newer build).

On the device, which build runs and what the front camera's image processing loads (the maintainer, one terminal,
no other camera application open):

```bash
rpm -q libcamera libcamera-ipa libcamera-tools; F=$(cam -l 2>/dev/null | sed -n 's/^\([0-9]*\): .*camera@1a)$/\1/p'); LIBCAMERA_LOG_LEVELS=IPAManager:DEBUG,IPASoft:INFO,IPASoftExposure:DEBUG cam -c "$F" -C30 2>&1 | grep -E 'signature is|Using tuning file|Exposure target|Exposure [0-9]+-[0-9]+, gain'
```

Expected: `.sp11.` in each release; `signature is valid`, `Using tuning file .../imx681.yaml`,
`Exposure target 1.4 by the tuning file`, `Exposure 8-3546, gain 1-16 (0.15)` (Fedora's build: `signature is not
valid`, `uncalibrated.yaml`, `gain 0-960 (1)`). The rear camera is `camera@10)`.

## 2. A new Fedora libcamera

The pipeline takes Koji's copy of the build, which is unsigned; check it against Fedora's signed copy (Koji keeps
that only while the build is current) and take its checksum (`<new>` and `<rel>`: version and release, as `0.7.2`
and `3`):

```bash
KOJI=https://kojipkgs.fedoraproject.org/packages/libcamera/<new>/<rel>.fc$R; N=libcamera-<new>-<rel>.fc$R.src.rpm; KEYFILE=/etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$R-primary; KEY=$(gpg --show-keys --with-colons "$KEYFILE" | awk -F: '/^pub/ {print tolower(substr($5, 9))}'); T=$(mktemp -d); KR=$(mktemp -d)
curl -fsSL -o "$T/u.rpm" "$KOJI/src/$N" && curl -fsSL -o "$T/s.rpm" "$KOJI/data/signed/$KEY/src/$N" && rpmkeys --root "$KR" --import "$KEYFILE" && rpmkeys --root "$KR" --checksig -v "$T/s.rpm" | grep -i signature; [ "$(rpm -qp --qf '%{PAYLOADSHA256}' "$T/s.rpm" 2>/dev/null)" = "$(rpm -qp --qf '%{PAYLOADSHA256}' "$T/u.rpm" 2>/dev/null)" ] && echo "same payload"; sha256sum "$T/u.rpm" | cut -d' ' -f1; rm -rf "$T" "$KR"
```

Expected: `Header OpenPGP V4 RSA/SHA256 signature, key fingerprint: ...: OK`, `same payload` and the checksum. Set
`<new>` and `<rel>` in `LIBCAMERA_SRPM` and `LIBCAMERA_SRPM_URL` in `sp11.conf` and the checksum as
`LIBCAMERA_SRPM_SHA256`; step 10 downloads the file, and step 47 names the new spec hash:

```bash
scripts/10-fetch-sources.sh >/dev/null && ls build/cache/ | grep '^libcamera'
```

```bash
scripts/47-build-camera-rpms.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'ERROR|differs'
```

Expected: `libcamera-<new>-<rel>.fc45.src.rpm` next to the old one; step 47 stops with `Fedora's libcamera.spec in
libcamera-<new>-<rel>.fc45.src.rpm differs from the one rpm/libcamera.spec.in was derived from ... set
LIBCAMERA_BASE_SPEC_SHA256=<hash>`.

Fedora's changes to its spec, to carry into the template (`<old>`: the previous build, as `0.7.2-3.fc45`; both
source RPMs are in `build/cache/`):

```bash
B=$PWD/build/cache; d=$(mktemp -d); for v in old new; do mkdir $d/$v; done; (cd $d/old && rpm2cpio $B/libcamera-<old>.src.rpm | cpio -idm --quiet ./libcamera.spec); (cd $d/new && rpm2cpio $B/libcamera-<new>-<rel>.fc45.src.rpm | cpio -idm --quiet ./libcamera.spec); diff -u $d/old/libcamera.spec $d/new/libcamera.spec
```

`rpm2cpio` names every file `./...`: a pattern without the `./` extracts nothing, silently.

## 3. Scratch clone, rebase, export

The clone (once; blobless, a few MB of history), detached at the new tag, with a placeholder identity for this
project's commits:

```bash
[ -d $C ] || git clone -q --filter=blob:none https://gitlab.freedesktop.org/camera/libcamera.git $C; git -C $C fetch -q --tags origin && git -C $C checkout -q --detach v<new> && git -C $C config user.name sp11-scratch && git -C $C config user.email scratch@invalid && git -C $C log --oneline -1
```

Expected: `<hash> libcamera v<new>`.

Apply the series in order. The third-party patches (0001–0004) are mails; this project's (0005 on) have no
headers, so they are applied and committed with their first paragraph as the message:

```bash
for p in payload/camera/0*.patch; do if head -1 "$p" | grep -q '^From '; then git -C $C am -q "$PWD/$p" || break; else git -C $C apply --index "$PWD/$p" && git -C $C commit -q -F <(sed '/^---$/,$d' "$p") || break; fi; done; git -C $C log --oneline v<new>..HEAD | wc -l
```

Expected: `9`; on 0.7.2 the result's tree is the one the payload was exported from (checked 2026-09-28). A patch
that does not apply stops the loop: resolve it in the clone (`git am --continue` for a mail; `git apply --reject`,
fix, `git add`, commit for this project's), then run the loop again from the next patch.

Export again, then strip the mail headers from this project's patches (its commits are by `sp11-scratch`):

```bash
rm -rf build/camera-wip/export && git -C $C format-patch -q --zero-commit --no-signature -o "$PWD/build/camera-wip/export" v<new>..HEAD && ls build/camera-wip/export
```

```bash
for f in build/camera-wip/export/*.patch; do grep -q '^From: sp11-scratch' "$f" && python3 -c 'import re,sys; p=sys.argv[1]; t=open(p).read(); m=re.match(r"From [0-9a-f]{40} [^\n]*\nFrom: [^\n]*\nDate: [^\n]*\nSubject: (?:\[PATCH[^\]]*\] )?(.*?)\n\n", t, re.S); open(p,"w").write(" ".join(l.strip() for l in m.group(1).split("\n")) + "\n\n" + t[m.end():])' "$f"; done; grep -L '^From: ' build/camera-wip/export/*.patch
```

Expected: the file names of this project's patches (no `From:` line left). On 0.7.2 the export equals
`payload/camera/` byte for byte (sp11.6; the four mails' subjects carry the series' length, `[PATCH n/9]`, so a new
patch renumbers them: take that over only together with a real change, since a changed file changes step 47's
inputs). Replace `payload/camera/0*.patch` with the export, check `git diff --stat payload/camera/`, and keep the
`Patch02`–`Patch10` lines of `rpm/libcamera.spec.in` in step with the file names.

## 4. Pins, build, host checks

After the template and the patches: the next suffix, and the new spec's hash if section 2 applied:

```bash
grep -n '^LIBCAMERA_RPM_SUFFIX\|^LIBCAMERA_BASE_SPEC_SHA256\|0.7.2-3.sp11' sp11.conf
```

Build and check (about five minutes; step 48 follows when a live root exists):

```bash
scripts/47-build-camera-rpms.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^\[sp11\] (libcamera RPMs|camera RPMs verified)|FAIL|ERROR'
```

Expected: `libcamera RPMs: libcamera-<version>-<rel>.<suffix>.fc45.aarch64.rpm ...` and `camera RPMs verified in an
overlay of the live root: ...`, no `FAIL` or `ERROR`; no compiler warning in the mock log
(`grep -c 'warning:' build/work/mock-libcamera/build.log` against the previous build's count).

The exposure control, for a changed control law or target (about ten seconds per run):

```bash
python3 -B $S/agc-model.py --target 1.4; python3 -B $S/agc-model.py --sensor ov13858 --again-max 15.5; python3 -B $S/agc-model.py --lux 12.5 14.5 16.5 --gain-codes truncate
```

Expected with 0008 and target 1.4: `dark spot 1 lux ... never` at an MSV of 1.00 to 1.03 and the limits
(`3546 / 16.00 / 4.00`; the rear camera `3206 / 15.50 / 4.00`), `dim 10 lux` reached within about 6 s, `room` and
`daylight` within about 1.5 s, wobble below 2 %; `--gain-codes truncate` (before 0009) leaves 12.5 to 16.5 lux at
13.3x to 15.75x without digital gain and an MSV of about 1.2, the default (0009) reaches 16x there. Run the old
values too and compare.

The GPU debayering, for a shader change (the first run sets up a mock root, about a minute afterwards):

```bash
$S/debayer-model.sh $C v<version>
```

Expected: the numbers in `debayer-model.py`'s docstring (dark flat frame: spread about 4 levels original, 0.6 to
0.7 with `quad 1`, `identical to the original: True` with `quad 0`).

The raw-capture probe, for a probe change (needs `sudo -n`; about ten seconds):

```bash
$S/probe-fake.sh 2>&1 | grep -E '^===|at 886 lines|at 665 lines|x step|^ 15.5x|^   31x'
```

Expected: `rev8`: 20.00 and 15.00 fps at 886 lines; `rev8-ignored` and `rev7`: 30.00 at the short exposure;
`FAKE_GAIN_STOP=15.5`: `x step 1.00` from 31x on, without it about 2 per step.

## 5. On the device

Trying a tuning value before building it (the maintainer, as the desktop user; a libcamera update undoes it):

```bash
sudo sed -i 's/^\(\s*exposureTarget:\).*/\1 1.6/' /usr/share/libcamera/ipa/simple/imx681.yaml && systemctl --user restart wireplumber pipewire
```

The raw sensor output (`sudo python3 sp11-camera-probe front|rear [--dark | --frame-length | --gain-range]`, every
camera application closed): see `payload/camera/sp11-camera-probe`'s docstring and `docs/camera.md` (On the device).

Files returned on the Windows desktop, when WSL cannot read them by path (drvfs ACLs):

```bash
cmd.exe /c type 'C:\Users\<user>\Desktop\<folder>\<file>.txt' | tr -d '\r' > build/handoff/<folder>-results/<file>.txt
```

```bash
powershell.exe -NoProfile -Command "[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\Users\<user>\Desktop\<folder>\<photo>.jpg'))" | tr -d '\r\n' | base64 -d > build/handoff/<folder>-results/<photo>.jpg
```

A colour-correction matrix needs a colour chart photographed under known light: a genuine Calibrite (X-Rite)
ColorChecker Classic, whose reference values libcamera's `utils/tuning` (libtuning: `macbeth.py`, the CCM module)
uses; the Mini and Passport editions carry the same patches, clones do not match the reference.
