# Pipeline
The repository's files, the pipeline steps and their verification steps, the WSL build host, and shell pitfalls.

## Repository

- `sp11.conf`: every version (but the support RPM's, `VERSION=` in step 30), URL, regex, boot-policy string and
  content pin; scripts source it via `scripts/lib.sh`.
- `scripts/NN-*.sh`: pipeline steps, idempotent, `FORCE=1` rebuilds. `build-all.sh` runs 00, 05, 10, 20, 30, 40,
  45, 47 and 50 and then `35-verify-support-rpm.sh`, `46-verify-sensors-rpms.sh` and `48-verify-camera-rpms.sh`,
  which need the live root 50 extracts (steps 30, 45 and 47 also run them themselves whenever one is already there;
  30 warns when it is not);
  `60-verify-rootfs.sh` (optional, not in `build-all.sh`) checks the remastered root; `70-export-bt-pairings.sh`
  and `75-export-sensor-registry.sh` are separate tools. `sync-state-drivers.py` is step 20's check that every user
  of the rails and the interconnect in the Denali device tree has a driver (`docs/kernel.md`).
- `rpm/*.spec.in`: templates rendered by `render()` (`@KEY@` placeholders; leftovers fail the build).
- `.claude/skills/sp11-kernel-update/`: the procedure for a new Fedora kernel as a Claude Code project skill
  (`SKILL.md`; every command with its expected output in `reference.md`; hand-off templates; the DSP ping tool
  the device steps use).
- `payload/`: payload of `sp11-surface-support` (installed under `/usr/libexec/sp11`, `/etc/grub.d`,
  `/usr/lib/...`), `README-iso.txt.in` (the note inside the ISO; it carries the redistribution warning and credits),
  `kernel-local` (configuration additions; a build input of step 20, part of `KERNEL_SP11_REV`, not part of the
  support RPM). The SP11 patch set lives in the project's kernel fork (`KERNEL_PATCH_*` in `sp11.conf`; manifest in
  `docs/kernel-patches.md`). `payload/sensors/`: payload of `sp11-sensors` (udev, systemd, tmpfiles, SELinux and dnf
  files, the helper scripts), hexagonrpc's sysusers entry and udev rule (packaged by `hexagonrpc.spec.in`), and the
  unpackaged `sp11-sam-posture` probe. `payload/camera/`: libcamera's patches, a build input of step 47 (the IMX681
  support from turbineBMW/surface-pro-11-linux, rebased onto Fedora's version; Robert Bozik's exposure control,
  backported; the project's analogue-gain bound, exposure target, tuning and GPU downscaling fix; libcamera's
  LGPL-2.1-or-later, the tuning files CC0-1.0; third-party authorship in each patch, the project's own patches carry
  no author line), and the unpackaged `sp11-camera-probe`, which measures the raw sensor output without libcamera
  (`docs/camera.md`).
- `build/` (git-ignored): `cache/` (downloads, the kernel, iio-sensor-proxy and libcamera source RPMs, pinned
  checkouts, `rpm-deps/`, the kernel fork's partial clone `kernel-patches.git` and the series written from it,
  `kernel-patches/<commit>/`), `kernel/` (the unpacked source RPM with the SP11 additions, the SP11 source RPM, step
  20's logs; the build itself runs in `/var/lib/mock/<MOCK_CONFIG>-sp11-kernel`), `work/iso/` (extracted live root,
  root-owned), `rpms/`, `out/` (ISO, `.sha256`, pairing tarball), `bt-pairings/` (exported hive; secret), `sensors/`
  (this unit's sensor registry export; private), `camera/` (step 47's unpacked libcamera sources), `hardware.env`.

## Verification steps

