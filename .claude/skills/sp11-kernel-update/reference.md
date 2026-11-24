# Kernel update: commands

The commands of [SKILL.md](SKILL.md), step by step, run from the checkout's root in bash. Set the values first, in
every new shell; the examples are those of the 7.2.5 to 7.2.7 update, but for the revision, which restarts at 1
with every kernel version since 7.2.11.

```bash
OLD=7.2.5 OLDREL=300    # KERNEL_FEDORA_VERSION and KERNEL_FEDORA_RELEASE as pinned before the update
NEW=7.2.7 REL=300       # the new Fedora kernel and its release
FR=45 REV=1             # FEDORA_RELEASE; the new KERNEL_SP11_REV (1 for a new kernel version)
KORG=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git   # where the stable tags come from
R=build/rebase          # scratch area inside the git-ignored build/
KOJI=https://kojipkgs.fedoraproject.org/packages/kernel/$NEW/$REL.fc$FR
PIN=$(git rev-parse HEAD:linux-sp11)   # the committed pin: the submodule's gitlink
```

In a worktree, prepare `build/` (section 4) before the downloads of section 1.

## 1. Target and inputs

Fedora's kernel updates for the release, newest first:

```bash
curl -s "https://bodhi.fedoraproject.org/updates/?packages=kernel&releases=F$FR&rows_per_page=10" -H 'Accept: application/json' | python3 -c 'import json, sys; [print(u["title"], u["status"], u.get("date_stable") or "") for u in json.load(sys.stdin)["updates"]]'
```

Expected: lines like `kernel-7.2.7-300.fc45 stable 2026-09-23 00:15:11`; take the newest `stable` one.

The stable tags at kernel.org (no clone of the fork is needed; the tags come into the scratch clone of section 2):

```bash
git ls-remote "$KORG" "refs/tags/v$OLD^{}" "refs/tags/v$NEW^{}"; grep -n '^KERNEL_PATCH_BASE_COMMIT=' sp11.conf
```

Expected: `v$OLD`'s id equals `KERNEL_PATCH_BASE_COMMIT`; `v$NEW`'s id becomes it in section 4.

Fedora's source RPM and stock `kernel-core`, and their sha256 for `sp11.conf`:

```bash
(cd build/cache && curl -fsSLO "$KOJI/src/kernel-$NEW-$REL.fc$FR.src.rpm" && curl -fsSLO "$KOJI/aarch64/kernel-core-$NEW-$REL.fc$FR.aarch64.rpm" && sha256sum "kernel-$NEW-$REL.fc$FR.src.rpm" "kernel-core-$NEW-$REL.fc$FR.aarch64.rpm")
```

The same packages as Fedora signed them (the key file comes with the host's `fedora-gpg-keys`, under
`/usr/share/pki/rpm-gpg` on Fedora 45, where `/etc/pki/rpm-gpg` is empty):

```bash
KEYFILE=/usr/share/pki/rpm-gpg/RPM-GPG-KEY-fedora-$FR-primary; KEY=$(gpg --show-keys --with-colons "$KEYFILE" | awk -F: '/^pub/ {print tolower(substr($5, 9))}'); S=$(mktemp -d); KR=$(mktemp -d)
curl -fsSL -o "$S/src.rpm" "$KOJI/data/signed/$KEY/src/kernel-$NEW-$REL.fc$FR.src.rpm" && curl -fsSL -o "$S/core.rpm" "$KOJI/data/signed/$KEY/aarch64/kernel-core-$NEW-$REL.fc$FR.aarch64.rpm"
rpmkeys --root "$KR" --import "$KEYFILE" && rpmkeys --root "$KR" --checksig -v "$S/src.rpm" "$S/core.rpm" | grep -i signature
for p in "src.rpm kernel-$NEW-$REL.fc$FR.src.rpm" "core.rpm kernel-core-$NEW-$REL.fc$FR.aarch64.rpm"; do set -- $p; [ "$(rpm -qp --qf '%{PAYLOADSHA256}' "$S/$1" 2> /dev/null)" = "$(rpm -qp --qf '%{PAYLOADSHA256}' "build/cache/$2")" ] && echo "same payload: $2"; done; rm -rf "$S" "$KR"
```

Expected: two `signature, key fingerprint: ...: OK` lines and two `same payload` lines.

Both source RPMs unpacked, the spec's local-build slots, and Fedora's own patch against the series' files:

```bash
for v in "$OLD-$OLDREL" "$NEW-$REL"; do mkdir -p "$R/srpm-$v" && (cd "$R/srpm-$v" && rpm2cpio "../../cache/kernel-$v.fc$FR.src.rpm" | cpio -idm --quiet); done
```

```bash
grep -cE '^# define buildid \.local$|^Patch999999: linux-kernel-test\.patch$|^Source3001: kernel-local$|^ApplyOptionalPatch linux-kernel-test\.patch$' "$R/srpm-$NEW-$REL/kernel.spec"
```

```bash
git -C linux-sp11 diff --name-only "$(sed -n 's/^KERNEL_PATCH_BASE_COMMIT="\([0-9a-f]*\)".*/\1/p' sp11.conf)" "$PIN" | sort > "$R/series-files.txt"; grep '^diff --git' "$R/srpm-$NEW-$REL"/patch-*-redhat.patch | awk '{print $3}' | sed 's|^a/||' | sort -u > "$R/redhat-files.txt"; wc -l < "$R/series-files.txt"; comm -12 "$R/series-files.txt" "$R/redhat-files.txt"
```

Expected: `4`; the number of files the series touches (80 at 7.2.5, 100 since revision 6, 118 at 7.2.15), and no
file both touch but `MAINTAINERS` (up to 7.2.15 also `drivers/media/i2c/Kconfig` and `Makefile`, for the IMX471
driver 7.3 has). kernel.spec applies the series after Fedora's patch, so prove it after the rebase on the copy of
Fedora's tarball the tarball check below unpacks (section 2 has the command); the first build of revision 6
stopped in `%prep` on exactly this.

Fedora's configuration change between the two stock `kernel-core` packages (the old one is in the cache of the
checkout that built the pinned revision):

```bash
for v in "$OLD-$OLDREL" "$NEW-$REL"; do rpm2cpio "build/cache/kernel-core-$v.fc$FR.aarch64.rpm" | cpio -i --quiet --to-stdout "./lib/modules/$v.fc$FR.aarch64/config" > "$R/stock-config-$v"; done
```

```bash
diff <(grep -E '^(CONFIG_|# CONFIG_)' "$R/stock-config-$OLD-$OLDREL" | sort) <(grep -E '^(CONFIG_|# CONFIG_)' "$R/stock-config-$NEW-$REL" | sort) > "$R/stock-config.diff"; cat "$R/stock-config.diff"; grep -oE 'CONFIG_[A-Za-z0-9_]+' payload/kernel-local | sort -u | while read -r s; do if grep -qw "$s" "$R/stock-config.diff"; then echo "kernel-local symbol changed: $s"; fi; done
```

Expected: toolchain values (`BUILD_SALT`, `PAHOLE_VERSION`, `RUSTC_*`, ...) and Fedora's own changes (7.2.7: the
NTFS driver); no `kernel-local symbol changed` line.

Fedora's tarball against the tag (under a minute on an idle host, several while a build runs):

```bash
T=$R/tarcheck; rm -rf "$T"; mkdir -p "$T/tag"; tar -xf "$R/srpm-$NEW-$REL/linux-$NEW.tar.xz" -C "$T"; git -C "$R/linux" archive "v$NEW" | tar -x -C "$T/tag"
diff -r --no-dereference "$T/linux-$NEW" "$T/tag" > /dev/null && echo "same content"; diff <(cd "$T/linux-$NEW" && find . | sort) <(cd "$T/tag" && find . | sort) > /dev/null && echo "same entries"; diff <(cd "$T/linux-$NEW" && find . -type f -perm -u+x | sort) <(cd "$T/tag" && find . -type f -perm -u+x | sort) > /dev/null && echo "same executables"
```

Expected: `same content`, `same entries`, `same executables`. Both copies stay for the proof of section 2 that the
series applies after Fedora's patch.

## 2. Rebase rehearsal

The scratch clone: a shared clone of the submodule (step 10 initialized it, shallow, back past the base), detached
at the pinned head, with the identity of the maintainer's own patches (read from the pinned head) and without
signing; the old tag named locally, the new tag and the release tags of its series fetched from kernel.org without
the history the base already has (7.3.3 from 7.2.15: 17 k commits, 220 MB, under a minute):

