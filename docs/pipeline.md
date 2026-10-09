# Pipeline
The repository's files, the pipeline and verification steps, the WSL build host, and shell pitfalls.

## Repository

- `sp11.conf`: every version, URL, regex, boot-policy string and content pin, sourced through `scripts/lib.sh`; only
  the support RPM's `VERSION=` lives in step 30.
- `rpm/*.spec.in`: the spec templates; `render()` fills their `@KEY@` placeholders, a leftover one fails the build.
- `scripts/NN-*.sh`: the pipeline steps, idempotent; `FORCE=1` rebuilds.
- `build-all.sh`: runs 00, 05, 10, 20, 30, 40, 45 and 50, then steps 35 and 46, which need step 50's live root
  (steps 30 and 45 run them when it exists).
- `70-export-bt-pairings.sh`: the pairing export (`docs/hardware.md`); `75-export-sensor-registry.sh`: the sensor
  registry export from Windows into `build/sensors/` (`docs/sensors.md`).
- `sync-state-drivers.py`: step 20's check that the Denali device tree's rail and interconnect users all have a
  driver (`docs/kernel.md`).
- `payload/`: `sp11-surface-support`'s payload, installed under `/usr/libexec/sp11`, `/etc/grub.d` and
  `/usr/lib/...`; `payload/README-iso.txt.in` is the note inside the ISO.
- `payload/kernel-local`: kernel configuration additions, a build input of step 20 and part of `KERNEL_SP11_REV`;
  the patch set is the kernel fork's, pinned by `KERNEL_PATCH_*`.
- `payload/sensors/`: `sp11-sensors`' payload, hexagonrpc's sysusers entry and udev rule, the patches of libssc
  (`libssc/`) and iio-sensor-proxy (`iio-sensor-proxy/`), the unpackaged `sp11-sam-posture` probe.
- `payload/camera/`: the unpackaged `sp11-camera-probe` and `sp11-camera-calibrate`, and the cameras' tuning files
  `imx681.yaml` and `ov13858.yaml`, which step 30 installs into `/etc/libcamera/ipa/simple/` from support 3.5 on;
  they come from a colour calibration on the device and step 30 refuses to build without them (`docs/camera.md`).
- `build/`, git-ignored: `cache/` (downloads, source RPMs, checkouts, `rpm-deps/`, the fork's partial clone
  `kernel-patches.git`, its series `kernel-patches/<commit>/`), `kernel/` (step 20's tree and logs; the build runs
  in `/var/lib/mock/<MOCK_CONFIG>-sp11-kernel`), `work/iso/` (the live root, root-owned), `rpms/`, `out/` (the
  ISO and the pairing tarball), `bt-pairings/`, `sensors/` and `hardware.env` (per-unit, private).

## Verification steps

### Step 35: the support RPM

- `35-verify-support-rpm.sh` installs the support RPM in an overlay of the live root (a real ext4 `/boot` loop,
  grub2 stubs) on both paths it reaches a machine: `dnf upgrade` (`rpm -U` with scriptlets) and the ISO build
  (`rpm -U --noscripts` plus the helper runs). After step 50 the live root carries that RPM, so the upgrade is a
  reinstall with `--replacepkgs`; `SUPPORT_PREVIOUS_RPM=<rpm>` installs that build first.
- The update path first stages a wrong GRUB policy (`GRUB_GFXMODE=640x480`, an empty `GRUB_FONT`,
  `GRUB_TIMEOUT=99`, no font in `/boot`), so a package that installs without applying the `sp11.conf` policy to
  `/etc/default/grub` and the menu fails; both paths also check the 3.x payload (dnf override,
  `scmi-cpufreq`, no FIPS omission, no 2.x or 3.1 leftover, from 3.5 the two tuning files with a `Ccm`).

### Step 36: the kernel install

- `36-verify-kernel-install.sh`, not in `build-all.sh`, installs the SP11 kernel packages (`KERNEL_PKGS`) into the
  same kind of overlay, as `dnf install` does (`rpm -i` with scriptlets, one transaction, next to the previous
  kernel), then the support RPM with `rpm -U` unless the live root carries that version, and checks the BLS entry,
  `saved_entry`, the initramfs, the menu, `kernel-local` in the shipped `config` and the `rpm -e` way back.
- After an ISO build, pass the support RPM the live root carries as `SUPPORT_PREVIOUS_RPM`: its reinstall's
  `%posttrans` writes the menu an installed system has; `20-grub.install` regenerates it only when
  `/etc/kernel/cmdline` is older than `/etc/default/grub`, and the SP11 plugin rewrites that file first.