- `35-verify-support-rpm.sh` installs the freshly built support RPM in an overlay of the live root, with a real ext4
  `/boot` loop and the `grub2-probe`/`grub2-mkrelpath` stub, on both paths it reaches a machine: `rpm -U` with
  scriptlets over the version the live root carries (what `dnf upgrade` does; after step 50 that is the RPM under
  test, so the install is a reinstall with `--replacepkgs`, which runs the same `%posttrans` and triggers — a plain
  `rpm -U` of an installed NVR is refused, which made the step fail at the end of every `build-all.sh` until
  2026-09-22; `SUPPORT_PREVIOUS_RPM=<rpm>` installs that build first, for a real upgrade) and `rpm -U --noscripts`
  plus explicit helper runs (what step 50 does, plus `sp11-grub-modules`). It asserts that the GRUB policy values in
  `sp11.conf` (device tree, mode, terminal, timeout, font) reach `/etc/default/grub` and, on the update path, the
  generated menu (the live root has no menu). The update path first stages a deliberately wrong policy
  (`GRUB_GFXMODE=640x480`, empty `GRUB_FONT`, `GRUB_TIMEOUT=99`, font deleted from `/boot`), so a package that
  installs without applying the policy cannot pass. Verified as a negative control when the check was written: with
  the pre-2.4 `%posttrans` the update path failed seven checks while the live path still passed, which is exactly
  how the bug presented. Both paths assert the 3.x payload (the dnf repository override, the `scmi-cpufreq` load, no
  `libdnf5.conf.d` exclusion left over from 2.x, no FIPS omission, and since 3.2 no `sp11-cdsp-check` left from
  3.1), and the live path runs dnf5 in the chroot against a probe `kernel-core` RPM in a local repository: hidden by
  the override, visible with `--setopt=disable_excludes='*'`, installable as a file (`@commandline`). Passed on
  2026-09-23 for 3.0 over 2.6 and, with `SUPPORT_PREVIOUS_RPM`, over 2.7, for 3.1 over 2.6 and 3.0, on 2026-09-24
  for 3.2 over 2.6 and 3.1, and on 2026-09-26 for 3.3 over 3.2 and 2.6.
- `36-verify-kernel-install.sh` (standalone, not in `build-all.sh`: after a full pipeline run the live root already
  carries the kernel under test) installs the freshly built SP11 kernel packages (`KERNEL_PKGS`) into an overlay of
  the live root the way `dnf install` does on an installed system — `rpm -i` with scriptlets, one transaction, next
  to the kernel already there (whatever provides `kernel-core-uname-r`: `kernel-sp11` or an earlier `kernel-core`) —
  with a real ext4 `/boot` and the step-35 grub2 stubs, then the support RPM with `rpm -U` (left out when the live
  root already carries that version, as dnf leaves an installed package out of the transaction;
  `SUPPORT_PREVIOUS_RPM=<rpm>` installs that build beforehand). It asserts the packages, the BLS entry (`linux`,
  `initrd`, `devicetree /dtb-<abi>/…`, every `SP11_ARGS_INSTALLED`, no live-only argument), `saved_entry` naming the
  new entry, the previous kernel's files, the dracut initramfs (new module tree, Adreno microcode, the Denali DSP
  firmware), the regenerated menu, `kernel-local` in the shipped `config`, and that `rpm -e` of the new packages
  puts the previous kernel back. When the live root already carries the support RPM under test (after any ISO
  build), pass that RPM as `SUPPORT_PREVIOUS_RPM`: its reinstall's `%posttrans` writes the menu an installed system
  has. Without it the menu check fails, because the live root's menu is Fedora's own and `20-grub.install`
  regenerates the menu only when `/etc/kernel/cmdline` is older than `/etc/default/grub`, which the SP11 plugin's
  rewrite of `/etc/kernel/cmdline` before it never lets happen (2026-09-25). `kernel-install` exits non-zero in
  the chroot (`95-set-boot-entry.install` wants the kernel's initramfs, which the previous kernel's entry is written
  without), so the script judges by the entry, as the RPM's `%posttrans` does with `|| :`.
  `95-set-boot-entry.install` (grub2-common) is what turns `tmp_saved_entry` into `saved_entry`, so a kernel whose
  initramfs failed to build never becomes the default.
  dracut's `selinux` module is in none of these images (its `check()` returns 255: included only as a dependency or
  when added; Fedora's stock 45 Beta live initrd lacks it too) — systemd loads the policy in the real root.