```bash
git clone -q --shared --no-checkout "$PWD/linux-sp11" "$R/linux" && git -C "$R/linux" config user.name "$(git -C linux-sp11 log -1 --format=%an "$PIN")" && git -C "$R/linux" config user.email "$(git -C linux-sp11 log -1 --format=%ae "$PIN")" && git -C "$R/linux" config commit.gpgsign false && git -C "$R/linux" checkout -q --detach "$PIN" && git -C "$R/linux" tag "v$OLD" "$(sed -n 's/^KERNEL_PATCH_BASE_COMMIT="\([0-9a-f]*\)".*/\1/p' sp11.conf)"
```

```bash
git -C "$R/linux" fetch --no-tags --shallow-exclude="v$OLD" "$KORG" "refs/tags/v$NEW:refs/tags/v$NEW" "refs/tags/v${NEW%.*}:refs/tags/v${NEW%.*}" && git -C "$R/linux" rev-parse "v$NEW^{commit}"
```

Expected: `* [new tag]` lines and kernel.org's id of `v$NEW`. This clone has the complete *tree* of every commit
(the rebase, the compile check and `git archive` are right), but not the complete *history*: `--shallow-exclude`
cuts every chain behind a merge of excluded history (a maintainer's back-merge of a `-rc` tag), a sixth of 7.3's
commits, and a cut commit is a root whose `git show` prints the whole tree (64 MB). The surveys below therefore run
in a second repository, fetched by date into an empty one (`--shallow-since` into an existing shallow clone fails
with `error in object: unshallow`); the date lies before the new series' merge window (7.3: 2026-06-01; 20 k
commits, 400 MB, a few minutes). The series comes in from the submodule; the stale shallow entry of the submodule's
boundary is removed because the new repository has its parent:

```bash
git init -q "$R/linux2" && git -C "$R/linux2" fetch --no-tags --shallow-since=<date> "$KORG" "refs/tags/v$NEW:refs/tags/v$NEW" "refs/tags/v$OLD:refs/tags/v$OLD" "refs/tags/v${NEW%.*}:refs/tags/v${NEW%.*}" && git -C "$R/linux2" fetch -q --no-tags "$PWD/linux-sp11" HEAD:refs/heads/series && for s in $(cat "$R/linux2/.git/shallow"); do p=$(git -C "$R/linux2" cat-file commit "$s" 2>/dev/null | awk '/^parent/ {print $2}' | head -1); [ -n "$p" ] && git -C "$R/linux2" cat-file -e "$p" 2>/dev/null && sed -i "/^$s\$/d" "$R/linux2/.git/shallow"; done; git -C "$R/linux2" rev-list --count "v$OLD..series"; git -C "$R/linux2" rev-list --count "v$OLD..v$NEW"
```

Expected: the series' commit count and the stable range's (7.2.15 to 7.3.3: 20994). `--min-parents=1` keeps the
remaining date-cut roots out of every survey.

In a worktree whose submodule is not initialized, make the scratch clone from the main checkout's submodule
(`$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/linux-sp11`) and read the identity from
it; section 4 initializes the worktree's submodule from the scratch clone.

A point release of the same series has no merge (7.3.3 to 7.3.5: 1769 commits, fetched in 4 s), so the scratch
clone serves the surveys and no second repository is needed. Its fetch still records the range's first commit as
shallow although its parent, the old tag, is in the clone: until the entry is removed that commit is a root,
`git merge-base` finds nothing and `git merge-tree` cannot be used. With `$R/linux` in place of `$R/linux2` in the
surveys below:

```bash
for s in $(cat "$R/linux/.git/shallow"); do p=$(git -C "$R/linux" cat-file commit "$s" 2>/dev/null | awk '/^parent/ {print $2}' | head -1); [ -n "$p" ] && git -C "$R/linux" cat-file -e "$p" 2>/dev/null && sed -i "/^$s\$/d" "$R/linux/.git/shallow"; done; git -C "$R/linux" merge-base "v$NEW" "$PIN"; git -C "$R/linux" rev-list --count --merges "v$OLD..v$NEW"
```

Expected: the old tag's commit and `0`. One three-way merge then names every file a rebase will stop at:

```bash
git -C "$R/linux" merge-tree --write-tree --name-only --no-messages "v$NEW" "$PIN" | sed -n '2,$p' | sort -u
```

The stable commits that touch the series' files, each with the first release that has it:

```bash
cd "$R/linux2" && git log --no-merges --min-parents=1 --format='%h %s' "v$OLD..v$NEW" -- $(cat ../series-files.txt) > ../stable-touching.txt; while read -r c s; do echo "$(git tag --contains "$c" --list "v${NEW%.*}*" --sort=v:refname | head -1) $c $s"; done < ../stable-touching.txt; cd - > /dev/null
```

