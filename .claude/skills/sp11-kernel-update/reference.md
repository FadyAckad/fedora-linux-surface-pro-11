# Kernel update: commands

The commands of [SKILL.md](SKILL.md), step by step, run from the checkout's root in bash. Set the values first, in
every new shell; the examples are those of the 7.2.5 to 7.2.7 update (revision 5).

```bash
OLD=7.2.5 OLDREL=300    # KERNEL_FEDORA_VERSION and KERNEL_FEDORA_RELEASE as pinned before the update
NEW=7.2.7 REL=300       # the new Fedora kernel and its release
FR=45 REV=5             # FEDORA_RELEASE; the new KERNEL_SP11_REV
FORK=""                 # the path of the maintainer's full clone of the kernel fork; ask for it
R=build/rebase          # scratch area inside the git-ignored build/
KOJI=https://kojipkgs.fedoraproject.org/packages/kernel/$NEW/$REL.fc$FR
PIN=$(git show HEAD:sp11.conf | sed -n 's/^KERNEL_PATCH_COMMIT="\([0-9a-f]\{40\}\)".*/\1/p')   # the committed pin
```

In a worktree, prepare `build/` (section 4) before the downloads of section 1.

## 1. Target and inputs

Fedora's kernel updates for the release, newest first:

```bash
curl -s "https://bodhi.fedoraproject.org/updates/?packages=kernel&releases=F$FR&rows_per_page=10" -H 'Accept: application/json' | python3 -c 'import json, sys; [print(u["title"], u["status"], u.get("date_stable") or "") for u in json.load(sys.stdin)["updates"]]'
```

Expected: lines like `kernel-7.2.7-300.fc45 stable 2026-09-23 00:15:11`; take the newest `stable` one.

The stable tags, at kernel.org and in the fork clone:

```bash
git ls-remote https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git "refs/tags/v$OLD^{}" "refs/tags/v$NEW^{}"
```

```bash
git -C "$FORK" rev-parse "v$OLD^{commit}" "v$NEW^{commit}"
```

Expected: the same two commit ids. A tag the clone lacks is the maintainer's to fetch.

Fedora's source RPM and stock `kernel-core`, and their sha256 for `sp11.conf`:

```bash
(cd build/cache && curl -fsSLO "$KOJI/src/kernel-$NEW-$REL.fc$FR.src.rpm" && curl -fsSLO "$KOJI/aarch64/kernel-core-$NEW-$REL.fc$FR.aarch64.rpm" && sha256sum "kernel-$NEW-$REL.fc$FR.src.rpm" "kernel-core-$NEW-$REL.fc$FR.aarch64.rpm")
```