- Sensors stack (see `docs/sensors.md`; `build-all.sh` runs 45 before 50 and 46 after 35 since 2026-09-22, and
  step 50 installs the four RPMs into the live root): `45-build-sensors-rpms.sh` builds `hexagonrpc`, `libssc` and
  `iio-sensor-proxy` with `mock --chain` (`mock_chain` in `lib.sh`; always mock, so the host never gets
  unpackaged libraries and iio-sensor-proxy resolves `libssc-devel` from the chain's local repo) and `sp11-sensors`
  (files only, `build_rpm`); the chain is skipped while its RPMs are current, `FORCE=1` rebuilds. When step 50's
  live root exists it then runs `46-verify-sensors-rpms.sh`: an overlay install of the four into the live root with
  scriptlets (runtime dependencies from `SENSORS_DEPS_PKGS`, matched by capability because F45 ships `protobuf-c` as
  `protobuf3-c`), linkage, units, rules, the drop-in and a guard run, the initramfs trigger (no dracut in the
  scriptlets), CIL module, sysusers, both dnf exclusions (the kernel one per repository, the proxy one in the main
  configuration), the payload and its mtimes against the registry's stamps, the working directory with a write as
  the `fastrpc` user, the daemon's strings, the wait helper's re-probe, erase; with
  `SENSORS_PREVIOUS_RPMS="<earlier RPMs>"` also the in-place upgrade from those, with the daemon's unit masked the
  way a crash loop was stopped.
  `75-export-sensor-registry.sh` is the UAC tool that copies this unit's registry and calibration overrides out of
  `DriverData\Qualcomm\fastRPC` (robocopy in an elevated PowerShell) into `build/sensors/`.
- Cameras (see `docs/camera.md`; step 50 installs the rebuild in place of Fedora's since 2026-09-28):
  `47-build-camera-rpms.sh` checks Fedora's libcamera source RPM (downloaded by step 10) against its pinned checksum
  and its spec against `LIBCAMERA_BASE_SPEC_SHA256`, rebuilds it from
  `rpm/libcamera.spec.in` with `payload/camera/` in a mock root of its own (`mock_rebuild_family`, `libcamera`), and
  checks the packages: the IMX681 in `libcamera.so` and in the simple IPA, the exposure control's tuning keys in the
  simple IPA, the whole-quad downscaling in the packed Bayer shader, every tuning file byte for byte as the patches
  leave it (their hunks applied with `git apply --include`), and every IPA module's signature against the key built
  into `libcamera.so` (`ipa_signatures_ok` in `lib.sh`; Fedora's own 0.7.2-3 fails it). `48-verify-camera-rpms.sh`
  installs `libcamera`, `libcamera-ipa` and `libcamera-tools` over the build the live root carries in an overlay
  (Fedora's before step 50 ran with the rebuild, the rebuild itself after it: a reinstall) (no extra dependency RPMs
  are needed: the Workstation root has every library `cam` links), checks the linkage of the library, the IPA, `cam`
  and PipeWire's libcamera plugin, repeats the package checks on the installed files and parses both cameras' tuning
  files with the root's Python. Step 50 takes the three RPMs, plus the rebuild of every other libcamera subpackage
  the live root carries (each requires the same release; the Workstation 45 Beta root has only `libcamera` and
  `libcamera-ipa`), refuses RPMs whose release lacks `LIBCAMERA_RPM_SUFFIX`, installs them with the other SP11 RPMs
  (they have no scriptlets), stops when a package of Fedora's build is left, and copies the three to `/sp11/rpms`;
  step 60 checks them with `rpm -V` and the IPA signatures in the remastered root.

## Versions and content pins

- Bump `VERSION=` in `scripts/30-build-support-rpm.sh` whenever the support payload changes, so `dnf upgrade` works
  on the installed system. Its `%posttrans` runs `sp11-grub-defaults` and then, when a
  `grub.cfg` exists, regenerates it. The helper call is not optional: up to 2.3 the scriptlet only ran
  grub2-mkconfig, which rebuilt the menu from the *previous* `/etc/default/grub`, so a changed policy value
  installed but never reached the machine (nothing else applies it on an installed system — the kernel-install
  plugin runs only on a kernel install, `sp11-first-boot` only once). `35-verify-support-rpm.sh` guards this. Steps
  20/30/40/45/47 skip when the cached RPM matches (the `kernel-core` RPM's version-release-arch against the
  configured uname, which carries the Fedora release; support `%{VERSION}` and the `.fc<release>` dist tag;
  iptsd version-release and commit; the sensors chain's version-release; libcamera's release with
  `LIBCAMERA_RPM_SUFFIX`), so a bump or a release switch triggers the rebuild; `IPTSD_RPM_RELEASE` in `sp11.conf`
  versions the iptsd spec. The bump rules are enforced since 2026-09-22: steps 30, 45 and (since 2026-09-26) 47
  record a hash of the payload inputs in the RPM description (`Inputs:`, `inputs_sha256` in `lib.sh`: the payload
  files, the spec template, the sp11.conf values rendered, for 45 also the registry export and the DriverStore
  package, for 47 the source RPM's name) and die when the cached RPM of the same version was built from other
  inputs, `FORCE=1` or not; an RPM built before that is accepted with a warning. Step 20 pins each kernel
  revision's content in `sp11.conf` (`KERNEL_SP11_REV_SHA256`, `kernel_rev_sha256`: the revision number, the
  effective `kernel-local` lines and the two pinned commits of the patch set) and dies before its cache check when
  they or the number differ, printing the value to set after a bump; a revision number therefore always means one
  content.
  The iio-sensor-proxy and libcamera source RPMs are pinned by name and checksum like the kernel's since 2026-09-28
  (`IIO_SENSOR_PROXY_SRPM`, `LIBCAMERA_SRPM`, each with its URL and checksum; steps 45 and 47 verify the checksum
  again). Step 10 used to download the newest build with dnf, so a Fedora update would have stopped steps 45 and 47
  at their spec pins on a fresh cache. The pinned files are Koji's copies, which are unsigned; their payload equals
  that of the Fedora-signed copies (compared when pinned; Koji drops the signed copies of superseded builds). A
  newer build is taken over by changing the pin, then the template and its spec pin.
  `build_rpm`, `mock_rebuild` and `mock_rebuild_family` delete every older RPM of the same name, so `build/rpms/`
  holds one release's set.

## Caches and build details

- The support spec disables `__os_install_post`: `board.bin` and the Qualcomm images are ELF files that rpmbuild's
  brp scripts would otherwise rewrite (`board.bin` comes out 32 bytes shorter, the Bluetooth helper loses its
  `.comment` data).
- Step 10 honours `FORCE=1` only for the two dnf-downloaded caches (`build/cache/wifi/f<release>`,
  `build/cache/rpm-deps/f<release>`); checksum-pinned downloads are never re-fetched.
- `50-build-iso.sh` caches the extracted live image as `build/work/iso/live.erofs` and keys it to the ISO it came
  from with a `live.erofs.source` stamp. An unkeyed cache silently remasters the *previous* media on a release or
  compose change; it also asserts the extracted root's `VERSION_ID` equals `FEDORA_RELEASE`.
- `fetch()` in `lib.sh` resumes into `DEST.part` across attempts. curl's own `--retry` restarts from byte zero,
  which never gets a multi-GB ISO through a mirror that drops the transfer (curl error 18).

## Host

WSL2 Fedora 44 aarch64 on the Surface itself (tested with 12 cores, 11 GiB RAM), passwordless sudo, Windows at
`/mnt/c`, `powershell.exe` interop (SMBIOS, panel and Bluetooth detection; one UAC prompt for the registry export).
No Docker; the kernel and the cross-release packages build in mock buildroots of the target release (the kernel's
root needs about 40 GiB on the same disk, hence the 80 GiB check in step 0). `00-setup-host.sh` installs everything,
including gawk, xz, openssl, cmake, dosfstools, isomd5sum and python3-hivex, which the stock WSL image lacks. A
long build must outlive the Claude Code session that starts it: run it under `setsid nohup` and watch its log.

## Shell pitfalls

- `grep -q` at the end of a pipeline under `pipefail` fails spuriously (SIGPIPE); use `grep ... >/dev/null`.
- Under `set -e -o pipefail`, `var=$(ls pattern | head -1)` exits the script silently when the glob does not match
  (`ls` fails, the assignment inherits the status). Append `|| true` inside the substitution. The same applies to
  `var=$(grep ... | sed ...)` and `var=$(... | grep -v ...)` on empty input, and to `var=$(find DIR ... | wc -l)`
  when DIR does not exist (`find` fails on a missing start point; filter with `-path` from a directory that exists
  instead).
- A partial clone (`extensions.partialClone`) fetches every object it is asked about and lacks, with that object's
  whole history: in step 10 a `merge-base` probe before the first shallow fetch of the kernel fork pulled 3 GB of
  Linux commits and trees, and a plain `write-tree` in the series check the whole kernel tree. Lookups there run
  with `GIT_NO_LAZY_FETCH=1`, and the check uses `write-tree --missing-ok` (the tree id it compares covers every
  file anyway).
- `bash -n A B C` parses only `A` (`B C` become positional parameters); syntax-check files one at a time.
- `grep -v -q PATTERN FILE` cannot assert absence (it succeeds on any non-matching line); use `! grep -q`.
- `findmnt -R DIR` lists submounts only when DIR itself is a mount point; `mounts_under` in `lib.sh` matches the
  target prefix instead. Both `50` and `60` refuse to `rm -rf` a tree with mounts below it.
- `pkill -f PATTERN` also matches the shell that runs it when its own command line contains PATTERN, and kills it;
  stop a build by PID. mock runs as root: its processes need `sudo kill`.
- Fedora's `kernel.spec` applies patches with `git apply`, which refuses what GNU `patch` accepts (fuzz, a hunk
  whose line count is off by one); test a patch set with `git apply` on a copy of the Fedora source, not with
  `patch`. A `patch --dry-run` of a concatenated series whose later patches build on earlier ones in the same file
  fails spuriously; apply for real on a copy instead.