Which SP11 patch each of them meets (number in the old series, subject, stable commit, shared files):

```bash
cd "$R/linux2" && git log --reverse --format=%H "v$OLD..series" > ../series-commits.txt; n=0; while read -r c; do n=$((n + 1)); f=$(git diff-tree --no-commit-id --name-only -r "$c" | sort); while read -r s rest; do common=$(comm -12 <(echo "$f") <(git diff-tree --no-commit-id --name-only -r "$s" | sort) | tr '\n' ' '); [ -n "$common" ] && printf '%04d %s <-> %s %s: %s\n' "$n" "$(git log -1 --format=%s "$c" | cut -c1-50)" "$s" "${rest:0:40}" "$common"; done < ../stable-touching.txt; done < ../series-commits.txt; cd - > /dev/null
```

The rebase (it stops at each conflict):

```bash
git -C "$R/linux" rebase --empty=drop --onto "v$NEW" "v$OLD"
```

Expected: `dropping <id> <subject> -- patch contents already upstream` for each patch now upstream. At a conflict,
`git -C "$R/linux" diff --name-only --diff-filter=U` lists the files; after resolving:

```bash
git -C "$R/linux" add <resolved files> && GIT_EDITOR=true git -C "$R/linux" rebase --continue
```

A note or a fix for patch K of the rebased series (`K=<number>`), keeping its author and re-stacking the patches
above it. The first command checks the patch out and writes its message to `$R/msg.txt`; append the
`[sp11: ...]` note after the trailers there and, for a fix, edit the files in `$R/linux`; the second amends and
re-stacks:

```bash
cd "$R/linux" && H=$(git rev-parse HEAD) && C=$(git log --reverse --format=%H "v$NEW..$H" | sed -n "${K}p") && git log -1 --format=%B "$C" > ../msg.txt && git checkout -q --detach "$C"; cd - > /dev/null
```

```bash
cd "$R/linux" && git commit -q -a --amend -F ../msg.txt && git rebase -q --onto HEAD "$C" "$H" && git rev-parse HEAD 'HEAD^{tree}'; cd - > /dev/null
```

Authors, dates and subjects against the old branch, then the patch-by-patch comparison:

```bash
diff <(git -C "$R/linux" log --reverse --format='%an <%ae>|%ad|%s' --date=raw "v$OLD..$PIN") <(git -C "$R/linux" log --reverse --format='%an <%ae>|%ad|%s' --date=raw "v$NEW..HEAD")
```

```bash
git -C "$R/linux" range-diff "v$OLD..$PIN" "v$NEW..HEAD" > "$R/range-diff.txt"; grep -E '^ *[0-9-]+: +[0-9a-f-]+ [!<>] ' "$R/range-diff.txt"
```

Expected: `<` lines only for the dropped patches and `>` only for new ones; in the range-diff, `!` for every
adapted patch, and a partly upstream patch as a `<` and `>` pair.

The series as kernel.spec applies it, after Fedora's own patch, on the copies the tarball check of section 1
left:

```bash
T=$PWD/$R/tarcheck S=$PWD/$R/series-check P=$PWD/$R/srpm-$NEW-$REL/patch-${NEW%.*}-redhat.patch; git -C "$R/linux" format-patch -q --no-signature --no-renames -o "$S" "v$NEW..HEAD"; export GIT_CEILING_DIRECTORIES=$T; (cd "$T/tag" && cat "$S"/*.patch | git apply --check -R --whitespace=nowarn - 2> /dev/null) || echo "control: the tag tree refuses the reverse"; (cd "$T/linux-$NEW" && git apply "$P" && cat "$S"/*.patch | git apply --check --whitespace=nowarn - && echo "the series applies after the Fedora patch")
```

Expected: `control: the tag tree refuses the reverse` and `the series applies after the Fedora patch`. The first
line is what makes the second one count: inside this checkout, `build/` included, `git apply` skips every path of a
patch and reports success, and `GIT_CEILING_DIRECTORIES` is what makes it a patch tool there.

A clean textual merge of a carried patch can hide a reversion: compare each touched file's tested change
(`git diff v$OLD $PIN -- FILE`) with its effective change on the new base (`git diff v$NEW -- FILE` in `$R/linux`)
by their `+`/`-` lines; the 7.3.3 rebase found two extraction artefacts this way (deleted tracepoints, a reverted
PM-clock conversion) and a semantic clash (the DMIC divider derived twice).