- `kernel-install` exits non-zero in the chroot (`95-set-boot-entry.install` wants an initramfs the previous
  kernel's entry lacks), so the script judges by the entry, as the RPM's `%posttrans` does with `|| :`; that
  plugin turns `tmp_saved_entry` into `saved_entry`, so a kernel without an initramfs never becomes the default.
  Dracut's `selinux` module is in no initramfs here (`check()` returns 255); systemd loads the policy.

### Steps 45 and 46: the sensors stack

- `45-build-sensors-rpms.sh` builds `hexagonrpc`, `libssc` and `iio-sensor-proxy` with `mock --chain`
  (`mock_chain` in `lib.sh`) and `sp11-sensors` from files (`build_rpm`), always in mock so the host never gets
  unpackaged libraries; libssc's spec applies the patches of `payload/sensors/libssc/`, a change there bumps
  `LIBSSC_RPM_RELEASE`, and iio-sensor-proxy's those of `payload/sensors/iio-sensor-proxy/`, a change there bumps
  `IIO_SENSOR_PROXY_RPM_SUFFIX` (`docs/sensors.md`). It refuses a proxy without libssc or without the sleep pause.
- `46-verify-sensors-rpms.sh` installs the four RPMs into an overlay of the live root with scriptlets and the
  runtime dependencies of `SENSORS_DEPS_PKGS`, matched by capability (F45 ships `protobuf-c` as `protobuf3-c`),
  and checks the installed stack, a write as `fastrpc` and the erase; `SENSORS_PREVIOUS_RPMS="<earlier RPMs>"`
  adds the in-place upgrade.

### Step 60: the remastered root

`60-verify-rootfs.sh`, optional and not in `build-all.sh`, checks the remastered root step 50 leaves and the Denali
firmware directory, and simulates the installed system's kernel-install hand-off in a chroot: the BLS entry
must get the Denali DTB and the SP11 arguments.

### Cameras

The ISO keeps Fedora's libcamera; step 20 checks the kernel side: sensors, privacy LED, modules
(`docs/camera.md`).

## Versions and content pins

`CLAUDE.md` lists the version variables; here are rationale and enforcement.

- Support RPM: bump `VERSION=` in `scripts/30-build-support-rpm.sh` whenever the payload changes, so `dnf upgrade`
  works; its `%posttrans` must run `sp11-grub-defaults` before regenerating `grub.cfg` (up to 2.3 a changed policy
  never reached the machine), which step 35 guards.
- Input hashes: steps 30 and 45 record `inputs_sha256` (`lib.sh`; the payload, the spec template, the rendered
  `sp11.conf` values, for step 45 also the registry export and the DriverStore package) as `Inputs:` in the RPM
  description and die when the cached RPM of the same version was built from other inputs, `FORCE=1` or not.
- Kernel revision pins: `KERNEL_SP11_REV_SHA256` in `sp11.conf` pins each revision's content (`kernel_rev_sha256`
  over the revision number, the effective `kernel-local` lines and the two pinned commits); step 20 dies when
  either differs from the pin and prints the value to set after a bump.
- `IIO_SENSOR_PROXY_SRPM` pins the iio-sensor-proxy source RPM by URL and checksum, like the kernel's, to Koji's
  unsigned copy (Koji drops superseded builds' signed copies; the payloads are equal); a newer build changes the
  pin, then the template and its spec pin.

Cache checks: steps 20, 30, 40 and 45 skip when the cached RPM matches, so a bump or a release switch rebuilds;
`build_rpm`, `mock_rebuild` and `mock_rebuild_family` delete older RPMs of the same name, so `build/rpms/` holds
one release's set.

| Step | The cached RPM matches on                                                                          |
|------|----------------------------------------------------------------------------------------------------|
| 20   | the `kernel-core` RPM's version-release-arch against the configured uname, Fedora release included |
| 30   | the support RPM's `%{VERSION}` and the `.fc<release>` dist tag                                     |
| 40   | iptsd's version-release and commit                                                                 |
| 45   | the sensors chain's version-release                                                                |

## Caches and build details

- The support spec disables `__os_install_post`: `board.bin` and the Qualcomm images are ELF files rpmbuild's brp
  scripts would rewrite.
- Step 10 honours `FORCE=1` only for the two dnf-downloaded caches, `build/cache/wifi/f<release>` and
  `build/cache/rpm-deps/f<release>`; checksum-pinned downloads are never re-fetched.
- Step 50 caches the extracted live image as `build/work/iso/live.erofs`, keyed to its source ISO by the
  `live.erofs.source` stamp, and asserts the root's `VERSION_ID` equals `FEDORA_RELEASE`.
- `fetch()` in `lib.sh` resumes into `DEST.part` across attempts; curl's own `--retry` restarts from byte zero and
  never gets a multi-GB ISO through a mirror that drops transfers.

## Host

- WSL2 Fedora 44 aarch64 on the Surface itself (12 cores, 11 GiB RAM), passwordless sudo, Windows at `/mnt/c`;
  `powershell.exe` interop serves the hardware detection and the registry export.
- No Docker: the kernel and the cross-release packages build in mock buildroots of the target release; the
  kernel's root needs about 40 GiB on the same disk, hence the 80 GiB check in step 0.
- `00-setup-host.sh` installs every tool, even those the stock WSL image lacks.
- A long build must outlive the Claude Code session that starts it: run it under `setsid nohup`, watch its log.

## Shell pitfalls

- `grep -q` at the end of a pipeline fails spuriously under `pipefail` (SIGPIPE); use `grep ... >/dev/null`.
- Under `set -e -o pipefail`, `var=$(ls pattern | head -1)` exits the script silently when the glob does not
  match, like any `var=$(... | ...)` with a failing member (`grep` on no match, `find` on a missing directory);
  append `|| true` inside the substitution.
- A partial clone (`extensions.partialClone`) fetches every missing object it is asked about, with its whole
  history: a `merge-base` probe pulled 3 GB of Linux commits, a plain `write-tree` the whole kernel tree. The
  lookups run with `GIT_NO_LAZY_FETCH=1` and the series check uses `write-tree --missing-ok`.
- `bash -n A B C` parses only `A`; syntax-check files one at a time.
- `grep -v -q PATTERN FILE` cannot assert absence; use `! grep -q`.
- `findmnt -R DIR` lists submounts only when DIR itself is a mount point; `mounts_under` in `lib.sh` matches the
  target prefix instead (steps 50 and 60 refuse to `rm -rf` a tree with mounts below it).
- `pkill -f PATTERN` also kills the shell whose command line contains PATTERN; stop a build by PID (`sudo kill`
  for mock's root processes).
- Fedora's `kernel.spec` applies patches with `git apply`, which refuses the fuzz and off-by-one hunk counts GNU
  `patch` accepts: test a patch set with `git apply` on a copy of the Fedora source (`patch --dry-run` of a
  concatenated series fails spuriously when later patches build on earlier ones).