The same packages as Fedora signed them (the key file comes with the host's `fedora-gpg-keys`):

```bash
KEYFILE=/etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$FR-primary; KEY=$(gpg --show-keys --with-colons "$KEYFILE" | awk -F: '/^pub/ {print tolower(substr($5, 9))}'); S=$(mktemp -d); KR=$(mktemp -d)
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
git -C "$FORK" diff --name-only "v$OLD" "$PIN" | sort > "$R/series-files.txt"; grep '^diff --git' "$R/srpm-$NEW-$REL"/patch-*-redhat.patch | awk '{print $3}' | sed 's|^a/||' | sort -u > "$R/redhat-files.txt"; wc -l < "$R/series-files.txt"; comm -12 "$R/series-files.txt" "$R/redhat-files.txt"
```

Expected: `4`; the number of files the series touches (80 at 7.2.5), and no file both touch.

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
T=$R/tarcheck; rm -rf "$T"; mkdir -p "$T/tag"; tar -xf "$R/srpm-$NEW-$REL/linux-$NEW.tar.xz" -C "$T"; git -C "$FORK" archive "v$NEW" | tar -x -C "$T/tag"
diff -r --no-dereference "$T/linux-$NEW" "$T/tag" > /dev/null && echo "same content"; diff <(cd "$T/linux-$NEW" && find . | sort) <(cd "$T/tag" && find . | sort) > /dev/null && echo "same entries"; diff <(cd "$T/linux-$NEW" && find . -type f -perm -u+x | sort) <(cd "$T/tag" && find . -type f -perm -u+x | sort) > /dev/null && echo "same executables"; rm -rf "$T"
```

Expected: `same content`, `same entries`, `same executables`.

## 2. Rebase rehearsal

The scratch clone, detached at the pinned head, with the fork commits' identity and without signing:

```bash
git clone -q --shared --no-checkout "$FORK" "$R/linux" && git -C "$R/linux" config user.name "$(git -C "$FORK" config user.name)" && git -C "$R/linux" config user.email "$(git -C "$FORK" config user.email)" && git -C "$R/linux" config commit.gpgsign false && git -C "$R/linux" checkout -q --detach "$PIN"
```

The stable commits that touch the series' files, each with the first release that has it:

```bash
cd "$R/linux" && git log --no-merges --format='%h %s' "v$OLD..v$NEW" -- $(cat ../series-files.txt) > ../stable-touching.txt; while read -r c s; do echo "$(git tag --contains "$c" --list "v${NEW%.*}.*" --sort=v:refname | head -1) $c $s"; done < ../stable-touching.txt; cd - > /dev/null
```

Which SP11 patch each of them meets (number in the old series, subject, stable commit, shared files):

```bash
cd "$R/linux" && git log --reverse --format=%H "v$OLD..$PIN" > ../series-commits.txt; n=0; while read -r c; do n=$((n + 1)); f=$(git diff-tree --no-commit-id --name-only -r "$c" | sort); while read -r s rest; do common=$(comm -12 <(echo "$f") <(git diff-tree --no-commit-id --name-only -r "$s" | sort) | tr '\n' ' '); [ -n "$common" ] && printf '%04d %s <-> %s %s: %s\n' "$n" "$(git log -1 --format=%s "$c" | cut -c1-50)" "$s" "${rest:0:40}" "$common"; done < ../stable-touching.txt; done < ../series-commits.txt; cd - > /dev/null
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

The stable changes of the subsystems the SP11 relies on (read the list; 236 commits from 7.2.5 to 7.2.7):

```bash
git -C "$R/linux" log --no-merges --format='%h %s' "v$OLD..v$NEW" -- drivers/remoteproc drivers/misc/fastrpc.c drivers/soc/qcom drivers/pmdomain/qcom drivers/interconnect/qcom drivers/clk/qcom drivers/pinctrl/qcom drivers/net/wireless/ath/ath12k drivers/bluetooth drivers/platform/surface drivers/usb/dwc3 drivers/usb/typec drivers/power/supply/qcom_battmgr.c drivers/gpu/drm/msm drivers/iommu/arm drivers/cpufreq drivers/firmware/arm_scmi drivers/firmware/qcom drivers/spi/spi-geni-qcom.c drivers/dma/qcom sound/soc/qcom sound/soc/codecs/wsa884x.c 'sound/soc/codecs/lpass-*' drivers/soundwire drivers/hid drivers/input drivers/nvme drivers/pci/controller/dwc net/qrtr drivers/rpmsg drivers/thermal/qcom drivers/iio drivers/phy/qualcomm drivers/crypto/qce arch/arm64/boot/dts/qcom/hamoa.dtsi arch/arm64/boot/dts/qcom/x1-microsoft-denali.dtsi > "$R/stable-relevant.txt"; wc -l < "$R/stable-relevant.txt"
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
git -C "$R/linux" diff --name-only "v$NEW" HEAD | sed 's|/[^/]*$||' | sort -u | grep -vE '^(include|Documentation|arch/arm64/boot/dts)|^drivers/hid/bpf' | sed 's|$|/|' > "$R/build-targets.txt"; rm -rf "$R/kbuild/drivers" "$R/kbuild/sound" "$R/kbuild/net" "$R/kbuild/arch/arm64/boot/dts"
```

```bash
make -C "$R/linux" O=../kbuild ARCH=arm64 -j"$(nproc)" prepare modules_prepare > "$R/kbuild-prepare.log" 2>&1; echo "prepare rc=$?"; make -C "$R/linux" O=../kbuild ARCH=arm64 -j"$(nproc)" $(cat "$R/build-targets.txt") > "$R/kbuild-dirs.log" 2>&1; echo "dirs rc=$?"; make -C "$R/linux" O=../kbuild ARCH=arm64 -j"$(nproc)" dtbs > "$R/kbuild-dtbs.log" 2>&1; echo "dtbs rc=$?"; grep -E 'warning:|error:' "$R/kbuild-dirs.log" "$R/kbuild-dtbs.log"
```

Expected: the `olddefconfig` override warnings for the `kernel-local` symbols, no `LOST:` line; three `rc=0`, no
`warning:` or `error:` line. `build-targets.txt` must list only kernel make targets: drop any other directory the
series touches (tools, scripts) the same way.

## 4. Pins and build directory

The revision hash for `KERNEL_SP11_REV_SHA256`, after the other `sp11.conf` edits:

```bash
bash -c '. scripts/lib.sh; kernel_rev_sha256'
```

A worktree's `build/`, from the main checkout's (hard links, so nothing is downloaded or copied twice):

```bash
MAIN=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/build; mkdir -p build/cache build/rpms build/work/iso build/logs; find "$MAIN/cache" -maxdepth 1 -type f -exec ln -f {} build/cache/ \; ; cp -al "$MAIN/cache/sp11-audio-v19c" "$MAIN/cache/wifi" "$MAIN/cache/rpm-deps" build/cache/; cp -a "$MAIN/cache/iptsd" "$MAIN/cache/oe" "$MAIN/cache/hexagonrpc" "$MAIN/cache/libssc" build/cache/; ln -f "$MAIN"/rpms/sp11-surface-support-*.rpm build/rpms/
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
KERNEL_PATCH_REPO="$PWD/$R/linux" scripts/10-fetch-sources.sh > "build/logs/step10-rev$REV.log" 2>&1; echo "step 10 rc=$?"; sed 's/\x1b\[[0-9;]*m//g' "build/logs/step10-rev$REV.log" | grep -E 'SP11 patch set|all sources present|ERROR' 
```

Expected: `step 10 rc=0`, `SP11 patch set: <n> commits, v<new>..<head>` and `all sources present`.

```bash
setsid nohup bash -c './scripts/20-build-kernel.sh; echo "STEP20-DONE rc=$?"' > "build/logs/step20-rev$REV.log" 2>&1 < /dev/null & disown
```

Wait in the background for the marker, or for the build's shell to be gone:

```bash
until grep -q STEP20-DONE "build/logs/step20-rev$REV.log" || ! pgrep -f '^bash -c ./scripts/20-build-kernel.sh' > /dev/null; do sleep 30; done; sed 's/\x1b\[[0-9;]*m//g' "build/logs/step20-rev$REV.log" | tail -4
```

Expected: `kernel <abi>: configuration = Fedora's kernel-core-<new>-<rel>.fc<n> + kernel-local; DTB compatible:
...`, then `STEP20-DONE rc=0`.

Step 36 as an installed system with the current support RPM sees it: that RPM reinstalled first, so its
`%posttrans` writes the menu such a system has (the live root's own menu is Fedora's):

```bash
SUPPORT_PREVIOUS_RPM=$(ls -t "$PWD"/build/rpms/sp11-surface-support-*.rpm | head -1) scripts/36-verify-kernel-install.sh > "build/logs/step36-rev$REV.log" 2>&1; echo "step 36 rc=$?"; sed 's/\x1b\[[0-9;]*m//g' "build/logs/step36-rev$REV.log" | grep -cE '^\[sp11\] +ok:'; sed 's/\x1b\[[0-9;]*m//g' "build/logs/step36-rev$REV.log" | grep -E 'FAIL|ERROR|/boot use|verified on an installed system'
```

Expected: `step 36 rc=0`; 42 checks (revision 5); the `/boot` use of the new kernel (195M) and
`kernel packages verified on an installed system next to <previous kernel-core>`; no `FAIL` or `ERROR` line.

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
`ntfs`, and `i2c-hid-acpi-prp0001`, which 7.2.6 added); `diff` then ends with status 1.