The stable changes of the subsystems the SP11 relies on (read the list; 236 commits from 7.2.5 to 7.2.7, before the
camera paths were added; 1670 from 7.2.15 to 7.3.3):

```bash
git -C "$R/linux2" log --no-merges --min-parents=1 --format='%h %s' "v$OLD..v$NEW" -- drivers/remoteproc drivers/misc/fastrpc.c drivers/soc/qcom drivers/pmdomain/qcom drivers/interconnect/qcom drivers/clk/qcom drivers/pinctrl/qcom drivers/net/wireless/ath/ath12k drivers/bluetooth drivers/platform/surface drivers/usb/dwc3 drivers/usb/typec drivers/power/supply/qcom_battmgr.c drivers/gpu/drm/msm drivers/iommu/arm drivers/cpufreq drivers/firmware/arm_scmi drivers/firmware/qcom drivers/spi/spi-geni-qcom.c drivers/dma/qcom sound/soc/qcom sound/soc/codecs/wsa884x.c 'sound/soc/codecs/lpass-*' drivers/soundwire drivers/hid drivers/input drivers/nvme drivers/pci/controller/dwc net/qrtr drivers/rpmsg drivers/thermal/qcom drivers/iio drivers/phy/qualcomm drivers/crypto/qce drivers/media/platform/qcom/camss drivers/media/i2c drivers/media/v4l2-core drivers/i2c/busses/i2c-qcom-cci.c drivers/leds drivers/regulator arch/arm64/boot/dts/qcom/hamoa.dtsi arch/arm64/boot/dts/qcom/x1-microsoft-denali.dtsi drivers/bus/mhi drivers/pci/pcie drivers/pci/pci.c drivers/tty/serial/qcom_geni_serial.c drivers/power/sequencing drivers/input/touchscreen drivers/base/platform.c > "$R/stable-relevant.txt"; wc -l < "$R/stable-relevant.txt"
```

