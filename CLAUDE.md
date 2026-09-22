# CLAUDE.md — Fedora live ISO for Surface Pro 11 (5G, X1E80100, OLED)

Working notes for future sessions. Everything below was verified in September 2026 on the tested unit listed under
Target hardware. Re-verify anything that depends on a newer Fedora, GRUB, Anaconda or ooaklee release.

## Repository

- `sp11.conf`: every version (but the support RPM's, `VERSION=` in step 30), URL, regex, boot-policy string and
  content pin; scripts source it via `scripts/lib.sh`.
- `scripts/NN-*.sh`: pipeline steps, idempotent, `FORCE=1` rebuilds. `build-all.sh` runs 00, 05, 10, 20, 30, 40
  and 50 and then `35-verify-support-rpm.sh`, which needs the live root 50 extracts (step 30 also runs it itself
  whenever one is already there, and warns when it is not); `60-verify-rootfs.sh` (optional, not in `build-all.sh`)
  checks the remastered root; `70-export-bt-pairings.sh` is a separate tool.
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
  how the bug presented. The update path also seeds what an installer without SELinux leaves behind
  (`selinux=0` in `/etc/kernel/cmdline` and `GRUB_CMDLINE_LINUX`, `SELINUX=disabled`) and asserts `%posttrans` undid
  it, followed by a negative control with the config line alone, which `sp11-selinux-restore` must leave untouched.
- `36-verify-kernel-install.sh` (standalone, not in `build-all.sh`: after a full pipeline run the live root already
  carries the kernel under test) installs the freshly built `kernel-sp11` RPM into an overlay of the live root the
  way `dnf install` does on an installed system — `rpm -i` with scriptlets, next to the kernel already there — with
  a real ext4 `/boot` and the step-35 grub2 stubs, then the support RPM with `rpm -U` (left out when the live root
  already carries that version, as dnf leaves an installed package out of the transaction;
  `SUPPORT_PREVIOUS_RPM=<rpm>` installs that build beforehand). It asserts both packages, the
  BLS entry (`linux`, `initrd`, `devicetree /dtb-<abi>/…`, every `SP11_ARGS_INSTALLED`, no live-only argument),
  `saved_entry` naming the new entry, the previous kernel's files, the dracut initramfs (new module tree, Adreno
  microcode), the regenerated menu, the config policy in the shipped `config`, the sysctl file under a kernel
  without the AppArmor key, the SELinux units the first boot depends on, and that `rpm -e` of the new kernel puts
  the previous one back. `kernel-install` exits non-zero in the chroot (`95-set-boot-entry.install` wants the
  kernel's initramfs, which the previous kernel's entry is written without), so the script judges by the entry, as
  the RPM's `%posttrans` does with `|| :`. `95-set-boot-entry.install` (grub2-common) is what turns
  `tmp_saved_entry` into `saved_entry`, so a kernel whose initramfs failed to build never becomes the default.
  dracut's `selinux` module is in none of these images (its `check()` returns 255: included only as a dependency or
  when added; Fedora's stock 45 Beta live initrd lacks it too) — systemd loads the policy in the real root. The
  seeded `/etc/kernel/cmdline` and `GRUB_CMDLINE_LINUX` carry the installer's `selinux=0` with `SELINUX=disabled` in
  the config, so the previous kernel's entry is written with the argument; the checks assert the plugin removed it
  from both entries, the cmdline file and `/etc/default/grub`, restored `SELINUX=enforcing` and created
  `/.autorelabel`.