## 8. After the device test and the push

The pushed head and its tree:

```bash
REPO=$(bash -c '. ./sp11.conf; echo "$KERNEL_PATCH_REPO"'); git ls-remote "$REPO" "refs/heads/sp11/$NEW"
```

Put that commit in `KERNEL_PATCH_COMMIT`, then `kernel_rev_sha256` (section 4) into `KERNEL_SP11_REV_SHA256`, the
revision number unchanged, and:

```bash
scripts/10-fetch-sources.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'SP11 patch set|ERROR'; git -C build/cache/kernel-patches.git rev-parse "$(sed -n 's/^KERNEL_PATCH_COMMIT="\([0-9a-f]\{40\}\)".*/\1/p' sp11.conf)^{tree}"; git -C "$R/linux" rev-parse 'HEAD^{tree}'
```

```bash
scripts/20-build-kernel.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'already built|configuration =|ERROR' 
```

Expected: `SP11 patch set: <n> commits, v<new>..<head>`; two equal tree ids; `kernel RPMs already built: ...
checking them` and step 20's configuration line, no `ERROR`.

The pushed branch in the fork clone, read-only: signatures, and authors, dates and messages against the tested
series:

```bash
git -C "$FORK" log --format=%G? "v$NEW..sp11/$NEW" | sort | uniq -c; diff <(git -C "$FORK" log --reverse --format='%an <%ae>|%ad|%s%n%b' --date=raw "v$NEW..sp11/$NEW") <(git -C "$R/linux" log --reverse --format='%an <%ae>|%ad|%s%n%b' --date=raw "v$NEW..HEAD") > /dev/null && echo "same authors, dates and messages"
```

Expected: `<n> G`; `same authors, dates and messages`. Then remove the rehearsal's series from
`build/cache/kernel-patches/` (every directory but the pinned commit's). Before handing over the commit message,
check that the change set applies onto the main checkout as it is now (it may have moved since the worktree was
made; the new skill or other untracked files come on top):

```bash
MAIN=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)"); git diff > "$R/change-set.patch"; git -C "$MAIN" apply --check "$PWD/$R/change-set.patch" && echo "applies onto $(git -C "$MAIN" log --oneline -1)"
```