A new fix: edit the files in `$R/linux`, write the message to `$R/msg-fix.txt`, then commit it on top with the
configured identity (the maintainer's, as for the POS switch) and check it:

```bash
git -C "$R/linux" commit -q -a -F ../msg-fix.txt && rm -rf "$R/checkpatch" && git -C "$R/linux" format-patch -q -1 -o ../checkpatch HEAD && (cd "$R/linux" && perl scripts/checkpatch.pl --strict ../checkpatch/*.patch)
```

Expected: only `ERROR: Missing Signed-off-by: line(s)`.

## 3. Host compile check

```bash
mkdir -p "$R/kbuild" && { cat "$R/stock-config-$NEW-$REL"; grep -E '^(CONFIG_|# CONFIG_)' payload/kernel-local; } > "$R/kbuild/.config" && make -s -C "$R/linux" O=../kbuild ARCH=arm64 olddefconfig
```

```bash
grep -E '^(CONFIG_|# CONFIG_)' payload/kernel-local | while IFS= read -r l; do grep -qxF "$l" "$R/kbuild/.config" || echo "LOST: $l"; done
```

```bash
git -C "$R/linux" diff --name-only "v$NEW" HEAD | grep / | sed 's|/[^/]*$||' | sort -u | grep -vE '^(include|Documentation|arch/arm64/boot/dts)|^drivers/hid/bpf' | sed 's|$|/|' | awk 'BEGIN {p = ""} {if (p != "" && index($0, p) == 1) next; print; p = $0}' > "$R/build-targets.txt"; rm -rf "$R/kbuild/drivers" "$R/kbuild/sound" "$R/kbuild/net" "$R/kbuild/arch/arm64/boot/dts"
```

```bash
make -C "$R/linux" O=../kbuild ARCH=arm64 -j"$(nproc)" prepare modules_prepare > "$R/kbuild-prepare.log" 2>&1; echo "prepare rc=$?"; make -C "$R/linux" O=../kbuild ARCH=arm64 -j"$(nproc)" $(cat "$R/build-targets.txt") > "$R/kbuild-dirs.log" 2>&1; echo "dirs rc=$?"; make -C "$R/linux" O=../kbuild ARCH=arm64 -j"$(nproc)" dtbs > "$R/kbuild-dtbs.log" 2>&1; echo "dtbs rc=$?"; grep -E 'warning:|error:' "$R/kbuild-dirs.log" "$R/kbuild-dtbs.log"
```

Expected: the `olddefconfig` override warnings for the `kernel-local` symbols, no `LOST:` line; three `rc=0`, no
`warning:` or `error:` line. `build-targets.txt` must list only kernel make targets: top-level files such as
`MAINTAINERS` (touched since revision 6) are left out by the `grep /`; drop any other directory the series touches
(tools, scripts) the same way.
The `awk` keeps only the top-most directory of a nest: `drivers/pci/` and `drivers/pci/controller/dwc/` as two
targets of one `make -j` race for `drivers/pci/controller/built-in.a` (`ar: ... No such file or directory`,
`Error 123`), seen at 7.2.15.

## 4. Pins and build directory

The submodule at the rehearsal head, pinned in the index and named in `.gitmodules`. Only the series' commits are
fetched: a plain fetch there would pull the fork's whole history (5 GB).

```bash
N=$(git -C "$R/linux" rev-list --count "v$NEW..HEAD"); git -C linux-sp11 fetch -q --no-tags --depth=$((N + 1)) "$PWD/$R/linux" HEAD && git -C linux-sp11 checkout -q --detach FETCH_HEAD && git add linux-sp11 && git config -f .gitmodules submodule.linux-sp11.branch "sp11/$NEW" && git submodule status
```

Expected: ` <rehearsal head> linux-sp11 (...)`, the head the scratch clone is detached at.

In a worktree whose submodule is not initialized, register and create it first, as step 10 would, but without
its fetch from the fork, which does not have the rehearsal head; after the command above, move its `.git` into
the superproject's:

```bash
[ -e linux-sp11/.git ] || { git submodule init -q -- linux-sp11 && git init -q linux-sp11 && git -C linux-sp11 remote add origin "$(git config --get submodule.linux-sp11.url)"; }
```

```bash
git submodule absorbgitdirs -- linux-sp11
```

The revision hash for `KERNEL_SP11_REV_SHA256`, after the other `sp11.conf` edits:

```bash
bash -c '. scripts/lib.sh; kernel_rev_sha256'
```

A worktree's `build/`, from the main checkout's (hard links, so nothing is downloaded or copied twice):

```bash
MAIN=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/build; mkdir -p build/cache build/rpms build/work/iso build/logs; find "$MAIN/cache" -maxdepth 1 -type f -exec ln -f {} build/cache/ \; ; cp -al "$MAIN/cache/sp11-audio-v19c" "$MAIN/cache/wifi" "$MAIN/cache/rpm-deps" build/cache/; cp -a "$MAIN/cache/iptsd" "$MAIN/cache/oe" "$MAIN/cache/libssc" build/cache/; ln -f "$MAIN"/rpms/sp11-surface-support-*.rpm build/rpms/; ln -f "$MAIN/hardware.env" build/
```

On a host with the Secure Boot signing key, the stub of the main checkout as well, so that step 25 packs the
image with the stub the installed images have instead of building one:

```bash
mkdir -p build/secureboot && ln -f "$MAIN"/secureboot/sp11-secureboot-stub-*.rpm build/secureboot/
```

```bash
sudo cp -al "$MAIN/work/iso/rootfs" build/work/iso/rootfs && sudo rpm --root "$PWD/build/work/iso/rootfs" -q --whatprovides kernel-core-uname-r sp11-surface-support
```

```bash
ps -eo pid,etime,args | grep -E '[m]ock|[r]pmbuild'
```

Expected: the live root's kernel (the previous revision) and support RPM; no mock or rpmbuild process.

## 5. Build and verify

```bash
scripts/10-fetch-sources.sh > "build/logs/step10-$NEW-rev$REV.log" 2>&1; echo "step 10 rc=$?"; sed 's/\x1b\[[0-9;]*m//g' "build/logs/step10-$NEW-rev$REV.log" | grep -E 'SP11 patch set|all sources present|ERROR' 
```

Expected: `step 10 rc=0`, `SP11 patch set: <n> commits, v<new>..<head>` (with ` (shallow)` when the submodule is)
and `all sources present`.

```bash
setsid nohup bash -c './scripts/20-build-kernel.sh; echo "STEP20-DONE rc=$?"' > "build/logs/step20-$NEW-rev$REV.log" 2>&1 < /dev/null & disown
```

Wait in the background for the marker, or for the build's shell to be gone:

```bash
until grep -q STEP20-DONE "build/logs/step20-$NEW-rev$REV.log" || ! pgrep -f '^bash -c ./scripts/20-build-kernel.sh' > /dev/null; do sleep 30; done; sed 's/\x1b\[[0-9;]*m//g' "build/logs/step20-$NEW-rev$REV.log" | tail -4
```

Expected: `kernel <abi>: configuration = Fedora's kernel-core-<new>-<rel>.fc<n> + kernel-local; DTBs
x1e80100-microsoft-denali-oled.dtb and x1e80100-microsoft-denali-oled-5g.dtb, compatible: ...`, then
`STEP20-DONE rc=0`.

Step 36 as an installed system with the current support RPM sees it: that RPM reinstalled first, so its
`%posttrans` writes the menu such a system has (the live root's own menu is Fedora's):

```bash
SUPPORT_PREVIOUS_RPM=$(ls -t "$PWD"/build/rpms/sp11-surface-support-*.rpm | head -1) scripts/36-verify-kernel-install.sh > "build/logs/step36-$NEW-rev$REV.log" 2>&1; echo "step 36 rc=$?"; sed 's/\x1b\[[0-9;]*m//g' "build/logs/step36-$NEW-rev$REV.log" | grep -cE '^\[sp11\] +ok:'; sed 's/\x1b\[[0-9;]*m//g' "build/logs/step36-$NEW-rev$REV.log" | grep -E 'FAIL|ERROR|/boot use|verified on an installed system'
```

Expected: `step 36 rc=0`; 40 checks (7.3.5 revision 4; 42 up to support 3.17, when the entry was also checked
for the two live-only arguments); the `/boot` use of the new kernel (212M on 7.3, 195M on 7.2) and `kernel
packages verified on an installed system next to <previous kernel-core>`; no `FAIL` or `ERROR` line. The one
`WARNING`, `kernel-install add returned non-zero for the previous kernel`, belongs to the chroot
(`docs/pipeline.md`, Step 36).

The signed image, on a host with the signing key: the maintainer runs step 25 in a terminal, where it asks for
the key's passphrase. In a worktree the key directory is the main checkout's; without the variable the step
logs `no Secure Boot key in <worktree>/sp11-secureboot ...: no signed boot image is built` and ends with status
0:

```bash
SECUREBOOT_KEY_DIR=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/sp11-secureboot scripts/25-build-secureboot-rpms.sh
```

Expected: `stub already built: sp11-secureboot-stub-<version>.aarch64.rpm` (the stub linked in section 4), the
passphrase prompt, `add-on RPM: sp11-kernel-secureboot-<abi>-1-1.fc<n>.aarch64.rpm (17M); image <n> bytes,
sections: ... signed` and `next: scripts/26-verify-secureboot-rpms.sh ...`. A second run signs nothing and says
`add-on already built`. Then step 26, which the session runs:

```bash
scripts/26-verify-secureboot-rpms.sh > "build/logs/step26-$NEW-rev$REV.log" 2>&1; echo "step 26 rc=$?"; sed 's/\x1b\[[0-9;]*m//g' "build/logs/step26-$NEW-rev$REV.log" | grep -cE '^\[sp11\] +ok:'; sed 's/\x1b\[[0-9;]*m//g' "build/logs/step26-$NEW-rev$REV.log" | grep -E 'FAIL|ERROR|add-on verified'
```

Expected: `step 26 rc=0`; 72 checks (7.3.5 revisions 3 and 4); `Secure Boot add-on verified with
sp11-surface-support-<version> on an installed system: sp11-kernel-secureboot-<abi>-1-1...`; no `FAIL` or
`ERROR` line.

Beyond step 20 (`ABI` is the new uname):

```bash
ABI=$NEW-$REL.sp11.$REV.fc$FR.aarch64; rpm2cpio "build/kernel/rpmbuild/SRPMS/kernel-$NEW-$REL.sp11.$REV.fc$FR.src.rpm" | cpio -i --quiet --to-stdout ./linux-kernel-test.patch > "$R/test.patch"; grep -c '^From [0-9a-f]\{40\} ' "$R/test.patch"
```

```bash
P=$R/pkg; rm -rf "$P"; mkdir -p "$P"; for p in kernel-core kernel-modules-core kernel-modules kernel-modules-extra; do (cd "$P" && rpm2cpio "../../rpms/$p-$ABI.rpm" | cpio -idm --quiet); done; ls "$P/lib/modules/$ABI/kernel/drivers/spi/" | grep geni
```

```bash
f=$(find "$P/lib/modules/$ABI" -name 'spi-geni-qcom.ko*'); xz -dcf "$f" | grep -ac 'SP11: accepting protocol 9 as QSPI controller'
```

Expected: the number of commits in the series; the module file; `1`. The same way for other adapted code
(`snd-q6apm`, `soundwire-qcom`, ...).

The module list against the previous revision's packages (`PREVDIR`: the main checkout's `build/rpms` from a
worktree, otherwise the previous hand-off folder, since step 20 deletes older builds from `build/rpms`):