- Sensors stack (see the Sensors section; `build-all.sh` runs 45 before 50 and 46 after 35 since 2026-09-22, and
  step 50 installs the four RPMs into the live root): `45-build-sensors-rpms.sh` builds `hexagonrpc`, `libssc` and
  `iio-sensor-proxy` with `mock --chain` (`mock_chain` in `lib.sh`; always mock, so the host never gets
  unpackaged libraries and iio-sensor-proxy resolves `libssc-devel` from the chain's local repo) and `sp11-sensors`
  (files only, `build_rpm`); the chain is skipped while its RPMs are current, `FORCE=1` rebuilds. When step 50's
  live root exists it then runs `46-verify-sensors-rpms.sh`: an overlay install of the four into the live root with
  scriptlets (runtime dependencies from `SENSORS_DEPS_PKGS`, matched by capability because F45 ships `protobuf-c` as
  `protobuf3-c`), linkage, units, rules, the drop-in and a guard run, the initramfs trigger (no dracut in the
  scriptlets), CIL module, sysusers, merged dnf excludes, the
  payload and its mtimes against the registry's stamps, the working directory with a write as the `fastrpc` user,
  the daemon's strings, the wait helper's re-probe, erase; with `SENSORS_PREVIOUS_RPMS="<earlier RPMs>"` also the
  in-place upgrade from those, with the daemon's unit masked the way a crash loop was stopped.
  `75-export-sensor-registry.sh` is the UAC tool that copies this unit's registry and calibration overrides out of
  `DriverData\Qualcomm\fastRPC` (robocopy in an elevated PowerShell) into `build/sensors/`.
- `rpm/*.spec.in`: templates rendered by `render()` (`@KEY@` placeholders; leftovers fail the build).
- `files/`: payload of `sp11-surface-support` (installed under `/usr/libexec/sp11`, `/etc/grub.d`, `/usr/lib/...`),
  the live GRUB menu template, `README-iso.txt.in` (the note inside the ISO; it carries the redistribution warning
  and credits), `kernel-sp11-fedora.config`, the kernel config policy fragment, and `kernel-patches/`, the kernel
  source patches (both build inputs of step 20, part of `KERNEL_SP11_REV`, not payload). `files/sensors/`: payload
  of `sp11-sensors` (udev, systemd, tmpfiles, SELinux and dnf files, the helper scripts), hexagonrpc's sysusers
  entry and udev rule (packaged by `hexagonrpc.spec.in`), and the unpackaged `sp11-sam-posture` probe.
- The repo is public under GPL-3.0-or-later (`LICENSE`; the support RPM's `License:` tag must agree). Tracked files
  carry no per-unit identifiers: Bluetooth/Wi-Fi/peripheral addresses, firmware versions, local paths and the
  owner's name stay out of `CLAUDE.md`, `README.md`, `files/` and `scripts/`. Per-unit values live in
  `build/hardware.env`, `build/bt-pairings/`, `build/sensors/` and, inside the built RPMs,
  `/etc/sp11/bluetooth-address` and the `sp11-sensors` registry. Check before staging:
  `git grep -nE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'` must show only the `AA:BB:CC:DD:EE:FF` placeholders.
- `CLAUDE.local.md` (git-ignored, loaded by Claude Code after this file) holds the owner's private working rules and
  hand-off notes. `.gitattributes` forces LF. `.gitignore` also blocks `hardware.env`, `*.hiv`, `*.iso`, `*.rpm` and
  the pairing tarball anywhere in the tree.
- `build/` (git-ignored): `cache/` (downloads, pinned checkouts, `rpm-deps/`, `patch-<v>.xz`), `kernel/` (one source
  tree per stable version, payload, logs), `work/iso/` (extracted live root, root-owned), `rpms/`, `out/` (ISO,
  `.sha256`, pairing tarball), `bt-pairings/` (exported hive; secret), `sensors/` (this unit's sensor registry
  export; private), `hardware.env`.
- Bump `VERSION=` in `scripts/30-build-support-rpm.sh` whenever the support payload changes, so `dnf upgrade` works
  on the installed system. Its `%posttrans` runs `sp11-selinux-restore`, `sp11-grub-defaults` and then, when a
  `grub.cfg` exists, regenerates it. The helper call is not optional: up to 2.3 the scriptlet only ran
  grub2-mkconfig, which rebuilt the menu from the *previous* `/etc/default/grub`, so a changed policy value
  installed but never reached the machine (nothing else applies it on an installed system — the kernel-install
  plugin runs only on a kernel install, `sp11-first-boot` only once). `35-verify-support-rpm.sh` guards this. Steps
  20/30/40/45 skip when the cached RPM matches (kernel ABI file list, so a `FEDORA_RELEASE` switch reuses the other
  release's kernel RPM, whose payload is release-independent; support `%{VERSION}` and the `.fc<release>` dist tag;
  iptsd version-release and commit; the sensors chain's version-release), so a bump or a release switch triggers
  the rebuild; `IPTSD_RPM_RELEASE` in `sp11.conf` versions the iptsd spec. The bump rules are enforced since
  2026-09-22: steps 30 and 45 record a hash of the payload inputs in the RPM description (`Inputs:`,
  `inputs_sha256` in `lib.sh`: the payload files, the spec template, the sp11.conf values rendered, for 45 also the
  registry export and the DriverStore package) and die when the cached RPM of the same version was built from other
  inputs, `FORCE=1` or not; an RPM built before that is accepted with a warning. Step 20 pins each kernel
  revision's content in `sp11.conf` (`KERNEL_SP11_REV_SHA256`, `kernel_rev_sha256`: the revision number, the
  fragment's effective lines, each patch's diff) and dies before its cache check when the files or the number
  differ, printing the value to set after a bump; a revision number therefore always means one content
  (`KERNEL_CONFIG_REV=1` used to build revision 1 with revision 2's patch, and did so during the 2026-09-22 tests).
  `build_rpm` and `mock_rebuild` delete every older RPM of the same name, so `build/rpms/` holds one release's set;
  copy it aside (`build/rpms-fc<release>/`) before switching. The support payload is byte-identical across releases
  (2.2 fc44 and fc45 compared); only the dist tag differs.
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
No Docker. `00-setup-host.sh` installs everything, including gawk, xz, openssl, cmake, dosfstools and python3-hivex,
which the stock WSL image lacks.

## Target hardware (tested unit)

- Product `Microsoft Surface Pro with 5G, 11th Edition`, SKU `Surface_Pro_with_5G_11th_Edition_2077`, X1E80100,
  Samsung (SDC) OLED 2880x1920.
- Bluetooth and Wi-Fi addresses are per unit. `05-detect-hardware.sh` reads the Bluetooth address into
  `build/hardware.env`; the support RPM carries it in `/etc/sp11/bluetooth-address`.
- Device tree `qcom/x1e80100-microsoft-denali-oled.dtb`; the X1P LCD variant (`x1p64100-microsoft-denali.dtb`) is a
  different machine.
- Upstream regexes are written for the non-5G SKU (`Microsoft Surface Pro, 11th Edition`, SKU `_2076`) and need
  `( with 5G)?` / `(_with_5G)?`. `05-detect-hardware.sh` self-tests every regex against both SKUs and the live
  Windows values.
- stubble's `x1e80100-microsoft-denali.json` hardware IDs do not match this SKU (CHIDs computed: zero matches), so
  automatic DTB selection cannot work; the DTB is always loaded explicitly.
- Windows identity queries (`05-detect-hardware.sh`): the built-in panel is the `WmiMonitorID` instance whose
  `WmiMonitorConnectionParams.VideoOutputTechnology` is 2147483648 (internal); the controller address is
  `DEVPKEY_Bluetooth_RadioAddress` (`{a92f26ca-eda7-4b1d-9db2-27b68aa5a2eb} 1`) on the Bluetooth-class device
  `QCA_SHB\UART_H4_HMT\...`, formatted `{0:X12}`. Radios under `USB\` are skipped.

## Kernel

- ooaklee/linux_ms_dev_kit-sp11, release `sp11-qcom-x1e-7.2.0-jg-0sp11v23`, commit
  `ce78e6ebc3d70c4a316b5721a62478ca87d6cb46`, ABI `7.2.0-jg-0sp11v23-qcom-x1e`. Source tarball and debs with
  SHA256SUMS are on the OE release page. The default build adds the kernel.org 7.2.5 stable update
  (`KERNEL_STABLE_VERSION`) and SP11 revision 2 (`KERNEL_SP11_REV`: Fedora's config policy and the tablet-mode
  switch patch): ABI `7.2.5-jg-0sp11v23.2-qcom-x1e`, package `kernel-sp11-7.2.5-sp11v23.2`. Also run on the tested
  unit: 7.2.5 without a revision (`sp11v23`, 2026-09-17) and revision 1 (`sp11v23.1`, 2026-09-18).
- `python3 debian/scripts/misc/annotations --file debian.qcom-x1e/config/annotations --arch arm64 --flavour qcom-x1e --export`
  reproduces the released config exactly except `CONFIG_VERSION_SIGNATURE`. The ABI is injected with
  `CONFIG_LOCALVERSION="-jg-0sp11v23-qcom-x1e"`. Native build of a fresh tree: ~45 min on 12 cores, 7816 modules,
  same set as ooaklee's deb. A stopped build resumes where it left off (the background task dies with the Claude
  session or WSL); `FORCE=1` on a built tree takes ~5 min. Image is `arch/arm64/boot/vmlinuz.efi` (EFI zboot PE).
- Relevant config: EROFS with LZMA and xattrs as module; no `CRYPTO_FIPS`; `MODULE_SIG=y` with an ephemeral key;
  zstd modules; `FW_LOADER_COMPRESS_XZ=y`. LSM stack from `files/kernel-sp11-fedora.config`:
  `CONFIG_LSM="lockdown,yama,integrity,selinux,bpf,landlock,ipe"` (the value of Fedora's
  `kernel-aarch64-fedora.config`, f45), `DEFAULT_SECURITY_SELINUX`, `SECURITY_IPE` (inert until a policy is loaded),
  `SECURITY_APPARMOR` off, `IGH_ECAT` and `UBUNTU_ODM_DRIVERS` off. ooaklee's published config has
  `CONFIG_LSM="landlock,lockdown,yama,integrity,apparmor"` with `SECURITY_SELINUX=y` never activated (Fedora ran
  without MAC) and `CONFIG_SECURITY_APPARMOR_RESTRICT_USERNS=y`, which denies unprivileged user namespaces without a
  profile; Fedora has none, so Flatpak's bwrap failed with EPERM until
  `kernel.apparmor_restrict_unprivileged_userns=0` was shipped in `/usr/lib/sysctl.d/90-sp11.conf`. The line stays
  for those kernels, which remain installed next to the new one, prefixed `-`: `sysctl.d(5)` then logs a missing key
  at debug level instead of failing the unit.
- Fedora's `depmod -b BASE` expects `BASE/lib/modules`; the payload uses `/usr/lib/modules`, so `20-build-kernel.sh`
  uses a temporary `lib -> usr/lib` symlink.
- `KERNEL_STABLE_VERSION` (default `7.2.5` in build mode; `KERNEL_STABLE_VERSION=` builds the release as published)
  applies kernel.org's cumulative `patch-<v>.xz` (sha256 pinned in the `sp11.conf` case table) to ooaklee's source
  in a tree of its own, `build/kernel/src/linux-<commit>-stable-<v>`, stamped `.sp11-stable-<v>` only after
  `patch --batch --forward --fuzz=1` applied without a reject. `KERNEL_UPSTREAM_VERSION` stays ooaklee's base;
  `KERNEL_BUILD_VERSION`, the ABI (`7.2.5-jg-0sp11v23-qcom-x1e`) and the RPM version follow the patch
  (`kernel-sp11-7.2.5-sp11v23`; `KERNEL_SP11_REV` below appends `.<revision>` to the ABI and the release).
  `KERNEL_MODE=prebuilt` ignores the default and refuses an explicit value. `sp11.conf` also refuses a stable
  version whose `X.Y.0` base is not `KERNEL_UPSTREAM_VERSION`, so a new ooaklee release on another base fails early
  until the default is revisited.
- `KERNEL_SP11_REV` (called `KERNEL_CONFIG_REV` until revision 1, which `sp11.conf` still accepts; default `2` in
  build mode; `KERNEL_SP11_REV=` builds ooaklee's release as published, prebuilt mode refuses a value) is everything
  this repository changes in ooaklee's kernel. It applies the source patches `files/kernel-patches/*.patch` in name
  order (`apply_local_patches` in step 20, fuzz 0, into whichever tree is built: the tree keeps copies in
  `.sp11-patches/`, an unchanged set is left alone, a changed one is taken out with `patch -R --forward` newest
  first before the current set goes in, so a built tree stays built and a tree edited behind its back makes the step
  die; exercised on a scratch tree: apply, rerun, changed patch, empty revision restoring the original byte for
  byte, re-apply, tampered tree refused), and it merges `files/kernel-sp11-fedora.config` into the annotations
  export with `scripts/kconfig/merge_config.sh -m` before `olddefconfig`; `config_fragment_holds` (`lib.sh`, also
  run by step 60 on the shipped `config`) then asserts every fragment line, and `stage_common` refuses any module
  under `kernel/ubuntu/` (Ubuntu's out-of-tree drivers; `IGH_ECAT` is `default m`, so a future one would otherwise
  ship unnoticed). The revision goes into the ABI (`…0sp11v23.2-qcom-x1e`) and the RPM release (`sp11v23.2`); bump
  it with every change to the fragment or the patches: `kernel-sp11` is install-only, and a same-ABI rebuild would
  own the same `/boot` and module paths as the installed package, so RPM refuses it; a new ABI also keeps the
  previous kernel in GRUB as the fallback; the content pin above makes step 20 refuse the mismatch. `make
  kernelrelease` is a no-sync-config target and `setlocalversion`
  reads `include/config/auto.conf`, so on a built tree the ABI check needs `make syncconfig` first (step 20 does).
- Why the LSM policy is a config change and not a source change (measured 2026-09-18 against pristine kernel.org
  7.2.5, rebuilt from `linux-7.2.tar.xz` plus the pinned `patch-7.2.5.xz`): ooaklee's tree modifies 433 upstream
  files (~20.5k lines), deletes none and adds ~230 source files. 161 of the modified files are Qualcomm/Surface/DTS
  work, 45 are Ubuntu distro code (AppArmor notify/af_inet, `version_signature`, `secureboot`, integrity), the rest
  cannot be attributed without git history, which the release tarball does not carry; the touch/pen stack
  (`mshw0485_touch.c`, `drivers/hid/spi-hid/`, g6ts headers, 7.5k lines) has no upstream counterpart. Ubuntu reaches
  the machine only through the config: the packaging is never used (step 20 runs `debian/scripts/misc/annotations`,
  nothing else from `debian*/`). Ubuntu SAUCE that stays compiled under any config: `fs/proc/version_signature.o`
  (gated on `BOOT_CONFIG`, which Fedora sets too) and `drivers/firmware/efi/secureboot.o` (on `EFI`); AppArmor
  references outside `security/apparmor` are `#ifdef CONFIG_SECURITY_APPARMOR`. Fedora's own aarch64 config already
  sets every `REQUIRED_OPTS` entry but four ooaklee-only drivers (the list has 21 entries), so a Fedora-config base
  (not done) would have to re-add them explicitly and re-validate every hardware function.
- SELinux on a system that ran the AppArmor kernels: with SELinux inactive nothing labels new files (no
  `security.selinux` xattr from the kernel, no setfilecon from rpm), so everything created since the installation is
  unlabeled. Fedora handles this itself: `selinux-autorelabel-mark.service` (`policycoreutils`, enabled by preset,
  `ConditionSecurity=!selinux`) touches `/.autorelabel` on every such boot, and `selinux-autorelabel-generator.sh`
  turns the marker into a relabel plus reboot on the first SELinux boot. Booting an AppArmor kernel again afterwards
  creates unlabeled files, hence another relabel. Helpers started through `SYSTEMD_WANTS` run as
  `unconfined_service_t` under the targeted policy; the one path in `udev_t` is
  `PROGRAM="/usr/libexec/sp11-iptsd-check-device"` (`70-sp11-iptsd.rules`) opening `/dev/hidraw*` (`usb_device_t`),
  the first suspect for an AVC if the pen daemon does not start. `sp11-diag` prints `/sys/kernel/security/lsm`,
  `getenforce` and the boot's kernel AVC lines. All of this presupposes that `/etc/selinux/config` does not say
  `disabled` — see the next bullet.
- Every installation made from media whose live session had no active SELinux — every ISO built with the AppArmor
  kernels — is **installed with SELinux disabled**, not merely inactive: Fedora's `/usr/bin/liveinst` runs
  `sestatus` and, when it does not report `enabled`, starts Anaconda with `--noselinux`; the Security module then
  holds `SELINUX_DISABLED`, `set_boot_args` adds `selinux=0` to the boot arguments (`/etc/kernel/cmdline`,
  `GRUB_CMDLINE_LINUX`, every BLS entry) and `ConfigureSELinuxTask` writes `SELINUX=disabled` into
  `/etc/selinux/config`. `SECURITY_SELINUX_BOOTPARAM=y` honours `selinux=0`, so the SELinux kernel came up with
  `getenforce: Disabled` and no `selinux` in the LSM list. `/usr/libexec/sp11/sp11-selinux-restore` (support RPM
  2.5) undoes it when *both* marks are present (`selinux=0` in `/etc/kernel/cmdline` and `SELINUX=disabled`; a
  system disabled by hand carries only the config line and is left alone): it removes the argument
  (`grubby --update-kernel=ALL --remove-args=selinux=0`, plus sed on `/etc/kernel/cmdline` and `GRUB_CMDLINE_LINUX`
  for systems without grubby or entries), sets `SELINUX=enforcing` and touches `/.autorelabel`; idempotent, never
  reboots, no-op in a live session (`rd.live.image`). It runs from the kernel-install plugin, before
  `20-grub.install` writes the new entry from `/etc/kernel/cmdline`, and from the support RPM's `%posttrans` (a
  support upgrade on a system that already has the kernel), before the menu regeneration, so `update_bls_cmdline`
  rewrites every entry from the cleaned `GRUB_CMDLINE_LINUX`. Enforcing directly, no permissive stage:
  `/usr/libexec/selinux/selinux-autorelabel` switches to permissive itself for the relabel boot and reboots, and
  `SELINUX=enforcing` under an AppArmor kernel is what every live session already ran. Manual equivalent: the grubby
  command, `SELINUX=enforcing`, `touch /.autorelabel`, reboot. The manual procedure (permissive first, then
  enforcing) and the automatic path were both confirmed on the tested unit on 2026-09-19: the relabel boot happened,
  and the system has run enforcing since with no kernel AVC and the pen daemon, the Bluetooth address helper and the
  audio stack working. Media built with the SELinux kernel should not have the problem (the live session runs
  enforcing, so Anaconda keeps the default); confirmed with the first such ISO (45 Beta 1.3, kernel v23.2, support
  2.6, built on 2026-09-22 with `--mkfs-time` and the sensors stack), installed on the tested unit the same day: the
  live session ran enforcing and the installation came up enforcing, without `selinux=0` or a relabel boot.
- 7.2.5 applies to v23 without a reject (one fuzz-1 hunk in `nvme/host/tcp.c`) and touches none of the drivers
  ooaklee's SP11 patches change (GPI DMA, spi-geni, Denali DTS, `sound/soc/qcom`, soundwire, `drivers/input`,
  `platform/surface`). Against the 7.2.0 build: the same 7816 module names, byte-identical Denali DTBs, and a config
  that differs only in `VERSION_SIGNATURE` and the Allwinner `CRYPTO_DEV_SUN8I_{CE,SS}_PRNG` symbols 7.2.5 removes.
- 7.2.6 does not apply to v23. Of the 26 files with rejected hunks, 19 hold changes v23 already has (the X1 "Fix
  swapped USB QMP PHY vdda-phy/vdda-pll supplies" series, including `x1-microsoft-denali.dtsi`, and msm DP/DSI
  fixes). 7 are real conflicts with non-upstream code in v23: `remoteproc/qcom_q6v5.c` and `remoteproc_core.c`
  (v23's ADSP attach and `RPROC_AUTO_BOOT_RESTART_IF_FW_AVAILABLE` series, absent from mainline 7.3-rc3, so there is
  no reference merge; 7.2.6's `!was_running` stop condition taken as-is would skip the SMP2P stop when the
  firmware-started ADSP is restarted), `spi/spi-geni-qcom.c` (SP11 QSPI branch in `spi_geni_init`), `qdsp6/q6apm.c`
  (SP11 audio, which already fixes the same start-count bug its own way), Ubuntu AppArmor `domain.c` (different
  `aa_audit_file()` arguments), `glymur-crd.dts` and `sc8280xp.dtsi`. Skipping the rejected hunk breaks the build in
  four of them, because other hunks of the same commit apply (`rproc_attach_work`, the `out_pm` label, `stack_msg`,
  a second `pil_gpu_mem` node). A successful `patch -R --dry-run` does not prove a pure-deletion hunk is already
  applied: the AppArmor hunk passed it although the block is still there.
- Upstream 7.2.5 builds `x1e80100-microsoft-denali-oled.dtb` too, but has no `mshw0485` driver and none of ooaklee's
  Denali DTS additions (QSPI touch controller, speaker feedback and TX DMIC links, CPU idle domains, IMX681, DSP/GPU
  firmware paths), so Fedora's own kernel with a DTB is no substitute.
- `kernel-sp11` provides `installonlypkg(kernel)`, so dnf installs a new version next to the existing ones. Fedora's
  `20-grub.install` makes the added kernel the saved default when `/etc/sysconfig/kernel` has `UPDATEDEFAULT=yes`
  and `DEFAULTKERNEL=kernel-core` (the ABI contains none of `64k|auto|rt|uki`). `kernel-install remove` leaves
  `saved_entry` naming the removed entry; GRUB then boots the first one. The spec's `%preun` runs
  `kernel-install remove` unconditionally since 2026-09-17: the earlier `if [ "$1" -eq 0 ]` guard skipped it
  whenever another `kernel-sp11` stayed installed and left the BLS entry and `/boot/dtb-<ver>` behind. RPMs built
  before that (the 7.2.0 package on existing installs) keep the guard: removing one next to a newer SP11 kernel
  needs `kernel-install remove <abi>` first.
- dnf removes such a kernel on its own: `installonly_limit` is 3 and `installonlypkgs` includes
  `installonlypkg(kernel)` (both in the 45 Beta root's `dnf --dump-main-config`), so the fourth `kernel-sp11`
  install (v23.2 on 2026-09-21, next to 7.2.0, 7.2.5 and v23.1) erases the oldest in the same transaction, keeping
  the running one; with the 7.2.0 package's guarded `%preun` that leaves its BLS entry, DTB directory and initramfs
  behind, a menu entry that cannot boot. Not verified on the device from the host (`rpm -q kernel-sp11`,
  `ls /boot/loader/entries`); `kernel-install remove 7.2.0-jg-0sp11v23-qcom-x1e` cleans up after the fact. Each
  SP11 kernel keeps roughly 200 MB in `/boot` (step 36 sizes its loop at 768 MB for two); a full `/boot` makes
  dracut fail inside `kernel-install`, whose status the spec ignores (`|| :`, as Fedora does), so the package
  installs without an entry and only the transaction's output says so: `df -h /boot` before a kernel install.
- A chroot test of that path needs a real filesystem at `/boot` (an ext4 loop image; `mkfs.ext4` from the root,
  since the host has no e2fsprogs): on an overlay root `grub2-editenv` fails with
  `failed to get canonical path of overlay`, so `saved_entry` never changes. The step 60 simulation does not check
  it.

## Fedora live media

- `FEDORA_TARGET` in `sp11.conf` picks the compose family: `ga` (`releases/<n>/`), `beta`
  (`releases/test/<n>_Beta/`) or `nightly` (`development/<n>/`, needs `FEDORA_COMPOSE=<stamp>`). `FEDORA_RELEASE`
  stays the numeric release (dnf `--releasever`, `%{dist}`, cache keys); `FEDORA_MEDIA_VERSION` is the version
  string inside the ISO name (`45_Beta`). The three families name their CHECKSUM file differently — GA
  `Fedora-Workstation-<v>-<c>-<arch>-CHECKSUM`, Beta `Fedora-Workstation-iso-<v>-<c>-<arch>-CHECKSUM`, nightly
  `Fedora-Workstation-iso-<n>-<arch>-<stamp>-CHECKSUM` — so each branch spells its own out rather than deriving one
  from another. The file body is the same clearsigned BSD digest in all three, so the
  `sha256sum -c --ignore-missing` check is unchanged.
- `FEDORA_EDITION` (default `Workstation`) picks the desktop; any other value is a spin, named as in its ISO file
  name. Every spin of a compose sits under `Spins/` and shares one CHECKSUM whose product is `Spins`
  (`Fedora-Spins-44-1.7-aarch64-CHECKSUM`), hence the separate `FEDORA_PRODUCT`. Workstation names resolve exactly
  as before the switch existed. KDE is its own product (`KDE/`, `Fedora-KDE-44-1.7-aarch64-CHECKSUM`,
  `Fedora-KDE-Desktop-Live-...`) and is not covered.
- `Fedora-Workstation-Live-44-1.7.aarch64.iso`, volume id `Fedora-WS-Live-44`, built by kiwi. The live root
  `/LiveOS/squashfs.img` is EROFS (LZMA, fragments, dedupe), 2.36 GB.
- Hybrid GPT + El Torito UEFI image + appended ESP. `/EFI/BOOT/grub.cfg` does
  `search --file --set=root /boot/0x503d6c7e` then `configfile ($root)/boot/grub2/grub.cfg`. Kernel
  `/boot/aarch64/loader/linux`, initrd `/boot/aarch64/loader/initrd`, font
  `/boot/aarch64/loader/grub2/fonts/unicode.pf2` (step 50 maps `sp11-console.pf2` in beside it, lifted out of the
  live root rather than generated a second time). `xorriso ... -boot_image any replay -map ...` reproduces the
  layout; `50-build-iso.sh` reads these paths from the ISO instead of assuming them.
- Fedora's aarch64 GRUB image has `devicetree`, `gfxterm`, `loadfont`, `blscfg`, `fat`, `efi_gop`, `all_video`,
  `search_fs_uuid`, `part_gpt`, `fwsetup`, `efinet`, `net`, `boot`. It lacks `efi_uga`, `video_bochs`,
  `video_cirrus` and `chain` (Fedora builds `chain` into x86 images only).
- GRUB has no text-scale setting: `gfxterm` sizes its character cell from the loaded PF2 font
  (`calculate_normal_character_width` over ASCII 32-126 for the width, `MAXH` for the height), so a large font is
  the only way to keep the menu legible at the panel's native mode. `sp11-console.pf2` is built by step 30 with
  `grub2-mkfont -s "$GRUB_FONT_SIZE"` from DejaVu Sans Mono; at 40 pt the cell is 24x48 px, i.e. 120x40 characters
  at 2880x1920 (measured from the PF2 header, not from the point size: `MAXW` is the maximum over *all* glyphs and
  overstates the monospace advance). DejaVu is Bitstream-Vera licensed, hence the extra `License:` term and a font
  name carrying neither "Bitstream" nor "Vera". `00_header` honours `GRUB_FONT`: when set it emits
  `prepare_grub_to_access_device` plus a single `if loadfont <path>` and skips its own `unicode/unifont/ascii`
  search, so exactly one font is loaded and `gfxterm` uses it. The file must be under `/boot`: on the LUKS layout
  nothing else is readable by GRUB, and 00_header's own fallback would otherwise land on
  `/usr/share/grub/unicode.pf2`, which is not. A `GRUB_FONT` naming a missing file makes 00_header run `grub2-probe`
  on it and grub2-mkconfig fails outright, so `sp11-grub-defaults` writes an empty `GRUB_FONT=` (the supported
  opt-out) whenever the copy into `/boot/grub2/fonts/` did not happen. Verified off-hardware first: a real
  `grub2-mkconfig` (2.12-76.fc45) in an overlay of the remastered root with an ext4 loop at `/boot` exits 0 and
  emits `search --fs-uuid` + `if loadfont /grub2/fonts/sp11-console.pf2` with `set gfxmode=2880x1920,auto`.
  Confirmed on the panel by the owner with support RPM 2.5 (2026-09-18): the menu is legible with the large font;
  which mode the firmware GOP picked (2880x1920 or the `auto` fallback) was not recorded.
- `insmod NAME` resolves `$prefix/arm64-efi/NAME.mod`; on installed Fedora `$prefix` is `/boot/grub2` (set by
  `gen_grub_cfgstub`, which Anaconda calls to write the ESP stub `EFI/fedora/grub.cfg`:
  `search --fs-uuid <boot uuid>`, then `configfile $prefix/grub.cfg`). The stub names a single /boot, so a second
  Fedora installed on the same ESP takes the menu over and hides the first. Module loading works with Secure Boot
  disabled. `grub2-efi-aa64-modules` (installed by default) provides the version-matched
  `/usr/lib/grub/arm64-efi/*.mod`.
- Fedora's os-prober has no EFI Windows probe on aarch64 (`os-probes/mounted/efi/` holds only `05shell`), so
  `GRUB_DISABLE_OS_PROBER=false` never finds Windows.
- GRUB menu order follows `/etc/grub.d/` filename order; `30_uefi-firmware` emits UEFI Firmware Settings, hence the
  Windows generator is `29_sp11_windows`.
- Stock live initramfs arguments:
  `dracut --no-hostonly --no-hostonly-cmdline --install /.profile --add "dmsquash-live livenet pollcdrom" --omit multipath`;
  it includes the `fips` dracut modules, which the pipeline omits. Generate it in a chroot of the live root.
- `rd.live.check` needs an implanted ISO checksum, which xorriso remastering does not carry over, so the live menu
  has no media-check entry.
- Anaconda 44.30 and 45.22 (code read in a Fedora 44 and a Workstation 45 Beta live root; same task order in both)
  discover kernels only from `/boot/vmlinuz-*` (`live_os/utils.py`) and run
  `kernel-install add <ver> /lib/modules/<ver>/vmlinuz` for each (the 44 1.7 and 45 Beta media carry no
  `kernel-core`; see `kernel-uki-dtbloader` below). Queue order (`modules/boss/installation.py`): payload
  (`PrepareSystemForInstallationTask` writes `/etc/modprobe.d/anaconda-denylist.conf` from `modprobe.blacklist=`;
  rsync of the live root without `--delete`, excluding `/boot/loader/`, then `/boot/grub2`, `/etc/sysconfig` and
  `/usr/lib/grub` copied again without xattrs) → bootloader (`InstallBootloaderTask`: `write_defaults` truncates
  `/etc/default/grub` and sets `GRUB_CMDLINE_LINUX` to Anaconda's boot args, then grub2-mkconfig, which creates
  `/etc/kernel/cmdline`; `CreateBLSEntriesTask`: deletes every BLS entry, `kernel-install add`,
  `grub2-mkconfig -o /etc/grub2.cfg`) → configuration queue (`RecreateInitrdsTask`: `dracut -f`). Only
  `preserved_arguments` from the live command line reach the boot args
  (`clk_ignore_unused pd_ignore_unused arm64.nopauth` among them, 45.22 also `systemd.tpm2_wait`; never
  `modprobe.blacklist`, `rd.driver.blacklist` or the soundwire argument), plus `rhgb quiet` and storage arguments.
  Command lines and their output go to `/var/log/anaconda/program.log` on the installed system. Its grub2-mkconfig
  runs in a chroot with `/dev` bound but no udev database. The live root's `/etc/default/grub` never reaches an
  installation. On a BTRFS root (Fedora's default layout, with or without LUKS) `FixBTRFSBootloaderTask` runs after
  `RecreateInitrdsTask` and repeats `ConfigureBootloaderTask` and `InstallBootloaderTask`: `/etc/default/grub` is
  truncated again and grub2-mkconfig rewrites every entry's options and `/etc/kernel/cmdline` from Anaconda's
  arguments, after the kernel-install plugin ran. The entry's `devicetree` line, the initramfs and the removed
  denylist survive; the GRUB settings and the SP11-only arguments do not.
- Fedora's `10_linux` (`update_bls_cmdline`) rewrites the `options` line of **every** BLS entry from
  `root=… ro $GRUB_CMDLINE_LINUX $GRUB_CMDLINE_LINUX_DEFAULT` on each grub2-mkconfig, and rewrites
  `/etc/kernel/cmdline` when that file is missing or older than `/etc/default/grub`. `20-grub.install` reads the
  options for a new entry from `/etc/kernel/cmdline`, but first runs grub2-mkconfig when that file is older than
  `/etc/default/grub`; it writes `devicetree /dtb-<ver>/$GRUB_DEVICETREE` and copies `/usr/lib/modules/<ver>/dtb` to
  `/boot/dtb-<ver>`. kernel-install resolves `layout=other` on these systems ("Entry-token directory … not found"),
  so `90-loaderentry.install` quits and `/etc/kernel/devicetree` is never read.
- `15-sp11-surface.install` runs before `20-grub.install`: `sp11-grub-defaults` (the single writer of the
  `/etc/default/grub` policy, also used by `sp11-first-boot`, the support RPM's `%posttrans` and `50-build-iso.sh`)
  sets `GRUB_DEVICETREE` and the display settings, the plugin appends the SP11 arguments to `/etc/kernel/cmdline`
  (rewritten after `/etc/default/grub`, so 20-grub does not rerun mkconfig — unless `sp11-selinux-restore` acts,
  which edits `/etc/default/grub` last; 20-grub's sync then rewrites the cmdline and every entry from
  `GRUB_CMDLINE_LINUX`, which carried the SP11 arguments on the tested unit since its first boot, so nothing was
  lost when the restore ran on 2026-09-19; left as is) and removes the Anaconda denylist before
  Anaconda's initramfs rebuild. Anaconda's last grub2-mkconfig still strips the SP11-only arguments from the entry
  (the soundwire argument; on 44 also `systemd.tpm2_wait=0`), and on BTRFS the GRUB settings as well, so the first
  boot runs without them until `sp11-first-boot` (`grubby --update-kernel=ALL --args`, which also updates
  `GRUB_CMDLINE_LINUX` and `/etc/kernel/cmdline`, then `sp11-grub-defaults` and grub2-mkconfig) fixes both for the
  second boot. Reproduced for the non-BTRFS order in an overlay of a Fedora 44 root with real grub2-mkconfig runs (a
  `grub2-probe`/`grub2-mkrelpath` stub for the overlay root, an ext4 loop at `/boot`). The plugin does not filter
  live-only arguments; step 60 checks that no Anaconda config mentions them.

- `mkfs.erofs -Ededupe` is single-threaded in erofs-utils 1.9.4 (hours).
  `-Efragments -C1048576 --workers=N -zlzma,level=6` takes ~5 min and is only slightly larger. Use `--file-contexts`
  from the root's own SELinux policy.
- `mkfs.erofs -T` alone implies `--all-time`: every file gets the build time, and Anaconda's `rsync -t` copies
  that onto the installed system. Every ISO up to 2026-09-21 was built that way, so on the tested unit
  `ls -l /usr/bin/bash` shows the ISO's build date, Python recompiles its timestamp-checked bytecode (7985 of the
  live root's 8178 `.pyc` files) at every start of an unprivileged process, and `rpm -V` flags the times; no
  malfunction. Step 50 passes `--mkfs-time` since 2026-09-22 and asserts that `/usr/lib/os-release` keeps its
  time from the source image.
- In a chroot without udev, `lsblk` reports empty PARTTYPE/FSTYPE; use `blkid -c /dev/null -o device -t TYPE=vfat`
  and `blkid -p -s PART_ENTRY_TYPE -o value DEV` instead.
- `grep -q` at the end of a pipeline under `pipefail` fails spuriously (SIGPIPE); use `grep ... >/dev/null`.
- Under `set -e -o pipefail`, `var=$(ls pattern | head -1)` exits the script silently when the glob does not match
  (`ls` fails, the assignment inherits the status). Append `|| true` inside the substitution. The same applies to
  `var=$(grep ... | sed ...)` and `var=$(... | grep -v ...)` on empty input, and to `var=$(find DIR ... | wc -l)`
  when DIR does not exist (`find` fails on a missing start point; filter with `-path` from a directory that exists
  instead). Step 20's Ubuntu-module guard died that way on its first run.
- `bash -n A B C` parses only `A` (`B C` become positional parameters); syntax-check files one at a time.
- `grep -v -q PATTERN FILE` cannot assert absence (it succeeds on any non-matching line); use `! grep -q`.
- `findmnt -R DIR` lists submounts only when DIR itself is a mount point; `mounts_under` in `lib.sh` matches the
  target prefix instead. Both `50` and `60` refuse to `rm -rf` a tree with mounts below it.
- `%systemd_postun_with_restart NAME@.service` on a template unit is a no-op (`systemctl try-restart` rejects a name
  without instance); restart `'NAME@*.service'` explicitly.
- dracut `install_items` applies to `--no-hostonly` builds too; `50` parks the support RPM's drop-in during the live
  initramfs run and installs only the GPU zap shader.
- `rpm --noscripts` also skips triggers, so step 50 runs `sp11-ucm-apply` in the chroot itself. On a normal install,
  the support RPM's `%triggerin -- alsa-ucm` and `%triggerin -- grub2-efi-aa64-modules` also fire for its own
  installation, and systemd's RPM file triggers daemon-reload, reload udev rules and run `systemd-sysctl` (only when
  `/run/systemd/system` exists), so the spec needs no `%post`.
- Never install RPMs into the live root with `--nodeps`. Workstation Live lacks `spdlog`, which `sp11-iptsd` links
  against; a daemon that cannot load makes udev's `check-device` fail, so no `sp11-iptsd@` unit starts.
  `LIVE_EXTRA_PKGS` in `sp11.conf` lists packages to download (`10-fetch-sources.sh` → `build/cache/rpm-deps`) and
  install first; `50-build-iso.sh` runs `rpm -U --test` and `--help` on the iptsd binaries; `60-verify-rootfs.sh`
  repeats the `--test` install, `ldd`s the shipped binaries and runs `sp11-iptsd-check-device --help`.

## Fedora 45 differences (verified 2026-09-16 against 45 Beta 1.3)

- fmt 11.2.0 → 12.1.0 and spdlog 1.15.3 → 1.17.0 break the sonames `sp11-iptsd` links against (`libfmt.so.11` →
  `.12`, `libspdlog.so.1.15` → `.1.17`), so a host-built RPM cannot install into an F45 root and step 50's
  `rpm -U --test` refuses it. `IPTSD_BUILD_MODE=auto` builds iptsd in a `mock` buildroot for the target whenever
  `FEDORA_RELEASE` differs from `rpm -E %{fedora}`; `mock_rebuild` in `lib.sh` passes `--no-bootstrap-image` (no
  container pull, so podman stays out of the dependency set) and retries once with `--isolation=simple` for WSL.
  `sp11-bt-set-addr` is libc-only and `kernel-sp11` is `AutoReqProv: no`, so iptsd is the only cross-release
  package of the ISO; the sensors chain (hexagonrpc, libssc, iio-sensor-proxy) is built by mock for the target
  release as well.
- `rpm/sp11-iptsd.spec.in` must carry `BuildRequires: cmake`: meson locates Microsoft.GSL only through its CMake
  config. The host build masked this because `00-setup-host.sh` installs cmake as an iptsd build dependency.
- The boot kernel on aarch64 is owned by `kernel-uki-dtbloader`, not `kernel-core` (Workstation Live installs no
  `kernel-core` at all). Not new in 45: Koji's package list of the 44 1.7 Workstation image shows the same set
  (`kernel`, `kernel-modules{,-core,-extra}`, `kernel-uki-dtbloader`, no `kernel-core`). It provides
  `installonlypkg(kernel)` and `kernel-core-uname-r`, so dnf adds it *alongside* rather than upgrading in place, and
  its `/usr/bin/kernel-install` dependency writes the BLS entry. `files/90-sp11-dnf.conf` therefore excludes
  `kernel-uki-*` as well; the glob deliberately does not match `kernel-sp11`, which must stay installable from a
  local RPM. `kernel-tools` and `kernel-tools-libs` track the kernel version too but own nothing in `/boot` and
  cannot create entries.
- dnf5 has no `--disableexcludes` (that is the DNF4 spelling and it errors out); `disable_excludes` is a config
  option only, so the override is `dnf --setopt=disable_excludes='*' ...`. The exclusion hides packages from
  `remove` as well as install, so taking a stock kernel off the system needs it.
- Two new aarch64 dracut modules defeat the live-media policy, and `LIVE_DRACUT_OMIT` in `50-build-iso.sh` omits
  both: `devicetree-firmware`'s generic (`--no-hostonly`) path globs `$fw_dir/qcom/x1e80100/*/*/*.mbn|elf`, which is
  exactly the Denali set, and `qcom-adsp` modprobes `qcom_q6v5_pas` from a pre-udev hook. dracut ignores omit names
  it does not know, so the GA path is unaffected. `qcom-adsp` exists to solve the very USB-C reset that forces the
  live-only DSP blacklist, so adopting it could give the live session audio and battery — untested on this unit.
- `/boot/loader/entries` is `0700 root`, so an unprivileged shell cannot expand a glob inside it: the BLS cleanup in
  step 50 must run root-side (`as_root find ... -delete`). The earlier
  `as_root rm -rf "$ROOTFS"/boot/loader/entries/*.conf` was a silent no-op and shipped the source media's rescue and
  stock-kernel entries inside the image.
- The GPU probes in the initramfs (plymouth) and needs the Adreno microcode there, or early boot logs
  `failed to load gen70500_sqe.fw` until switch-root makes `/usr/lib/firmware` reachable. `qcom-firmware` ships
  `qcom/gen70500_sqe.fw.xz` and `qcom/gen70500_gmu.bin.xz`; `files/90-sp11.conf` installs both and the support RPM
  now `Requires: qcom-firmware`. With 2.0 or later the error is gone on the installed 45 Beta Workstation system.
  The live initramfs still carries only the zap shader (step 50 parks the drop-in).
- A stock kernel whose packages stay installed without its `/boot` image breaks `dracut --regenerate-all`: dracut
  111 without an output path writes `/boot/initramfs-<ver>.img` only when `/boot/vmlinuz-<ver>` exists; otherwise,
  with `/boot/efi` mounted, it falls back to `/boot/efi/<machine-id>/<ver>/initrd`, fails with `Can't write to ...`,
  carries on to the next kernel and exits non-zero. Since support RPM 2.3, step 50 erases the stock set from the
  live root with `rpm -e --noscripts` (a plain erase, so dependencies are still checked: nothing outside the kernel
  family requires those packages on 44 or 45, and `kernel-sp11`'s unversioned `kernel-uname-r`,
  `kernel-core-uname-r` and `kernel-modules-core-uname-r` provides satisfy their versioned requires, so even a
  partial erase passes; erasing `glibc` is a working negative control). The erase leaves no module tree and no
  `/boot` file behind (the depmod outputs are `%ghost`); step 50 still removes unowned leftovers and refuses any
  other module tree, so the installer only ever sees `kernel-sp11`. Systems installed from earlier media got the
  cleanup from `sp11-remove-stock-kernels.service` (support RPM 2.1 and 2.2, a one-shot with its own stamp;
  confirmed on hardware on 2026-09-16 as an upgrade to 2.1), which 2.3 no longer ships: a system older than 2.1
  needs 2.1 or 2.2 and one reboot before 2.3.

## Peripherals and userspace

- Firmware: ADSP/CDSP/GPU blobs come from this device's Windows DriverStore (`surfacepro_ext_adsp8380*`,
  `qcnspmcdm_ext_cdsp8380*`, `qcdx8380*`); Fedora's `qcom-firmware` has no Denali directory. The Denali DT requests
  exactly `qcadsp8380.mbn`, `adsp_dtb.mbn`, `qccdsp8380.mbn`, `cdsp_dtb.mbn` and the zap shader `qcdxkmsuc8380.mbn`
  (all ELF); Windows ships the DT blobs as `adsp_dtbs.elf`/`cdsp_dtbs.elf`, and the support RPM installs them under
  the DT names only. Not shipped since 2.3: the `*_dtbs.elf` copies; `*.jsn` (the kernel's pd-mapper,
  `CONFIG_QCOM_PD_MAPPER=m`, is created by `qcom_common` as the `pd-mapper` aux device and needs no files; no
  userspace pd-mapper is installed); `qcdxkmsucpurwa.mbn` (X1P zap shader); `qcvss8380.mbn` (the iris node is
  `status = "disabled"` in `hamoa.dtsi` and Denali does not enable it). Step 60 compares the Denali directory with
  the DT's `firmware-name` list.
- Audio: ooaklee `sp11-audio-v19c` topology and UCM. Its `x1e80100.conf` matcher lacks the 5G variant and is patched
  via `UCM_SP11_REGEX`. `alsa-ucm` ships `conf.d/x1e80100/x1e80100.conf` as a symlink; the support RPM replaces it
  and re-applies on an `alsa-ucm` trigger.
- Wi-Fi: WCN7850, PCI 17cb:1107, `qmi-board-id=255`; no exact `board-2.bin` entry, so the 17cb:3378 entry is
  extracted with `ath12k-bdencoder` as `board.bin`. `disable-rfkill` is in the Denali DTS. `board-2.bin` is
  identical in the F44 (20260910) and F45 Beta (20260810) `atheros-firmware` packages.
- Bluetooth address: the controller enumerates without a public address; `sp11-bt-set-addr.c` (OE commit 69f40d5)
  sets it over raw HCI management before `bluetooth.service`, triggered by udev. Upstream's `parse_mac` copies the
  printed octets in order, but the MGMT payload is a little-endian `bdaddr_t`, so the unpatched helper sets the
  byte-reversed address; `30-build-support-rpm.sh` patches `out[i]` to `out[5 - i]` before compiling. The helper
  validates the index and the address itself; `sp11-bt-apply` only maps the unit instance `hciN` to `N`.
- Pen: unmodified upstream iptsd 3.1.0 (`a83bc1232f7096f8b33b50fdbda249cd640de670`) on the kernel's HIDRAW bridge
  (`hidraw` parent `001C:045E:0C83.*`, created by `mshw0485_touch` with `ipts_hid_bridge` defaulting to on);
  integration templates from OE `userspace/iptsd-sp11`; the build needs cmake for meson to find Microsoft.GSL. The
  kernel's own "Microsoft Surface G6 Pen" input device is silent by design; inking comes from the
  `sp11-iptsd@dev-hidrawN.service` started by the udev rule.
- Live media boots with `modprobe.blacklist=qcom_q6v5_pas rd.driver.blacklist=qcom_q6v5_pas` (an ADSP restart resets
  USB-C while rooted on USB), so no audio or battery in the live session; the installed system drops those arguments
  via the kernel-install plugin and `sp11-first-boot.service`. Anaconda carries neither argument into the boot
  entry, but turns the first into `/etc/modprobe.d/anaconda-denylist.conf`, which the kernel-install plugin removes
  before Anaconda rebuilds the initramfs. (`module_blacklist=` would avoid that file, but the kernel logs it with
  `pr_err` on every load attempt.)
- Windows dual-boot: `/etc/grub.d/29_sp11_windows` + `/usr/libexec/sp11/sp11-grub-modules` (copies `chain.mod` and
  its dependency closure from `moddep.lst` into `/boot/grub2/arm64-efi`; run by the generator on every
  grub2-mkconfig and by an RPM trigger on `grub2-efi-aa64-modules`, which keeps the copy matched to the GRUB image).
  Booting Windows through this entry works on the tested unit.

## Sensors (Snapdragon Sensor Core)

- **No sensor is on a bus Linux can see.** Windows' `Sensor` class holds two ACPI stubs, `MSHW048A` (display) and
  `MSHW048B` (keyboard, "Qualcomm All-Ways Aware Sensor Platform Device", `qcSensors.dll`: a QMI/protobuf client,
  `sns_client.pb`, `sns_suid.pb`, `sns_surface_imu.pb`). The chips, from the registry JSONs: ST LSM6DSV accel+gyro
  on the SSC's I3C buses 2 (display) and 1 (keyboard), AKM AK0991x magnetometer on I2C 4/3, AMS TCS3430 ALS/colour
  on I2C 4, TMD2755 ALS/prox, LPS22DF barometer on I2C 7, all on QUP instances the ADSP's sensor framework (SSC,
  protection domain `sensor_pd` inside `qcadsp8380.mbn`, `adsps.jsn`) owns. The Denali DTS has no sensor nodes
  (`&i2c0`/`&i2c4` carry "Something @…" comments only); the T14s bit-banged LIS2DW12 is a different board.
- Kernel: nothing to change for the sensors themselves (auto-rotation needs the tablet-mode switch patch, see
  below). `CONFIG_QCOM_FASTRPC=m` with the ADSP `fastrpc` node (`hamoa.dtsi:4372`, `qcom,non-secure-domain`, hence
  `/dev/fastrpc-adsp`), `FASTRPC_IOCTL_INIT_ATTACH_SNS`, `QRTR`/`QRTR_SMD=m`, `qcom_pd_mapper` advertising
  `msm/adsp/sensor_pd` for x1e80100. Installed system only: the live session blacklists the ADSP.
- Stack (denisix/ubuntu-surface-pro-11 `SENSORS.md` reports 13 sensors working on an SP11 this way):
  `hexagonrpcd -s` attaches to the sensors PD and serves the DSP a virtual tree from `-R DIR`:
  `/vendor/etc/sensors/config` ← `DIR/sensors/config/`, `/vendor/etc/sensors/sns_reg_config` ←
  `DIR/sensors/sns_reg.conf`, `/persist/sensors/registry/registry` ← `DIR/sensors/registry/`, `/sys/devices/soc0/*`
  ← `DIR/socinfo/*` (`rpcd_builder.c`; the fork serves `/persist/sensors/registry` as a whole from
  `DIR/sensors/persist` instead when that tree has a `registry` directory, see Packaging); without `-R` it guesses
  `/usr/share/qcom/<qcom,SOC>/<first word of model>/<device>` from the DT, `x1e80100/Microsoft/denali-oled` here.
  `libssc` finds `QMI_SERVICE_SSC` (0x190 = 400) on QRTR. Upstream iio-sensor-proxy 3.9 has
  `drv-ssc-{accel,light,compass,proximity}.c` behind `-Dssc-support`; Fedora builds it `disabled` (no libssc
  package), its udev rule enables `ssc-light ssc-compass` on `fastrpc-adsp*`, `ssc-accel` is the opt-in, its unit
  already allows `AF_QIPCRTR`. Fedora's `iiosensorproxy_t` has no `qipcrtr_socket` rule, so `sp11-sensors` loads a
  CIL module; under enforcing no AVC for the stack's domains has been seen.
- Inputs. Unelevated: `DriverStore/FileRepository/surfacepro_snscfgcrd8380.inf_*` (65 JSON, `json.lst`,
  `sns_reg_config`, `golden_color_calibration.bin`, the platform files `hw_platform`=CRD, `soc_id`=615,
  `revision`=3.1, …). **Every text file there is CRLF.** `sns_reg_config`, `json.lst` and the platform files are
  shipped as LF (step 45 strips the CR, step 46 refuses one): with the Windows bytes the DSP kept the CR in the
  values it parsed and asked for `.../registry\r/sns_secure_database.bin`, so it never found its registry. The JSON
  configs (CRLF inside JSON is whitespace) and the registry files stay as Windows has them, as denisix ships them.
  Windows' `json.lst` is not exact: it names `8380_crd_tcs3430_0.json` twice and omits `sns_cal.json`, so step 45
  ships every JSON of the package and asserts the unique listed set exists (the list stays as Windows wrote it).
  Elevated only (SYSTEM/Administrators ACL, denied to WSL and unelevated PowerShell):
  `C:\Windows\System32\drivers\DriverData\Qualcomm\fastRPC\persist\sensors\registry\registry\` (the pre-parsed
  registry the framework wrote under Windows, per unit: platform data and calibration) and
  `...\fastRPC\vendor\etc\sensors\config\` (6 calibration overrides, among them `factory_color_calibration.bin`,
  `tdm_uid.bin`, `acs_multiplier.bin` and the Surface accel/gyro calibration JSONs, which replace the package's
  copies); step 75 exports both. Windows keeps two more files in the registry's **parent** directory,
  `sns_reg_version` (9 bytes, `version=1`, no line ending) and `parsed_file_list.csv` (CRLF, written by the DSP
  itself, kept byte for byte); step 75 exports them with the entries and step 45 moves them to the payload's
  `sensors/registry-parent/` (served among the entries, the DSP deleted them as stale and tried to create
  `sns_reg_version` again). `Start-Process -Verb RunAs` on a cancelled UAC prompt returns no process object, so
  `exit $p.ExitCode` is 0: steps 70 and 75 treat that as failure explicitly, with the status caught on the pipeline
  itself (`… | sed >&2 || rc=$?`): under errexit and pipefail a `$PIPESTATUS` check after a failed pipeline is never
  reached (75 exited without its message until 2026-09-22). Both derive the Windows temp directory from
  `$env:USERNAME`, which names the profile directory on this unit; a renamed account would not, and the die says so.
- What the framework does when the file server attaches (the daemon's request log, `-Dhexagonrpcd_verbose=true`, run
  under `stdbuf -oL`: the log is on stdout, which is fully buffered on the journal socket otherwise). It asks for
  `oemconfig.so` (refused; not needed: the framework parses the JSONs itself, contrary to denisix's note that the
  JSON path needs that Android-only library), reads `sns_reg_config`, stats and reads the whole
  `sns_secure_database.bin` (75 reads of 512 plus 121 bytes = 38521, the exported file's size) and lists the
  registry. With every configuration file's modification time equal to the stamp its `sns_reg_config` entry recorded
  (62 of the 65 DriverStore JSONs and the two Surface calibration overrides match their Windows file times to the
  second; the overrides are what the framework parsed, not the DriverStore copies) it keeps the registry; with none
  matching (the payload's build times) it removed the secure database and every entry (341 `remove(` lines) and
  re-parsed the configuration, hence the payload keeps Windows' mtimes. A partial mismatch has not been seen. Then,
  within a second, the writes Windows makes on every boot: the `DIR` marker (3 bytes, part of the Windows export; a
  write test must not use that name), `parsed_file_list.csv` (15817 → 15478 bytes) and the entries
  `sns_ccd.json.ccd_te0_sensor0` (815 bytes) and `qsh_camera.dbg_flags` (295 bytes) through a temporary `fstempfile`
  in the registry's parent renamed into place (in the Windows export those two carry the date of the last Windows
  boot, the other `sns_ccd`/`qsh_camera` entries 2026-06-02: Windows rewrites them on every boot too), and
  `sns_secure_database.bin` (38521 bytes in 512-byte writes, above the 256 bytes the listener inlines; once in round
  5, three times per boot since). The `DIR` marker and the secure database are written in place. A healthy log has
  no `Unsupported`, `Refusing` or `Large` line. Refused with ENOENT and passed over: `sns_tppe.so` (hexagonrpcd
  supplies no DSP libraries) and `c:/Data/test/cam_registry_dump.txt`. A refused registry write aborts the whole
  ADSP. Upstream's daemon quits on method 24 (`apps_std_fremove`, sc `0x18020000`: 2 in, 0 out) and refuses
  `fopen(.../registry/registry/DIR, w)` (`Tried to open ... for writing`); the refusal gave `fatal error received:`
  `err_qdi.c:1205:EF:sensor_process:0x4:sns_registry_4:0x67:sns_registry_sensor.c:279:SNS_RC_SUCCESS == rc`,
  `crash detected in adsp` and a recovery in 5 s that took the CDSP down as well; the node reappeared, udev started
  the unit again, and so on every 5 s, with the battery indicator flapping (battery status comes over pmic_glink
  from the ADSP). Stopped with `systemctl mask --now`, removing the package, `dracut -f` and a reboot. Upstream's
  listener also quits on the first input buffer over 256 bytes (`Large (>256B) input buffers aren't implemented`,
  exit 0, which `Restart=on-failure` does not restart; the sensors keep running on the DSP). The framework repeats
  its registry work on the next attach until one attempt completes; after that, re-attaches (after a resume, the
  ADSP stays up through suspend) make no file request. The ADSP itself boots in the initramfs (the PAS driver's
  `RPROC_AUTO_BOOT_RESTART_IF_FW_AVAILABLE` restarts the UEFI-started ADSP with the Linux firmware at probe time,
  "restarting adsp with new firmware", and dracut's `qcom-adsp` pre-udev hook loads the driver there, before the
  LUKS prompt), but `/dev/fastrpc-adsp` appears only with the root's udev (16–25 s into the boot), and the framework
  does its registry work on that first root-side attach (the attach follows the node by ~0.6 s, the writes come
  within a second). An initramfs attach (sp11-sensors 1.1 and 1.2) is refused with
  `Could not attach to FastRPC node` until the sensors PD is up (the first came 20 ms after "adsp is now up") and is
  not needed, so it has been dropped; one boot with it hung at a black screen before the LUKS prompt, never
  explained (a hung boot leaves no journal). The QMI service 400 is registered as soon as the framework starts,
  registry or not, so readiness is a reading (`ssccli --sensor light`; without a working file server every request
  ends in "'registry' sensor timed out after 30s, is hexagonrpcd running?"); `ssccli` hangs in its synchronous
  registry lookup before its own `--timeout` applies, so it runs under `timeout`.
- Packaging: `hexagonrpc` 0.5.0 from the project's fork (`HEXAGONRPC_REPO` github.com/FadyAckad/hexagonrpc, branch
  `sp11-sensors` = upstream 598b591 plus five commits, pinned by `HEXAGONRPC_COMMIT`; `git_pin` fetches the commit
  by full hash, which GitHub serves for any reachable commit). The commits: hexagonfs
  create/write/truncate/unlink/rename for mapped directories; `apps_std` `fopen` 0, `fwrite` 5, `fsync` 23,
  `fremove` 24, `ftrunc` 32, `frename` 33 (ids from quic/fastrpc `inc/apps_std.h`; the extended ids above 30 travel
  in the first prim word), and `fopen_with_env` opening `w`/`a`/`+` modes read-write and accepting absolute names
  with unknown search variables; unsupported requests answered by `invoke_requested_procedure` with
  `AEE_EUNSUPPORTED` and empty output buffers instead of ending the session; input buffers longer than 256 bytes
  fetched with `adsp_listener_get_in_bufs2` (method 5 of the interface, quic/fastrpc `inc/adsp_listener.h`; the
  first 256 bytes arrive with `next2`, the rest from offset 256 as `listener_android.c` does); the builder mapping
  `/persist/sensors/registry` as a whole to `DIR/sensors/persist` when `DIR/sensors/persist/registry` exists
  (otherwise the upstream layout); and fixes found in review (`hexagonfs_close` destroying a descriptor while a
  second file number still referenced it, `fastrpc_apps_std_deinit` ascending from the root,
  `hexagonfs_mapped_or_empty_ops` pointing the write operations of an absent mapped directory at code that
  dereferences NULL instead of returning `-ENOENT`, zero-length output buffers padded in `outbufs_calculate_size`
  that `outbufs_encode` never writes, the method id of extended methods in `alloc_outbufs4`, `+` implying `O_CREAT`,
  `stat` claiming the write bit for read-only files, a short `write(2)` reported as an error). The spec builds with
  `-Dhexagonrpcd_verbose=true`, runs upstream's three unit tests in `%check` (two of them compile the changed files:
  `iobuffer.c`, and `hexagonfs.c` with `hexagonfs_mapped.c`), moves the units meson puts under libdir
  (`/usr/lib64`), and adds the `fastrpc` sysusers entry and a `GROUP=fastrpc, MODE=0660` rule for `fastrpc-*`
  (`sscregistrygen` is built but not installed upstream). Release `<n>.git<hash>.sp11`: the number must rise with
  every change, rpm compares `git<hash>` as a string. `libssc` 0.4.4+ (`libssc.so.2`; meson declares the QMI mock
  server unconditionally: `python3-devel`, `protobuf-compiler` for `protoc`, `protobuf-c-compiler` for
  `protoc-gen-c`; the spec deletes the installed mock server; Codeberg serves `git fetch --depth 1 origin <sha>`
  only with the full hash). `iio-sensor-proxy` = Fedora's SRPM of the target release with `-Dssc-support=enabled`,
  release `<fedora>.sp11.1` (step 45 refuses an SRPM with patches, and since 2026-09-22 one whose spec differs from
  the copy the template was made from, `IIO_SENSOR_PROXY_BASE_SPEC_SHA256`: refresh the template, then the pin).
  `sp11-sensors`: payload under `/usr/share/qcom/x1e80100/Microsoft/denali-oled` (the DriverStore package's 65 JSONs
  and `golden_color_calibration.bin`, its `json.lst`, `sns_reg_config` and platform files converted to LF, plus this
  unit's registry of 343 entries, its two parent-directory files and 6 calibration overrides from
  `vendor\etc\sensors\config`; `files/sensors/` installs elsewhere) with Windows' modification times (`install -p`,
  `source_date_epoch_from_changelog 0` and `clamp_mtime_to_source_date_epoch 0` in the spec; the JSONs carry their
  own times, 1747743181 to 1747743185, the Surface calibration overrides 1789827151, the registry's stamps; step 46
  compares two of them).