```bash
PREVDIR=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/build/rpms; O=$R/pkg-prev; rm -rf "$O"; mkdir -p "$O"; for p in kernel-core kernel-modules-core kernel-modules kernel-modules-extra; do (cd "$O" && rpm2cpio "$(ls -t "$PREVDIR/$p"-[0-9]*.rpm | head -1)" | cpio -idm --quiet); done; diff <(cd "$O"/lib/modules/* && find . -name '*.ko*' | sed 's/\.ko.*$//' | sort) <(cd "$P/lib/modules/$ABI" && find . -name '*.ko*' | sed 's/\.ko.*$//' | sort)
```

Expected: only modules that Fedora's configuration change or the stable update itself adds or removes (7.2.7:
`ntfs`, and `i2c-hid-acpi-prp0001`, which 7.2.6 added); `diff` then ends with status 1. No line and status 0:
the same modules (7.3.3 revision 5 to 7.3.5 revision 1: 5723).

## 8. After the device test and the push

The pushed head and its tree:

```bash
REPO=$(git config -f .gitmodules submodule.linux-sp11.url); git ls-remote "$REPO" "refs/heads/sp11/$NEW"
```

When the maintainer signed the series in place in this checkout's submodule and pushed from there (handoff.md), the
submodule's HEAD is the pushed head: `git add linux-sp11` pins it. Otherwise fetch the pushed commit into the
submodule (the rehearsal's commits stay in its repository, unreferenced). Then `kernel_rev_sha256` (section 4) into
`KERNEL_SP11_REV_SHA256`, the revision number unchanged:

```bash
PUSHED=<the pushed head>; N=$(git -C "$R/linux" rev-list --count "v$NEW..HEAD"); [ "$(git -C linux-sp11 rev-parse HEAD)" = "$PUSHED" ] || { git -C linux-sp11 fetch -q --no-tags --depth=$((N + 1)) origin "$PUSHED" && git -C linux-sp11 checkout -q --detach "$PUSHED"; }; git add linux-sp11 && git rev-parse :linux-sp11
```

```bash
scripts/10-fetch-sources.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'SP11 patch set|ERROR'; git -C linux-sp11 rev-parse 'HEAD^{tree}'; git -C "$R/linux" rev-parse 'HEAD^{tree}'
```

```bash
scripts/20-build-kernel.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'already built|configuration =|ERROR' 
```

Expected: `SP11 patch set: <n> commits, v<new>..<head>`; two equal tree ids; `kernel RPMs already built: ...
checking them` and step 20's configuration line, no `ERROR`.

The pushed branch in the submodule, read-only: signatures, and authors, dates and messages against the tested
series (the maintainer's own new patches gain a `Signed-off-by` line, nothing else may differ):

```bash
BASE=$(sed -n 's/^KERNEL_PATCH_BASE_COMMIT="\([0-9a-f]*\)".*/\1/p' sp11.conf); git -C linux-sp11 log --format=%G? "$BASE..HEAD" | sort | uniq -c; diff <(git -C linux-sp11 log --reverse --format='%an <%ae>|%ad|%s%n%b' --date=raw "$BASE..HEAD") <(git -C "$R/linux" log --reverse --format='%an <%ae>|%ad|%s%n%b' --date=raw "v$NEW..HEAD")
```

Expected: `<n> G` (on `sp11/7.3.5` also 4 `N`: revision 4's commits, merged from a pull request on GitHub); only
`Signed-off-by` lines in the diff. Then remove the rehearsal's series from `build/cache/kernel-patches/` (every
directory but the pinned commit's). Before handing over the commit message, check that the change set applies
onto the main checkout as it is now (it may have moved since the worktree was made; the new skill or other
untracked files come on top):

```bash
MAIN=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)"); git diff > "$R/change-set.patch"; git -C "$MAIN" apply --check "$PWD/$R/change-set.patch" && echo "applies onto $(git -C "$MAIN" log --oneline -1)"
```