- Runtime design: udev `SYSTEMD_WANTS` on the `fastrpc-adsp` misc device starts `hexagonrpcd-adsp-sensorspd.service`
  and `sp11-sensors-online.service` (the stock `[Install]` stays unused: the node exists only after the ADSP
  booted); the same rule adds `ssc-accel` to `IIO_SENSOR_PROXY_TYPE` and sets `ACCEL_MOUNT_MATRIX`. The daemon's
  drop-in: `-R /var/lib/sp11/hexagonrpc`, `stdbuf -oL`, `ExecCondition=+sp11-sensors-guard`, `Restart=on-failure`,
  `RestartSec=5`, `StartLimitBurst=4` per 5 min. The guard refuses an attach once `crash detected in adsp` is in the
  boot's kernel log and after 12 attaches per boot (count in `/run/sp11-sensors/attaches`; resume restarts count
  too, and after a refused one the sensors keep running on the DSP without the daemon), with exit 3; it must be a
  condition: `RestartPreventExitStatus=` covers the main process only, and on the host's systemd 259 an
  `ExecStartPre` exit 3 was restarted four times until the start limit, while an `ExecCondition` exit 1-254 skips
  the unit without a failure (`Skipped due to 'exec-condition'`); step 46 asserts the drop-in has neither setting.
  The daemon serves `/var/lib/sp11/hexagonrpc` (tmpfiles): links to the package's `sensors/config`,
  `sensors/sns_reg.conf` and `socinfo`, and `sensors/persist/` (`fastrpc`-owned, the DSP's
  `/persist/sensors/registry`) with a `C`-copy of the registry in `persist/registry/` and of the two
  parent-directory files beside it; `C` keeps the mtimes. `sp11-sensors-reset` rebuilds the copy, effective at the
  next boot (the framework reads its registry once per ADSP boot). The tmpfiles run is in `%posttrans`, not `%post`:
  on an upgrade `%post` runs while the previous release's payload is still in place and the copy took stale files
  along (caught by step 46's upgrade section); `%posttrans` also removes the 1.3/1.4 copy at `sensors/registry`. A
  `%triggerpostun -- sp11-sensors < 1.3` regenerates the running kernel's initramfs when a 1.1/1.2 package is
  upgraded away, which takes their hook (`95sp11-sensors`) out (hence the spec's `Requires: dracut`); 1.3 to 1.9 ran
  that dracut in `%posttrans` on every install. `sp11-sensors-resume.service` restarts the daemon
  `After=suspend.target` (the stock unit has
  `Conflicts=suspend.target`, and nothing restarts a conflict-stopped unit; `sleep.target` is the wrong anchor, it
  is active before the suspend). `sp11-sensors-wait` (the online unit, `TimeoutStartSec=5min`) waits for a light
  reading and then hands iio-sensor-proxy what its own probe missed without restarting it (see the compass bullet
  below). `91-sp11-sensors.conf` excludes `iio-sensor-proxy`; libdnf5 appends `excludepkgs` across drop-ins
  (verified with `dnf --dump-main-config` in the 45 Beta root: kernel list plus iio-sensor-proxy), and the exclusion
  also filters a local RPM of the package ("from @commandline is filtered out by exclude filtering"): the four RPMs
  go in one transaction, a later SP11 build of the proxy needs `--setopt=disable_excludes='*'`.
- In the ISO since 2026-09-22: step 50 installs the four RPMs into the live root with `--noscripts` and applies the
  scriptlet effects itself (`systemd-sysusers hexagonrpc.conf`, `semodule -i sp11-sensors.cil`,
  `systemd-tmpfiles --create sp11-sensors.conf`, all in the chroot with `/dev`, `/proc` and `/sys` bound), asserts
  the user, the module, the fastrpc-owned registry copy and a live initramfs without the stack, and puts the RPMs
  under `/sp11/rpms`. The live session never starts hexagonrpcd or the online unit (no `fastrpc-adsp` node while the
  ADSP is blacklisted), and the SSC iio-sensor-proxy without sensors behaves as the stock build; Anaconda's rsync
  carries the policy store, `/etc/passwd` with `fastrpc` and the registry copy, so the installed system runs the
  stack from its first boot. Step 46 installs with `--replacepkgs` (a reinstall after step 50) and the previous
  release with `--oldpackage`; step 60 checks the packages, the user, the module, the copy's mtime and the
  initramfs. The 45 Beta Workstation root provides every runtime dependency (`protobuf3-c` for `protobuf-c`);
  step 50 tests them by capability and installs missing ones from `build/cache/rpm-deps`, as it does for iptsd's.
- ADSP safety: nothing in the stack writes `/sys/class/remoteproc/*/state` (step 45 greps the stage for it;
  `sp11-sensors-check` only reads it). hexagonrpcd only attaches to the existing sensors PD (`INIT_ATTACH_SNS`),
  never creates a PD (`-c`) nor supplies DSP libraries (`dsp/` absent → empty), and serves the files taken from
  Windows (the control files converted to LF) and the registry copy the DSP itself rewrites. Its exit leaves the
  sensors running on the DSP. Stopping the ADSP through remoteproc resets the SoC (denisix).
- `sp11-sensors-check` (also run by `sp11-diag`): boot timeline, crashes per remote processor, the daemon's status
  and memory breakdown, a summary of the DSP's writes, removals, renames and refusals with the log's head and tail,
  the files the DSP wrote measured against `/run/sp11-sensors/attaches`, one `ssccli` reading per sensor,
  iio-sensor-proxy and `monitor-sensor`, SELinux, and a tablet-mode section (switch input devices, the aggregator's
  modules and kernel lines, libinput capabilities, `HasAccelerometer`, mutter's `PanelOrientationManaged` asked on
  the logged-in user's session bus with `runuser`/`gdbus`, so run it with `sudo` from a terminal in the desktop,
  connected Bluetooth devices; `libinput-utils` is optional).
- Orientation: the Sensor Core reports the Android convention (the reaction force in the display frame: x right, y
  up, z out of the screen; upright on the kickstand it read x=+0.77, y=+7.39, z=+6.35 m/s²; libssc's matrix from the
  SSC placement attribute is all zeros, so identity), while iio-sensor-proxy's `test-orientation.c` wants y<0 for
  normal, x>0 for left-up and `tilt_calc` z>0 for face-up. `ACCEL_MOUNT_MATRIX="-1,0,0;0,-1,0;0,0,1"` on the node:
  the proxy reports `normal` upright (`bottom-up` without the matrix), and on the desktop the picture follows the
  device to each side and upside down.
- Auto-rotation needs tablet mode. From the sources Fedora 45 ships (gnome-shell 51~beta, mutter 51~beta, libinput
  1.31): the quick toggle (`js/ui/status/autoRotate.js`) is visible iff `SystemActions.can-lock-orientation`, which
  is mutter's `panel-orientation-managed` (`js/misc/systemActions.js`); mutter (`meta-monitor-manager.c`) sets it to
  `touch mode && has accelerometer && built-in monitor`; the accelerometer is iio-sensor-proxy's `HasAccelerometer`;
  touch mode (`meta-seat-impl.c`, `update_touch_mode`) needs a touchscreen, then a **tablet-mode switch** decides
  when one exists, and without a switch it is on only while **no pointer device** exists (keyboards do not count).
  The touchscreen is `Microsoft Surface G6 Touch`; the Flex Keyboard's touchpad is a pointer attached (Surface
  Aggregator HID `045E:0C8B/0C8E/0C8D`) and detached (Bluetooth LE `Surface Pro Flex Keyboard`, which stays
  connected), so everything depends on the switch. `surface_aggregator_registry.c` matches `microsoft,denali` to
  `ssam_node_group_sp11`, which upstream (mainline too, checked 2026-09-21) gives the **KIP** cover switch
  (`ssam_node_kip_tablet_switch`, `ssam:01:0e:01:00:01`, `surface_aggregator_tabletsw.ko`, cover states
  disconnected/closed/laptop/folded-canvas/folded-back/book, tablet for disconnected, folded and book). On this
  firmware that device exists ("Microsoft Surface KIP Tablet Mode Switch", `EV=21`, `SW=2`) but stays at laptop: the
  driver reads the KIP cover state (0x0e/0x1d) once at probe and then waits for KIP event cid 0x1d, which never
  comes (KIP events arrive only with cid 0x2c, 9-byte payloads of unknown meaning). The aggregator reports every
  keyboard change as a **POS** event (tc 0x26, tid 0x01, cid 0x03, iid 0, 12-byte payload: source, previous posture,
  new posture as le32; one source, id 0, the type cover): 03 laptop attached, 01 disconnected (with or without
  Bluetooth), 05 folded back, 04 folded canvas, and 00, not in the driver's enum, for about 3 s while the keyboard
  is being attached (logged once as `unknown device posture for type-cover: 0`, reported as tablet, the mode the
  device is already in). Found with `files/sensors/sp11-sam-posture` (python3, not packaged): it talks to the
  aggregator through `/dev/surface/aggregator` (`surface_aggregator_cdev`, `CONFIG_SURFACE_AGGREGATOR_CDEV=m`; the
  module creates its own platform device on load and binds the controller; ioctl `SSAM_CDEV_REQUEST` = `0xc028a501`,
  a 40-byte packed request with the response through a user buffer; notifier register/unregister and event
  enable/disable with the SAM event registry `0x01/0x01/0x0b/0x0c`), sends the drivers' own read-only queries (KIP
  cover state, POS sources 0x26/0x01 and posture per source 0x26/0x02), reads the kernel switch with `EVIOCGSW` and
  prints every KIP/POS event with `--watch N`. The fix, SP11 kernel revision 2:
  `files/kernel-patches/0001-surface-aggregator-registry-sp11-pos-tablet-switch.patch` puts
  `&ssam_node_pos_tablet_switch` (`ssam:01:26:01:00:01`, the node the Surface Pro 12" group uses) in place of the
  KIP node, replacing rather than adding it: libinput pairs every tablet-mode switch with the internal keyboard and
  touchpad, so a second, static KIP switch left in tablet state from a detached boot would keep the attached
  touchpad suspended. Result on the device: "Microsoft Surface POS Tablet Mode Switch" reports SW_TABLET_MODE 1
  detached or folded back and 0 attached, `PanelOrientationManaged` is true when folded, GNOME offers the
  auto-rotate button with the keyboard folded back or detached, and libinput switches the keyboard and touchpad off
  while the keyboard is folded back (the aggregator's devices sit on `BUS_HOST` and count as internal). `gpio-keys`
  also carries a lid switch (`SW=1`).
- The compass in iio-sensor-proxy: libssc builds it from the DSP's `rotv` (rotation vector) fusion sensor, which the
  framework publishes a few seconds after the physical sensors, and the proxy probes the SSC sensors once, on the
  udev "add" of the node, 0.6–0.7 s after the attach. At that probe the compass was missing on three of six boots
  checked (rounds 7, 10 and 11; rounds 5, 8 and 12 had it) while `ssccli --sensor compass` streamed. Restarting the
  proxy (1.8) brought it back, but the CDSP asserted 58 ms into that restart; a restart also drops every client's
  claim, and a proxy whose probe finds nothing exits. Since 1.9 the helper sends the proxy a synthetic uevent
  instead, `udevadm trigger --action=add --settle /sys/class/misc/fastrpc-adsp`, until the proxy reports
  `HasAccelerometer`, `HasAmbientLight` and `HasCompass` (object `/net/hadess/SensorProxy/Compass`, interface
  `net.hadess.SensorProxy.Compass`), polling for 3 s after each event and waiting 2, 4, 8, then 16 s between them,
  within 120 s (the limit is checked before the back-off sleep, so one more event can follow it): iio-sensor-proxy
  3.9's `sensor_changes` answers an `add` by probing, for each sensor type it lacks,
  the first driver that matches the device (one type per event) and leaves existing sensors and their clients alone,
  and its SSC discovery only looks the sensor up (libssc `*_new_sync` plus `*_close_sync`, no stream enabled). On
  the host's systemd 259 a synthetic `add` for a device that is already there starts the device's `SYSTEMD_WANTS`
  units again (a oneshot ran once per event), while events sent from inside that oneshot merged with its own job
  (three tries, one run each, also with the trigger as its last command); so the helper sends the event only while
  hexagonrpcd and the proxy are active, and starts a proxy that is not running instead of restarting one. Exercised
  against stubs (eight scenarios) and step 46, which asserts that the helper sends the event and restarts or stops
  no unit (a check 1.8's helper fails). Not needed on the device yet: on the 1.9 boot the proxy's own probe had the
  compass.
- Known issues. The CDSP firmware asserts (`sleep_statsi.c:537`, recovered in 0.1–0.2 s, once in 5 s) around sensor
  streams starting or stopping on the ADSP: 5 s after the ADSP crash of round 3; 130 ms and 58 ms into the two
  boot-time proxy restarts (rounds 4 and 11), which close every stream at once; about a second after a check closed
  its magnetometer stream and opened the compass (round 7); during the checks and folding tests of rounds 8 and 10
  (595.9 s and 294.9 s). Boots without a proxy restart had none at boot. Nothing on Linux uses the CDSP
  (`/dev/fastrpc-cdsp` has no client) and no stream was interrupted; tracked, not fixed. systemd reports 622–638 MiB
  for hexagonrpcd after each boot's first attach (0.2 MiB after a resume's re-attach): `memory.stat` shows it as
  `file` (634 of 635 MiB; `anon` 144 KiB, the process's RSS 1.4 MiB, no `apps_mem` map request), page cache pulled
  in by the guard's `journalctl -k -b -g`, which runs in the unit's cgroup and reads every journal file. On the
  host, with the page cache dropped, that command in a transient unit was charged 889 MiB for a 936 MiB journal and
  took 1.3 s, as did `journalctl -k -b | grep` and `journalctl -b _TRANSPORT=kernel | grep` (1.2–1.7 s);
  `dmesg | grep` was charged 3.4 MiB and took 21 ms. Reclaimable, so left as it is: reading the ring buffer instead
  (256 KB, `LOG_BUF_SHIFT=18`) would change the crash-loop guard, whose refusal path the device cannot exercise
  without an ADSP crash. The boot clock runs two hours behind until NTP corrects it (the initramfs's kernel lines
  carry the right time, the root's are two hours behind): systemd's "since … ago", early file times and
  `find -newer` against files written later are off, so the check measures the DSP's writes against
  `/run/sp11-sensors/attaches`, which the same clock stamped.
- Upstream state (checked 2026-09-19 against linux-msm/hexagonrpc): no pull request carries these changes. PR #21
  (z3ntu, draft since 2026-03-20, for issue #19 "Support opening files for writing", the same
  `.../registry/registry/DIR` refusal) stubs `fwrite` (accepts the `DIR` marker and a `version=` string, nothing
  reaches disk), mocks `fremove`, hard-codes `fopen_with_env_fd`, and adds an `sns_reg_version` mapping in the
  registry's parent; it conflicts with main since the interface rework (PR #13). psacal reports there (SC8280XP,
  Windows firmware) that the DSP creates `sns_reg_version` through method 5 when it is missing and that a
  JSON-format `sns_reg_config` makes it "generate oversized messages", i.e. the large input buffers. Maintainer
  guidance (lumag): real writes belong in a writable directory under `/var`, attempts to modify `/usr/share/qcom`
  should fail loudly; the fork does that (writes go into the `-R` tree, the package stays read-only). Nobody else
  implements the large-buffer fetch, the temporary file's directory or `ftrunc`/`frename`/`fsync`: none of
  upstream's 14 forks carries write support beyond PR #21's branch, and denisix only mentions a private patch
  ("method 24 stub", "write support"); main has not moved past 598b591. The fork was created on 2026-09-19 at
  598b591 and its `sp11-sensors` branch pushed on 2026-09-20; its commits carry the owner as author and committer
  and no other trailer. Owner's decision: fork only for now, no pull request yet.
- Device history on the tested unit (Fedora 45 Beta install, SELinux enforcing throughout):
  - 2026-09-19, rounds 1–4: 1.0 attached safely (both remote processors up through two suspend/resume cycles, audio
    unaffected) but the registry never reached the DSP (the CRLF defect); a refused registry write ended in the ADSP
    crash loop (1.2); with write support (hexagonrpc 0.5.0-2, 1.4) the first sensor data, with the orientation
    inverted, a re-parse on every boot and the daemon quitting on the first large write.
  - 2026-09-20, rounds 5–6: hexagonrpc 0.5.0-3 and 1.6: the registry accepted without a re-parse, every write
    served, no ADSP or CDSP crash, orientation `normal`, all five sensors; round 6 rebuilt the same code from the
    fork (`.text` byte-identical to 0.5.0-3).
  - 2026-09-21, rounds 7–12: hexagonrpc 0.5.0-6's write-path fixes held, also through three suspend/resume cycles;
    the tablet-mode diagnosis (1.7's check in four keyboard states, `sp11-sam-posture`) and kernel revision 2 with
    the POS switch; 1.8 and 1.9 for the compass; auto-rotation confirmed on the desktop.

## Bluetooth dual-boot pairings

- Windows keeps LE bonds in `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys\<adapter>\ <device>`:
  `LTK` (16 B), `KeyLength`, `ERand` (QWORD, little-endian → BlueZ `Rand` decimal), `EDIV`, `IRK`, `AddressType` (1
  = random), `AuthReq` (0x04 MITM). The `Keys` key is SYSTEM-only, but `reg save` of the parent `Parameters` key
  works from an elevated prompt.
- BlueZ `info` fields: `[LongTermKey] Key/Authenticated/EncSize/EDiv/Rand` where `Authenticated` is the MGMT LTK
  type (0 legacy, 1 legacy+MITM, 2 SC, 3 SC+MITM); `[IdentityResolvingKey] Key`;
  `[General] AddressType=static|public`. Windows' `AuthReq` is the requested value (the keyboard shows the SC bit
  yet has non-zero EDIV/Rand), so the converter decides Secure Connections from `EDIV == ERand == 0` and MITM from
  AuthReq bit 0x04. Both Surface devices: legacy pairing, authenticated, static addresses. Keyboard USB ID
  045E:0C7A, pen 045E:0C0F.
- `scripts/70-export-bt-pairings.sh` (WSL, one UAC prompt, always exports afresh because a re-pairing rewrites the
  keys in place) → `build/out/sp11-bt-pairings.tar.gz`; converter `scripts/bt-pairings-from-hive.py` (python3-hivex,
  LE only, filtered by `BT_PAIRING_USB_IDS`); importer `/usr/libexec/sp11/sp11-bt-import-pairings` (also inside the
  tarball). Verified on 44 Workstation (keyboard connects over BLE with battery reporting) and 45 Beta Workstation
  (keyboard and pen connect without pairing again).

## Hardware-verified status

### Fedora 44 GA Workstation (2026-09-13/14, support RPM 1.7)

Working: boot, install, display/GPU, Wi-Fi, Bluetooth with the correct address, touch, pen inking, audio, battery,
Flatpak, Windows entry in GRUB before UEFI Firmware Settings, shared Windows pairings for keyboard and pen,
`sp11-bt-import-pairings` and `sp11-diag` under `/usr/libexec/sp11`. Suspend and resume confirmed on 2026-09-17.

Support RPM 1.7 (`sp11-diag` enumerates paired devices instead of fixed addresses; otherwise identical to 1.6, which
added `sp11-grub-defaults` and the dnf kernel exclusion) was confirmed working on the installed system on
2026-09-14. `sp11-iptsd` 3.1.0-2.sp11 restarts the running pen daemon on upgrade. The Fedora 44 ISO built on
2026-09-14 (sha256 `eb62a087…7fee`) contains both.

### Fedora 45 Beta 1.3 Workstation (2026-09-16)

Built with `FEDORA_TARGET=beta` and installed on the tested unit, onto a LUKS-encrypted root. Confirmed: the media
boots and installs, the installed system runs (dnf, desktop applications), and the SP11 kernel is the booted one.
`qcom_q6v5_pas` loads on the installed system, so the live-only blacklist is being dropped as intended.

`dnf upgrade --refresh` on the fresh install added a stock `kernel-uki-dtbloader-7.2.5-300.fc45` boot entry, because
the exclusion list predated that package (support RPM 1.8 adds `kernel-uki-*`); removing it needed
`dnf --setopt=disable_excludes='*' remove`.

Benign boot-time messages on this unit: `qcom_pmic_glink … Failed to create device link (0x180) with supplier …` for
the PD and USB nodes (probe deferral, retried); `surface_hid … unexpected descriptor length: got 0, expected 9` then
`error -71` for one Surface Aggregator HID endpoint that nothing depends on; with kernel revision 2,
`unknown device posture for type-cover: 0` once each time the keyboard is attached.

Confirmed working on the installed system by the owner on 2026-09-16: the 44 GA list above, the Bluetooth pairing
import, no early-boot Adreno error with support RPM 2.0, a clean `dnf upgrade --refresh` after the `kernel-uki-*`
exclusion, and support RPM 2.1 as an upgrade (stock kernel removed, `dracut --regenerate-all -f` clean). Suspend and
resume confirmed on 2026-09-17.

### Kernel 7.2.5 on Fedora 45 Beta Workstation (2026-09-17)

`kernel-sp11-7.2.5-sp11v23` (`KERNEL_STABLE_VERSION=7.2.5`, built with `FEDORA_TARGET=beta`) installed next to 7.2.0
on the 45 Beta install. Confirmed working by the owner: Bluetooth, touchscreen, Wi-Fi, pen, suspend and resume,
speakers, microphone, GPU acceleration, keyboard/touchpad, battery, Flatpak, the Windows GRUB entry, the keyboard
and pen pairings shared with Windows, backlight control (brightness slider) and multi-touch
(rjindael/fedora-surface-pro-11's HID-over-SPI patches give single touch only). 7.2.5 is the build default since
then; a 45 Beta ISO with this kernel was built on 2026-09-18 (never booted) and one with revision 2 on 2026-09-22,
installed on the tested unit (see below).

### Kernel config policy rev 1, SELinux (2026-09-18)

`kernel-sp11-7.2.5-sp11v23.1` and support RPM 2.5 (`FEDORA_TARGET=beta`), installed as an update on the 45 Beta
Workstation system next to the AppArmor kernels: nothing regressed. The installation still carried the installer's
`selinux=0` and `SELINUX=disabled` (the LSM list read `lockdown,capability,yama,bpf,landlock,ipe,ima,evm`; see the
`liveinst` bullet in the Kernel section); since the restore on 2026-09-19 it runs SELinux **enforcing** with no
kernel AVC. Off-hardware before the hand-off: the shipped config differs from the AppArmor build only by the policy
and what it pulls in (`SECURITY_APPARMOR*` off, `IGH_ECAT*` off, `SECURITY_IPE` on with its verity properties,
`DEFAULT_SECURITY_SELINUX`, `CONFIG_LSM`, `ZSTD_COMPRESS` y→m because AppArmor's `EXPORT_BINARY` had selected it
built-in, plus `LOCALVERSION`/`VERSION_SIGNATURE`); 7816 modules (`ec_master` gone, `zstd_compress` new); both
Denali DTBs byte-identical to the AppArmor build; steps 36 and 35 pass. The ISO was rebuilt on 2026-09-22 with
revision 2 (next section).

### Kernel SP11 revision 2, tablet mode (2026-09-21)

`kernel-sp11-7.2.5-sp11v23.2`, installed as an update on the same system. Rebuilt on the revision-1 tree in 7.6 min;
against revision 1: the same 7816 module names, identical DTBs, a config that differs only in
`LOCALVERSION`/`VERSION_SIGNATURE`, and at section level only `surface_aggregator_registry.ko` changed (its
`.rela.data`: the SP11 group's switch entry now points at the POS node) besides version strings and `kheaders.ko`.
On the device the POS tablet-mode switch follows the keyboard, and with the sensors stack GNOME's auto-rotation
works (see the Sensors section). A 45 Beta 1.3 ISO with this kernel, support 2.6, the `--mkfs-time` fix and the
sensors stack inside was built on 2026-09-22 (sha256 `121e542a…be65`, after a first build of the day without the
stack; `build-all.sh` took 11 min with everything cached, 35 passed on its reinstall branch, 46 reinstalling over
the root, 60 its 87 checks) and installed fresh on the tested unit the same day (next section).

### Fedora 45 Beta Workstation from the revision-2 ISO (2026-09-22)

Fresh installation from the ISO built on 2026-09-22 (sha256 `121e542a…be65`: kernel v23.2, support RPM 2.6, iptsd
3.1.0-3, the sensors stack, `--mkfs-time`). The owner reports every check of the hand-off list passing: the live
session and the installed system run SELinux enforcing without `selinux=0` or a relabel boot (the first media built
with the SELinux kernel), package file times instead of the ISO's build date, the seven packages installed, the
sensors stack active from the first boot without a separate install (`sp11-sensors-check`, auto-rotation), the
pairing import, the Windows entry, `dnf upgrade --refresh` without a stock kernel, and the README's feature table.

### Sensors stack (2026-09-19 to 2026-09-21)

On the 45 Beta install: `hexagonrpc-0.5.0-6.git79d1bed.sp11`, `libssc-0.4.4-2.git54dd13e.sp11`,
`iio-sensor-proxy-3.9-3.sp11.1` and `sp11-sensors-1.9-1` (fc45); support RPM 2.6 adds `sp11-sensors-check` to
`sp11-diag`. `sp11-sensors-1.10-1` (2026-09-22: the initramfs is regenerated by a trigger only when a 1.1/1.2
package is upgraded away, `sp11-sensors-reset` says the copy is read at the next boot, comments) is verified in the
chroot (step 46: 131 checks, the upgrade from 1.9 included) and on the device since the 2026-09-22 installation
from the ISO. Working:
readings from the light sensor, accelerometer, gyroscope, magnetometer and compass (`ssccli`),
`monitor-sensor` with orientation, tilt, light and compass, GNOME's auto-rotation, suspend and resume, SELinux
enforcing without an AVC for the stack's domains, no ADSP crash since the write support. Not reported: automatic
screen brightness. Step 46 passed for this set (129 checks, the upgrade from 1.8 included). The history is at the
end of the Sensors section.

## References

rjindael/fedora-surface-pro-11 (Fedora bring-up notes); ooaklee/linux-surface-pro-11-oe (kernel, audio, iptsd
releases, ADRs); ooaklee/lexr.sh `internal/image/fedora/*.go` (remaster design reference);
denisix/ubuntu-surface-pro-11 (`SENSORS.md`: the SSC sensor stack on an SP11 under Ubuntu); linux-msm/hexagonrpc;
DylanVanAssche/libssc (codeberg); Fedora wiki "Snapdragon WoA Laptop Install"; Arch wiki "Bluetooth" (dual-boot
pairing).
