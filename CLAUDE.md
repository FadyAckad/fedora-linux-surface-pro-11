# CLAUDE.md — Fedora live ISO for Surface Pro 11 (5G, X1E80100, OLED)

Working notes for future sessions. Everything below was verified in September 2026 on the tested unit
listed under Target hardware.
Re-verify anything that depends on a newer Fedora, GRUB, Anaconda or ooaklee release.

## Repository

- `sp11.conf`: every version, URL, regex and boot-policy string; scripts source it via `scripts/lib.sh`.
- `scripts/NN-*.sh`: pipeline steps, idempotent, `FORCE=1` rebuilds. `build-all.sh` runs 00–50 and then
  `35-verify-support-rpm.sh`, which needs the live root 50 extracts (step 30 also runs it itself whenever
  one is already there, and warns when it is not); `60-verify-rootfs.sh` checks the remastered root;
  `70-export-bt-pairings.sh` is a separate tool.
- `35-verify-support-rpm.sh` installs the freshly built support RPM in an overlay of the live root, with a
  real ext4 `/boot` loop and the `grub2-probe`/`grub2-mkrelpath` stub, on both paths it reaches a machine:
  `rpm -U` with scriptlets (what `dnf upgrade` does) and `rpm -U --noscripts` plus explicit helper runs
  (what step 50 does). It asserts that every boot-policy value in `sp11.conf` reaches `/etc/default/grub`
  and the generated menu. The update path first stages a deliberately wrong policy (`GRUB_GFXMODE=640x480`,
  empty `GRUB_FONT`, `GRUB_TIMEOUT=99`, font deleted from `/boot`), so a package that installs without
  applying the policy cannot pass. Verified as a negative control: with the pre-2.4 `%posttrans` the update
  path fails seven checks while the live path still passes, which is exactly how the bug presented. The
  update path also seeds what an installer without SELinux leaves behind (`selinux=0` in `/etc/kernel/cmdline`
  and `GRUB_CMDLINE_LINUX`, `SELINUX=disabled`) and asserts `%posttrans` undid it, followed by a negative
  control with the config line alone, which `sp11-selinux-restore` must leave untouched.
- `36-verify-kernel-install.sh` (standalone, not in `build-all.sh`: after a full pipeline run the live root
  already carries the kernel under test) installs the freshly built `kernel-sp11` RPM into an overlay of the
  live root the way `dnf install` does on an installed system — `rpm -i` with scriptlets, next to the kernel
  already there — with a real ext4 `/boot` and the step-35 grub2 stubs, then the support RPM with `rpm -U`. It
  asserts both packages, the BLS entry (`linux`, `initrd`, `devicetree /dtb-<abi>/…`, every
  `SP11_ARGS_INSTALLED`, no live-only argument), `saved_entry` naming the new entry, the previous kernel's
  files, the dracut initramfs (new module tree, Adreno microcode), the regenerated menu, the config policy in
  the shipped `config`, the sysctl file under a kernel without the AppArmor key, the SELinux units the first
  boot depends on, and that `rpm -e` of the new kernel puts the previous one back. `kernel-install` exits
  non-zero in the chroot (`95-set-boot-entry.install` wants the kernel's initramfs, which the previous
  kernel's entry is written without), so the script judges by the entry, as the RPM's `%posttrans` does with
  `|| :`. `95-set-boot-entry.install` (grub2-common) is what turns `tmp_saved_entry` into `saved_entry`, so a
  kernel whose initramfs failed to build never becomes the default. dracut's `selinux` module is in none of
  these images (its `check()` returns 255: included only as a dependency or when added; Fedora's stock 45 Beta
  live initrd lacks it too) — systemd loads the policy in the real root. The seeded `/etc/kernel/cmdline`
  and `GRUB_CMDLINE_LINUX` carry the installer's `selinux=0` with `SELINUX=disabled` in the config, so the
  previous kernel's entry is written with the argument; the checks assert the plugin removed it from both
  entries, the cmdline file and `/etc/default/grub`, restored `SELINUX=enforcing` and created `/.autorelabel`.
- Sensors stack, outside `build-all.sh` (see the Sensors section): `45-build-sensors-rpms.sh` builds `hexagonrpc`,
  `libssc` and `iio-sensor-proxy` with `mock --chain` (`mock_chain` in `lib.sh`; always mock, so the host never
  gets unpackaged libraries and iio-sensor-proxy resolves `libssc-devel` from the chain's local repo) and
  `sp11-sensors` (files only, `build_rpm`), then runs `46-verify-sensors-rpms.sh` (overlay install of the four
  into the live root with scriptlets, linkage, units, rules, CIL module, sysusers, merged dnf excludes, payload,
  erase; with `SENSORS_PREVIOUS_RPMS="<earlier RPMs>"` also the in-place upgrade from those, which is what every
  device round is). `75-export-sensor-registry.sh` is the UAC tool that copies this unit's registry out of
  `DriverData\Qualcomm\fastRPC` (robocopy in an elevated PowerShell) into `build/sensors/`.
- `rpm/*.spec.in`: templates rendered by `render()` (`@KEY@` placeholders; leftovers fail the build).
- `files/`: payload of `sp11-surface-support` (installed under `/usr/libexec/sp11`, `/etc/grub.d`,
  `/usr/lib/...`), the live GRUB menu template, `README-iso.txt.in` (the note inside the ISO; it
  carries the redistribution warning and credits) and `kernel-sp11-fedora.config`, the kernel config
  policy fragment (a build input of step 20, not payload).
- The repo is public under GPL-3.0-or-later (`LICENSE`; the support RPM's `License:` tag must agree).
  Tracked files carry no per-unit identifiers: Bluetooth/Wi-Fi/peripheral addresses, firmware versions,
  local paths and the owner's name stay out of `CLAUDE.md`, `README.md`, `files/` and `scripts/`.
  Per-unit values live in `build/hardware.env`, `build/bt-pairings/`, `build/sensors/` and, inside the built
  RPMs, `/etc/sp11/bluetooth-address` and the `sp11-sensors` registry. Check before staging:
  `git grep -nE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'` must show only the `AA:BB:CC:DD:EE:FF` placeholders.
- `CLAUDE.local.md` (git-ignored, loaded by Claude Code after this file) holds the owner's private working
  rules and hand-off notes. `.gitattributes` forces LF. `.gitignore` also blocks `hardware.env`, `*.hiv`,
  `*.iso`, `*.rpm` and the pairing tarball anywhere in the tree.
- `build/` (git-ignored): `cache/` (downloads, pinned checkouts, `rpm-deps/`, `patch-<v>.xz`), `kernel/`
  (one source tree per stable version, payload, logs), `work/iso/` (extracted live root, root-owned),
  `rpms/`, `out/` (ISO, `.sha256`, pairing tarball), `bt-pairings/` (exported hive; secret), `hardware.env`.
- Bump `VERSION=` in `scripts/30-build-support-rpm.sh` whenever the support payload changes, so
  `dnf upgrade` works on the installed system. Its `%posttrans` runs `sp11-grub-defaults` and then
  regenerates `grub.cfg`. The helper call is not optional: up to 2.3 the scriptlet only ran grub2-mkconfig,
  which rebuilt the menu from the *previous* `/etc/default/grub`, so a changed policy value installed but
  never reached the machine (nothing else applies it on an installed system — the kernel-install plugin
  runs only on a kernel install, `sp11-first-boot` only once). `35-verify-support-rpm.sh` guards this. Steps 20/30/40
  skip only when the cached RPM matches (kernel ABI file list; support `%{VERSION}` and the
  `.fc<release>` dist tag; iptsd version-release and commit), so a bump or a `FEDORA_RELEASE` switch
  triggers the rebuild; `IPTSD_RPM_RELEASE` in `sp11.conf` versions the iptsd spec. `build_rpm` and
  `mock_rebuild` delete every older RPM of the same name, so `build/rpms/` holds one release's set; copy it
  aside (`build/rpms-fc<release>/`) before switching. The support payload is byte-identical across releases
  (2.2 fc44 and fc45 compared); only the dist tag differs.
- The support spec disables `__os_install_post`: `board.bin` and the Qualcomm images are ELF files that
  rpmbuild's brp scripts would otherwise rewrite (`board.bin` comes out 32 bytes shorter, the Bluetooth
  helper loses its `.comment` data).
- Step 10 honours `FORCE=1` only for the two dnf-downloaded caches (`build/cache/wifi/f<release>`,
  `build/cache/rpm-deps/f<release>`); checksum-pinned downloads are never re-fetched.
- `50-build-iso.sh` caches the extracted live image as `build/work/iso/live.erofs` and keys it to the ISO it
  came from with a `live.erofs.source` stamp. An unkeyed cache silently remasters the *previous* media on a
  release or compose change; it also asserts the extracted root's `VERSION_ID` equals `FEDORA_RELEASE`.
- `fetch()` in `lib.sh` resumes into `DEST.part` across attempts. curl's own `--retry` restarts from byte
  zero, which never gets a multi-GB ISO through a mirror that drops the transfer (curl error 18).

## Host

WSL2 Fedora 44 aarch64 on the Surface itself (tested with 12 cores, 11 GiB RAM), passwordless sudo, Windows at
`/mnt/c`, `powershell.exe` interop (SMBIOS, panel and Bluetooth detection; one UAC prompt for the
registry export). No Docker. `00-setup-host.sh` installs everything, including gawk, xz, openssl, cmake,
dosfstools and python3-hivex, which the stock WSL image lacks.

## Target hardware (tested unit)

- Product `Microsoft Surface Pro with 5G, 11th Edition`, SKU `Surface_Pro_with_5G_11th_Edition_2077`,
  X1E80100, Samsung (SDC) OLED 2880x1920.
- Bluetooth and Wi-Fi addresses are per unit. `05-detect-hardware.sh` reads the Bluetooth address into
  `build/hardware.env`; the support RPM carries it in `/etc/sp11/bluetooth-address`.
- Device tree `qcom/x1e80100-microsoft-denali-oled.dtb`; the X1P LCD variant
  (`x1p64100-microsoft-denali.dtb`) is a different machine.
- Upstream regexes are written for the non-5G SKU (`Microsoft Surface Pro, 11th Edition`, SKU `_2076`)
  and need `( with 5G)?` / `(_with_5G)?`. `05-detect-hardware.sh` self-tests every regex against both
  SKUs and the live Windows values.
- stubble's `x1e80100-microsoft-denali.json` hardware IDs do not match this SKU (CHIDs computed:
  zero matches), so automatic DTB selection cannot work; the DTB is always loaded explicitly.
- Windows identity queries (`05-detect-hardware.sh`): the built-in panel is the `WmiMonitorID` instance
  whose `WmiMonitorConnectionParams.VideoOutputTechnology` is 2147483648 (internal); the controller
  address is `DEVPKEY_Bluetooth_RadioAddress` (`{a92f26ca-eda7-4b1d-9db2-27b68aa5a2eb} 1`) on the
  Bluetooth-class device `QCA_SHB\UART_H4_HMT\...`, formatted `{0:X12}`. Radios under `USB\` are skipped.

## Kernel

- ooaklee/linux_ms_dev_kit-sp11, release `sp11-qcom-x1e-7.2.0-jg-0sp11v23`, commit
  `ce78e6ebc3d70c4a316b5721a62478ca87d6cb46`, ABI `7.2.0-jg-0sp11v23-qcom-x1e`. Source tarball and
  debs with SHA256SUMS are on the OE release page. Since 2026-09-17 the default build adds the kernel.org
  7.2.5 stable update (see `KERNEL_STABLE_VERSION` below), since 2026-09-18 also the config policy
  (`KERNEL_CONFIG_REV=1`, see below): ABI `7.2.5-jg-0sp11v23.1-qcom-x1e`, package
  `kernel-sp11-7.2.5-sp11v23.1`.
- `python3 debian/scripts/misc/annotations --file debian.qcom-x1e/config/annotations --arch arm64
  --flavour qcom-x1e --export` reproduces the released config exactly except `CONFIG_VERSION_SIGNATURE`.
  The ABI is injected with `CONFIG_LOCALVERSION="-jg-0sp11v23-qcom-x1e"`. Native build of a fresh tree:
  ~45 min on 12 cores, 7816 modules, same set as ooaklee's deb. A stopped build resumes where it left off
  (the background task dies with the Claude session or WSL); `FORCE=1` on a built tree takes ~5 min.
  Image is `arch/arm64/boot/vmlinuz.efi` (EFI zboot PE).
- Relevant config: EROFS with LZMA and xattrs as module; no `CRYPTO_FIPS`; `MODULE_SIG=y` with an ephemeral
  key; zstd modules; `FW_LOADER_COMPRESS_XZ=y`. LSM stack from `files/kernel-sp11-fedora.config`:
  `CONFIG_LSM="lockdown,yama,integrity,selinux,bpf,landlock,ipe"` (the value of Fedora's
  `kernel-aarch64-fedora.config`, f45), `DEFAULT_SECURITY_SELINUX`, `SECURITY_IPE` (inert until a policy is
  loaded), `SECURITY_APPARMOR` off, `IGH_ECAT` and `UBUNTU_ODM_DRIVERS` off. ooaklee's published config has
  `CONFIG_LSM="landlock,lockdown,yama,integrity,apparmor"` with `SECURITY_SELINUX=y` never activated (Fedora
  ran without MAC) and `CONFIG_SECURITY_APPARMOR_RESTRICT_USERNS=y`, which denies unprivileged user
  namespaces without a profile; Fedora has none, so Flatpak's bwrap failed with EPERM until
  `kernel.apparmor_restrict_unprivileged_userns=0` was shipped in `/usr/lib/sysctl.d/90-sp11.conf`. The line
  stays for those kernels, which remain installed next to the new one, prefixed `-`: `sysctl.d(5)` then logs
  a missing key at debug level instead of failing the unit.
- Fedora's `depmod -b BASE` expects `BASE/lib/modules`; the payload uses `/usr/lib/modules`, so
  `20-build-kernel.sh` uses a temporary `lib -> usr/lib` symlink.
- `KERNEL_STABLE_VERSION` (default `7.2.5` in build mode; `KERNEL_STABLE_VERSION=` builds the release as
  published) applies kernel.org's cumulative `patch-<v>.xz` (sha256 pinned in the `sp11.conf` case table) to
  ooaklee's source in a tree of its own, `build/kernel/src/linux-<commit>-stable-<v>`, stamped
  `.sp11-stable-<v>` only after `patch --batch --forward --fuzz=1` applied without a reject.
  `KERNEL_UPSTREAM_VERSION` stays ooaklee's base; `KERNEL_BUILD_VERSION`, the ABI
  (`7.2.5-jg-0sp11v23-qcom-x1e`) and the RPM version follow the patch (`kernel-sp11-7.2.5-sp11v23`; the
  config revision below appends `.1` to the ABI and the release).
  `KERNEL_MODE=prebuilt` ignores the default and refuses an explicit value. `sp11.conf` also refuses a
  stable version whose `X.Y.0` base is not `KERNEL_UPSTREAM_VERSION`, so a new ooaklee release on another
  base fails early until the default is revisited.
- `KERNEL_CONFIG_REV` (default `1` in build mode; `KERNEL_CONFIG_REV=` builds ooaklee's config as published,
  prebuilt mode refuses a value) merges `files/kernel-sp11-fedora.config` into the annotations export with
  `scripts/kconfig/merge_config.sh -m` before `olddefconfig`; `config_fragment_holds` (`lib.sh`, also run by
  step 60 on the shipped `config`) then asserts every fragment line, and `stage_common` refuses any module
  under `kernel/ubuntu/` (Ubuntu's out-of-tree drivers; `IGH_ECAT` is `default m`, so a future one would
  otherwise ship unnoticed). The revision goes into the ABI (`…0sp11v23.1-qcom-x1e`) and the RPM release
  (`sp11v23.1`): `kernel-sp11` is install-only, and a same-ABI rebuild would own the same `/boot` and module
  paths as the installed package, so RPM refuses it; a new ABI also keeps the previous kernel in GRUB as the
  fallback. `make kernelrelease` is a no-sync-config target and `setlocalversion` reads
  `include/config/auto.conf`, so on a built tree the ABI check needs `make syncconfig` first (step 20 does).
- Why a config change and not a source change (measured 2026-09-18 against pristine kernel.org 7.2.5,
  rebuilt from `linux-7.2.tar.xz` plus the pinned `patch-7.2.5.xz`): ooaklee's tree modifies 433 upstream
  files (~20.5k lines), deletes none and adds ~230 source files. 161 of the modified files are
  Qualcomm/Surface/DTS work, 45 are Ubuntu distro code (AppArmor notify/af_inet, `version_signature`,
  `secureboot`, integrity), the rest cannot be attributed without git history, which the release tarball
  does not carry; the touch/pen stack (`mshw0485_touch.c`, `drivers/hid/spi-hid/`, g6ts headers, 7.5k lines)
  has no upstream counterpart. Ubuntu reaches the machine only through the config: the packaging is never
  used (step 20 runs `debian/scripts/misc/annotations`, nothing else from `debian*/`). Ubuntu SAUCE that
  stays compiled under any config: `fs/proc/version_signature.o` (gated on `BOOT_CONFIG`, which Fedora sets
  too) and `drivers/firmware/efi/secureboot.o` (on `EFI`); AppArmor references outside `security/apparmor`
  are `#ifdef CONFIG_SECURITY_APPARMOR`. Fedora's own aarch64 config already sets 20 of the 24
  `REQUIRED_OPTS`; the missing four are ooaklee-only drivers, so a Fedora-config base (not done) would have
  to re-add them explicitly and re-validate every hardware function.
- SELinux on a system that ran the AppArmor kernels: with SELinux inactive nothing labels new files (no
  `security.selinux` xattr from the kernel, no setfilecon from rpm), so everything created since the
  installation is unlabeled. Fedora handles this itself: `selinux-autorelabel-mark.service`
  (`policycoreutils`, enabled by preset, `ConditionSecurity=!selinux`) touches `/.autorelabel` on every such
  boot, and `selinux-autorelabel-generator.sh` turns the marker into a relabel plus reboot on the first
  SELinux boot. Booting an AppArmor kernel again afterwards creates unlabeled files, hence another relabel.
  Helpers started through `SYSTEMD_WANTS` run as `unconfined_service_t` under the targeted policy; the one
  path in `udev_t` is `PROGRAM="/usr/libexec/sp11-iptsd-check-device"` (`70-sp11-iptsd.rules`) opening
  `/dev/hidraw*` (`usb_device_t`), the first suspect for an AVC if the pen daemon does not start.
  `sp11-diag` prints `/sys/kernel/security/lsm`, `getenforce` and the boot's kernel AVC lines. All of this
  presupposes that `/etc/selinux/config` does not say `disabled` — see the next bullet.
- Every installation made from media whose live session had no active SELinux — every ISO built with the
  AppArmor kernels — is **installed with SELinux disabled**, not merely inactive: Fedora's `/usr/bin/liveinst`
  runs `sestatus` and, when it does not report `enabled`, starts Anaconda with `--noselinux`; the Security
  module then holds `SELINUX_DISABLED`, `set_boot_args` adds `selinux=0` to the boot arguments
  (`/etc/kernel/cmdline`, `GRUB_CMDLINE_LINUX`, every BLS entry) and `ConfigureSELinuxTask` writes
  `SELINUX=disabled` into `/etc/selinux/config`. Found on 2026-09-19 when the SELinux kernel booted on the
  owner's 45 Beta install with `getenforce: Disabled` and no `selinux` in the LSM list
  (`SECURITY_SELINUX_BOOTPARAM=y` honours `selinux=0`). Since the 2026-09-19 rebuild of support RPM 2.5 (the
  earlier 2.5 was never committed or released) `/usr/libexec/sp11/sp11-selinux-restore` undoes it: when *both*
  marks are present (`selinux=0` in `/etc/kernel/cmdline` and `SELINUX=disabled`; a system disabled by hand
  carries only the config line and is left alone) it removes the argument (`grubby --update-kernel=ALL
  --remove-args=selinux=0`, plus sed on `/etc/kernel/cmdline` and `GRUB_CMDLINE_LINUX` for systems without
  grubby or entries), sets `SELINUX=enforcing` and touches `/.autorelabel`; idempotent, never reboots, no-op in
  a live session (`rd.live.image`). It runs from the kernel-install plugin, before `20-grub.install` writes the
  new entry from `/etc/kernel/cmdline`, and from the support RPM's `%posttrans` (a support upgrade on a system
  that already has the kernel; it runs before the menu regeneration so `update_bls_cmdline` rewrites every
  entry from the cleaned `GRUB_CMDLINE_LINUX`). Enforcing directly, no permissive stage:
  `/usr/libexec/selinux/selinux-autorelabel` switches to permissive itself for the relabel boot and reboots, so
  the boot after it is enforcing on a relabeled system, and `SELINUX=enforcing` under an AppArmor kernel is
  what every live session already ran. Manual equivalent: the grubby command, `SELINUX=enforcing`,
  `touch /.autorelabel`, reboot. Done by hand by the owner on the 45 Beta install on 2026-09-19 (permissive
  first as a precaution, then enforcing): the relabel boot happened, the next boot ran permissive with
  `selinux` in the LSM list and no kernel AVC, then **enforcing** the same day — `sp11-diag` under enforcing shows no kernel
  AVC, the pen daemon on its hidraw node, the Bluetooth address helper's result and the audio stack, with a
  desktop login in between. The automatic path (`sp11-selinux-restore`) was confirmed on the device by the
  owner on 2026-09-19 after steps 35 and 36 had passed. Media built with the SELinux kernel should not have the
  problem — the live session runs enforcing, `sestatus` reports enabled and
  Anaconda keeps the default — but no such ISO has been built or booted yet.
- 7.2.5 applies to v23 without a reject (one fuzz-1 hunk in `nvme/host/tcp.c`) and touches none of the
  drivers the SP11 patches change (GPI DMA, spi-geni, Denali DTS, `sound/soc/qcom`, soundwire,
  `drivers/input`, `platform/surface`). Against the 7.2.0 build: the same 7816 module names,
  byte-identical Denali DTBs, and a config that differs only in `VERSION_SIGNATURE` and the Allwinner
  `CRYPTO_DEV_SUN8I_{CE,SS}_PRNG` symbols 7.2.5 removes.
- 7.2.6 does not apply to v23. Of the 26 files with rejected hunks, 19 hold changes v23 already has (the
  X1 "Fix swapped USB QMP PHY vdda-phy/vdda-pll supplies" series, including `x1-microsoft-denali.dtsi`, and
  msm DP/DSI fixes). 7 are real conflicts with non-upstream code in v23: `remoteproc/qcom_q6v5.c` and
  `remoteproc_core.c` (v23's ADSP attach and `RPROC_AUTO_BOOT_RESTART_IF_FW_AVAILABLE` series, absent from
  mainline 7.3-rc3, so there is no reference merge; 7.2.6's `!was_running` stop condition taken as-is would
  skip the SMP2P stop when the firmware-started ADSP is restarted), `spi/spi-geni-qcom.c` (SP11 QSPI branch
  in `spi_geni_init`), `qdsp6/q6apm.c` (SP11 audio, which already fixes the same start-count bug its own
  way), Ubuntu AppArmor `domain.c` (different `aa_audit_file()` arguments), `glymur-crd.dts` and
  `sc8280xp.dtsi`. Skipping the rejected hunk breaks the build in four of them, because other hunks of the
  same commit apply (`rproc_attach_work`, the `out_pm` label, `stack_msg`, a second `pil_gpu_mem` node). A
  successful `patch -R --dry-run` does not prove a pure-deletion hunk is already applied: the AppArmor hunk
  passed it although the block is still there.
- Upstream 7.2.5 builds `x1e80100-microsoft-denali-oled.dtb` too, but has no `mshw0485` driver and none of
  ooaklee's Denali DTS additions (QSPI touch controller, speaker feedback and TX DMIC links, CPU idle
  domains, IMX681, DSP/GPU firmware paths), so Fedora's own kernel with a DTB is no substitute.
- `kernel-sp11` provides `installonlypkg(kernel)`, so dnf installs a new version next to the existing ones.
  Fedora's `20-grub.install` makes the added kernel the saved default when `/etc/sysconfig/kernel` has
  `UPDATEDEFAULT=yes` and `DEFAULTKERNEL=kernel-core` (the ABI contains none of `64k|auto|rt|uki`).
  `kernel-install remove` leaves `saved_entry` naming the removed entry; GRUB then boots the first one.
  The spec's `%preun` runs `kernel-install remove` unconditionally since 2026-09-17: the earlier
  `if [ "$1" -eq 0 ]` guard skipped it whenever another `kernel-sp11` stayed installed and left the BLS
  entry and `/boot/dtb-<ver>` behind. RPMs built before that (the 7.2.0 package on existing installs) keep
  the guard: removing one next to a newer SP11 kernel needs `kernel-install remove <abi>` first.
- A chroot test of that path needs a real filesystem at `/boot` (an ext4 loop image; `mkfs.ext4` from the
  root, since the host has no e2fsprogs): on an overlay root `grub2-editenv` fails with `failed to get
  canonical path of overlay`, so `saved_entry` never changes. The step 60 simulation does not check it.

## Fedora live media

- `FEDORA_TARGET` in `sp11.conf` picks the compose family: `ga` (`releases/<n>/`), `beta`
  (`releases/test/<n>_Beta/`) or `nightly` (`development/<n>/`, needs `FEDORA_COMPOSE=<stamp>`).
  `FEDORA_RELEASE` stays the numeric release (dnf `--releasever`, `%{dist}`, cache keys);
  `FEDORA_MEDIA_VERSION` is the version string inside the ISO name (`45_Beta`). The three families name
  their CHECKSUM file differently — GA `Fedora-Workstation-<v>-<c>-<arch>-CHECKSUM`, Beta
  `Fedora-Workstation-iso-<v>-<c>-<arch>-CHECKSUM`, nightly
  `Fedora-Workstation-iso-<n>-<arch>-<stamp>-CHECKSUM` — so each branch spells its own out rather than
  deriving one from another. The file body is the same clearsigned BSD digest in all three, so the
  `sha256sum -c --ignore-missing` check is unchanged.
- `FEDORA_EDITION` (default `Workstation`) picks the desktop; any other value is a spin, named as in its ISO
  file name. Every spin of a compose sits under `Spins/` and shares one CHECKSUM whose product is `Spins`
  (`Fedora-Spins-44-1.7-aarch64-CHECKSUM`), hence the separate `FEDORA_PRODUCT`. Workstation names
  resolve exactly as before the switch existed. KDE is its own product (`KDE/`,
  `Fedora-KDE-44-1.7-aarch64-CHECKSUM`, `Fedora-KDE-Desktop-Live-...`) and is not covered.
- `Fedora-Workstation-Live-44-1.7.aarch64.iso`, volume id `Fedora-WS-Live-44`, built by kiwi. The
  live root `/LiveOS/squashfs.img` is EROFS (LZMA, fragments, dedupe), 2.36 GB.
- Hybrid GPT + El Torito UEFI image + appended ESP. `/EFI/BOOT/grub.cfg` does `search --file
  --set=root /boot/0x503d6c7e` then `configfile ($root)/boot/grub2/grub.cfg`. Kernel
  `/boot/aarch64/loader/linux`, initrd `/boot/aarch64/loader/initrd`, font
  `/boot/aarch64/loader/grub2/fonts/unicode.pf2` (step 50 maps `sp11-console.pf2` in beside it, lifted out
  of the live root rather than generated a second time). `xorriso ... -boot_image any replay -map ...`
  reproduces the layout; `50-build-iso.sh` reads these paths from the ISO instead of assuming them.
- Fedora's aarch64 GRUB image has `devicetree`, `gfxterm`, `loadfont`, `blscfg`, `fat`, `efi_gop`,
  `all_video`, `search_fs_uuid`, `part_gpt`, `fwsetup`, `efinet`, `net`, `boot`. It lacks `efi_uga`,
  `video_bochs`, `video_cirrus` and `chain` (Fedora builds `chain` into x86 images only).
- GRUB has no text-scale setting: `gfxterm` sizes its character cell from the loaded PF2 font
  (`calculate_normal_character_width` over ASCII 32-126 for the width, `MAXH` for the height), so a large
  font is the only way to keep the menu legible at the panel's native mode. `sp11-console.pf2` is built by
  step 30 with `grub2-mkfont -s "$GRUB_FONT_SIZE"` from DejaVu Sans Mono; at 40 pt the cell is 24x48 px,
  i.e. 120x40 characters at 2880x1920 (measured from the PF2 header, not from the point size: `MAXW` is the
  maximum over *all* glyphs and overstates the monospace advance). DejaVu is Bitstream-Vera licensed, hence
  the extra `License:` term and a font name carrying neither "Bitstream" nor "Vera".
  `00_header` honours `GRUB_FONT`: when set it emits `prepare_grub_to_access_device` plus a single
  `if loadfont <path>` and skips its own `unicode/unifont/ascii` search, so exactly one font is loaded and
  `gfxterm` uses it. The file must be under `/boot`: on the LUKS layout nothing else is readable by GRUB,
  and 00_header's own fallback would otherwise land on `/usr/share/grub/unicode.pf2`, which is not. A
  `GRUB_FONT` naming a missing file makes 00_header run `grub2-probe` on it and grub2-mkconfig fails
  outright, so `sp11-grub-defaults` writes an empty `GRUB_FONT=` (the supported opt-out) whenever the copy
  into `/boot/grub2/fonts/` did not happen. Verified so far only off-hardware: a real `grub2-mkconfig`
  (2.12-76.fc45) in an overlay of the remastered root with an ext4 loop at `/boot` exits 0 and emits
  `search --fs-uuid` + `if loadfont /grub2/fonts/sp11-console.pf2` with `set gfxmode=2880x1920,auto`.
  How it actually reads on the panel, and whether the firmware GOP offers 2880x1920, is not confirmed.
- `insmod NAME` resolves `$prefix/arm64-efi/NAME.mod`; on installed Fedora `$prefix` is `/boot/grub2`
  (set by `gen_grub_cfgstub`, which Anaconda calls to write the ESP stub `EFI/fedora/grub.cfg`:
  `search --fs-uuid <boot uuid>`, then `configfile $prefix/grub.cfg`). The stub names a single /boot, so a
  second Fedora installed on the same ESP takes the menu over and hides the first. Module loading works with
  Secure Boot disabled. `grub2-efi-aa64-modules` (installed by default) provides the version-matched
  `/usr/lib/grub/arm64-efi/*.mod`.
- Fedora's os-prober has no EFI Windows probe on aarch64 (`os-probes/mounted/efi/` holds only
  `05shell`), so `GRUB_DISABLE_OS_PROBER=false` never finds Windows.
- GRUB menu order follows `/etc/grub.d/` filename order; `30_uefi-firmware` emits UEFI Firmware
  Settings, hence the Windows generator is `29_sp11_windows`.
- Stock live initramfs arguments: `dracut --no-hostonly --no-hostonly-cmdline --install /.profile
  --add "dmsquash-live livenet pollcdrom" --omit multipath`; it includes the `fips` dracut modules,
  which the pipeline omits. Generate it in a chroot of the live root.
- `rd.live.check` needs an implanted ISO checksum, which xorriso remastering does not carry over, so the
  live menu has no media-check entry.
- Anaconda 44.30 and 45.22 (code read in a Fedora 44 and a Workstation 45 Beta live root; same task
  order in both) discover kernels only from `/boot/vmlinuz-*` (`live_os/utils.py`) and run
  `kernel-install add <ver> /lib/modules/<ver>/vmlinuz` for each (the 44 1.7 and 45 Beta media carry no
  `kernel-core`; see `kernel-uki-dtbloader` below). Queue order (`modules/boss/installation.py`): payload
  (`PrepareSystemForInstallationTask` writes `/etc/modprobe.d/anaconda-denylist.conf` from
  `modprobe.blacklist=`; rsync of the live root without `--delete`, excluding `/boot/loader/`, then
  `/boot/grub2`, `/etc/sysconfig` and `/usr/lib/grub` copied again without xattrs) → bootloader
  (`InstallBootloaderTask`: `write_defaults` truncates `/etc/default/grub` and sets `GRUB_CMDLINE_LINUX` to
  Anaconda's boot args, then grub2-mkconfig, which creates `/etc/kernel/cmdline`; `CreateBLSEntriesTask`:
  deletes every BLS entry, `kernel-install add`, `grub2-mkconfig -o /etc/grub2.cfg`) → configuration queue
  (`RecreateInitrdsTask`: `dracut -f`). Only `preserved_arguments` from the live command line reach the boot
  args (`clk_ignore_unused pd_ignore_unused arm64.nopauth` among them, 45.22 also `systemd.tpm2_wait`; never
  `modprobe.blacklist`, `rd.driver.blacklist` or the soundwire argument), plus `rhgb quiet` and storage
  arguments. Command lines and their output go to `/var/log/anaconda/program.log` on the installed system.
  Its grub2-mkconfig runs in a chroot with `/dev` bound but no udev database. The live root's
  `/etc/default/grub` never reaches an installation. On a BTRFS root (Fedora's default layout, with or
  without LUKS) `FixBTRFSBootloaderTask` runs after `RecreateInitrdsTask` and repeats
  `ConfigureBootloaderTask` and `InstallBootloaderTask`: `/etc/default/grub` is truncated again and
  grub2-mkconfig rewrites every entry's options and `/etc/kernel/cmdline` from Anaconda's arguments, after
  the kernel-install plugin ran. The entry's `devicetree` line, the initramfs and the removed denylist
  survive; the GRUB settings and the SP11-only arguments do not.
- Fedora's `10_linux` (`update_bls_cmdline`) rewrites the `options` line of **every** BLS entry from
  `root=… ro $GRUB_CMDLINE_LINUX $GRUB_CMDLINE_LINUX_DEFAULT` on each grub2-mkconfig, and rewrites
  `/etc/kernel/cmdline` when that file is missing or older than `/etc/default/grub`. `20-grub.install` reads
  the options for a new entry from `/etc/kernel/cmdline`, but first runs grub2-mkconfig when that file is
  older than `/etc/default/grub`; it writes `devicetree /dtb-<ver>/$GRUB_DEVICETREE` and copies
  `/usr/lib/modules/<ver>/dtb` to `/boot/dtb-<ver>`. kernel-install resolves `layout=other` on these
  systems ("Entry-token directory … not found"), so `90-loaderentry.install` quits and
  `/etc/kernel/devicetree` is never read.
- `15-sp11-surface.install` runs before `20-grub.install`: `sp11-grub-defaults` (the single writer of the
  `/etc/default/grub` policy, also used by `sp11-first-boot`, the support RPM's `%posttrans` and
  `50-build-iso.sh`) sets `GRUB_DEVICETREE`
  and the display settings, the plugin appends the SP11 arguments to `/etc/kernel/cmdline` (rewritten after
  `/etc/default/grub`, so 20-grub does not rerun mkconfig) and removes the Anaconda denylist before
  Anaconda's initramfs rebuild. Anaconda's last grub2-mkconfig still strips the SP11-only arguments from the
  entry (the soundwire argument; on 44 also `systemd.tpm2_wait=0`), and on BTRFS the GRUB settings as well,
  so the first boot runs without them until `sp11-first-boot` (`grubby --update-kernel=ALL --args`, which
  also updates `GRUB_CMDLINE_LINUX` and `/etc/kernel/cmdline`, then `sp11-grub-defaults` and
  grub2-mkconfig) fixes both for the second boot. Reproduced for the non-BTRFS order in an overlay of a
  Fedora 44 root with real grub2-mkconfig runs (a `grub2-probe`/`grub2-mkrelpath` stub for the overlay root,
  an ext4 loop at `/boot`). The plugin does not filter live-only arguments; step 60 checks that no Anaconda
  config mentions them.
- `mkfs.erofs -Ededupe` is single-threaded in erofs-utils 1.9.4 (hours). `-Efragments -C1048576
  --workers=N -zlzma,level=6` takes ~5 min and is only slightly larger. Use `--file-contexts` from the
  root's own SELinux policy.
- In a chroot without udev, `lsblk` reports empty PARTTYPE/FSTYPE; use `blkid -c /dev/null -o device
  -t TYPE=vfat` and `blkid -p -s PART_ENTRY_TYPE -o value DEV` instead.
- `grep -q` at the end of a pipeline under `pipefail` fails spuriously (SIGPIPE); use `grep ... >/dev/null`.
- Under `set -e -o pipefail`, `var=$(ls pattern | head -1)` exits the script silently when the glob does
  not match (`ls` fails, the assignment inherits the status). Append `|| true` inside the substitution.
  The same applies to `var=$(grep ... | sed ...)` and `var=$(... | grep -v ...)` on empty input, and to
  `var=$(find DIR ... | wc -l)` when DIR does not exist (`find` fails on a missing start point; filter with
  `-path` from a directory that exists instead). Step 20's Ubuntu-module guard died that way on its first run.
- `bash -n A B C` parses only `A` (`B C` become positional parameters); syntax-check files one at a time.
- `grep -v -q PATTERN FILE` cannot assert absence (it succeeds on any non-matching line); use `! grep -q`.
- `findmnt -R DIR` lists submounts only when DIR itself is a mount point; `mounts_under` in `lib.sh`
  matches the target prefix instead. Both `50` and `60` refuse to `rm -rf` a tree with mounts below it.
- `%systemd_postun_with_restart NAME@.service` on a template unit is a no-op (`systemctl try-restart`
  rejects a name without instance); restart `'NAME@*.service'` explicitly.
- dracut `install_items` applies to `--no-hostonly` builds too; `50` parks the support RPM's drop-in
  during the live initramfs run and installs only the GPU zap shader.
- `rpm --noscripts` also skips triggers, so step 50 runs `sp11-ucm-apply` in the chroot itself. On a normal
  install, the support RPM's `%triggerin -- alsa-ucm` and `%triggerin -- grub2-efi-aa64-modules` also fire
  for its own installation, and systemd's RPM file triggers daemon-reload, reload udev rules and run
  `systemd-sysctl` (only when `/run/systemd/system` exists), so the spec needs no `%post`.
- Never install RPMs into the live root with `--nodeps`. Workstation Live lacks `spdlog`, which
  `sp11-iptsd` links against; a daemon that cannot load makes udev's `check-device` fail, so no
  `sp11-iptsd@` unit starts. `LIVE_EXTRA_PKGS` in `sp11.conf` lists
  packages to download (`10-fetch-sources.sh` → `build/cache/rpm-deps`) and install first;
  `50-build-iso.sh` runs `rpm -U --test` and `--help` on the iptsd binaries; `60-verify-rootfs.sh`
  repeats both checks and `ldd`s the shipped binaries.

## Fedora 45 differences (verified 2026-09-16 against 45 Beta 1.3)

- fmt 11.2.0 → 12.1.0 and spdlog 1.15.3 → 1.17.0 break the sonames `sp11-iptsd` links against
  (`libfmt.so.11` → `.12`, `libspdlog.so.1.15` → `.1.17`), so a host-built RPM cannot install into an F45
  root and step 50's `rpm -U --test` refuses it. `IPTSD_BUILD_MODE=auto` builds iptsd in a `mock`
  buildroot for the target whenever `FEDORA_RELEASE` differs from `rpm -E %{fedora}`; `mock_rebuild` in
  `lib.sh` passes `--no-bootstrap-image` (no container pull, so podman stays out of the dependency set) and
  retries once with `--isolation=simple` for WSL. `sp11-bt-set-addr` is libc-only and `kernel-sp11` is
  `AutoReqProv: no`, so iptsd is the only cross-release package.
- `rpm/sp11-iptsd.spec.in` must carry `BuildRequires: cmake`: meson locates Microsoft.GSL only through its
  CMake config. The host build masked this because `00-setup-host.sh` installs cmake for other reasons.
- The boot kernel on aarch64 is owned by `kernel-uki-dtbloader`, not `kernel-core` (Workstation Live
  installs no `kernel-core` at all). Not new in 45: Koji's package list of the 44 1.7 Workstation image
  shows the same set (`kernel`, `kernel-modules{,-core,-extra}`, `kernel-uki-dtbloader`, no
  `kernel-core`). It provides `installonlypkg(kernel)` and `kernel-core-uname-r`, so dnf
  adds it *alongside* rather than upgrading in place, and its `/usr/bin/kernel-install` dependency writes
  the BLS entry. `files/90-sp11-dnf.conf` therefore excludes `kernel-uki-*` as well; the glob deliberately
  does not match `kernel-sp11`, which must stay installable from a local RPM. `kernel-tools` and
  `kernel-tools-libs` track the kernel version too but own nothing in `/boot` and cannot create entries.
- dnf5 has no `--disableexcludes` (that is the DNF4 spelling and it errors out); `disable_excludes` is a
  config option only, so the override is `dnf --setopt=disable_excludes='*' ...`. The exclusion hides
  packages from `remove` as well as install, so taking a stock kernel off the system needs it.
- Two new aarch64 dracut modules defeat the live-media policy, and `LIVE_DRACUT_OMIT` in `50-build-iso.sh`
  omits both: `devicetree-firmware`'s generic (`--no-hostonly`) path globs
  `$fw_dir/qcom/x1e80100/*/*/*.mbn|elf`, which is exactly the Denali set, and `qcom-adsp` modprobes
  `qcom_q6v5_pas` from a pre-udev hook. dracut ignores omit names it does not know, so the GA path is
  unaffected. `qcom-adsp` exists to solve the very USB-C reset that forces the live-only DSP blacklist, so
  adopting it could give the live session audio and battery — untested on this unit.
- `/boot/loader/entries` is `0700 root`, so an unprivileged shell cannot expand a glob inside it: the BLS
  cleanup in step 50 must run root-side (`as_root find ... -delete`). The earlier
  `as_root rm -rf "$ROOTFS"/boot/loader/entries/*.conf` was a silent no-op and shipped the source media's
  rescue and stock-kernel entries inside the image.
- The GPU probes in the initramfs (plymouth) and needs the Adreno microcode there, or early boot logs
  `failed to load gen70500_sqe.fw` until switch-root makes `/usr/lib/firmware` reachable. `qcom-firmware`
  ships `qcom/gen70500_sqe.fw.xz` and `qcom/gen70500_gmu.bin.xz`; `files/90-sp11.conf` installs both and the
  support RPM now `Requires: qcom-firmware`. With 2.0 or later the error is gone on the installed 45 Beta
  Workstation system. The live initramfs still carries only the zap shader (step 50 parks the drop-in).

- A stock kernel whose packages stay installed without its `/boot` image breaks `dracut --regenerate-all`:
  dracut 111 without an output path writes `/boot/initramfs-<ver>.img` only when `/boot/vmlinuz-<ver>`
  exists; otherwise, with `/boot/efi` mounted, it falls back to `/boot/efi/<machine-id>/<ver>/initrd`, fails
  with `Can't write to ...`, carries on to the next kernel and exits non-zero. Up to support RPM 2.2 the live
  root kept the stock packages with their images deleted, and `sp11-remove-stock-kernels.service` (one shot
  with its own stamp, `/var/lib/sp11/stock-kernels-removed.done`, so it also runs on systems whose first
  boot already happened; 2.1 compared `uname -r` with a fixed `SP11_KERNEL_ABI` from `/etc/sp11/sp11.env`,
  2.2 accepted any installed `kernel-sp11` version) erased the stock set with plain `rpm -e`, removed module
  trees no package owns, and deleted BLS entries whose kernel image is missing; confirmed on hardware on
  2026-09-16 as an upgrade to 2.1 on the Fedora 45 Beta install. Tested in an overlay of a Fedora 44 root
  with 7.2.0 and 7.2.5 installed and a faked `uname -r`: 2.1 refuses under 7.2.5; 2.2 refuses under the
  stock kernel, cleans up under 7.2.5, and a rerun under 7.2.0 changes nothing. Nothing outside the kernel
  family requires those packages on 45 (`rpm -e --test` is clean); `kernel-sp11`'s unversioned
  `kernel-uname-r`, `kernel-core-uname-r` and `kernel-modules-core-uname-r` provides satisfy the stock
  packages' versioned requires, so even a partial erase of the set passes; erasing `glibc` is a working
  negative control.
  Since 2.3, step 50 erases the stock set from the live root with `rpm -e --noscripts` (a plain erase, so
  dependencies are still checked; nothing outside the kernel family requires them on 44 or 45, and the same
  `kernel-sp11` provides satisfy the stock packages' versioned requires). On the Fedora 44 and 45 Beta roots
  the erase left no module tree and no `/boot` file behind (the depmod outputs are `%ghost`); step 50 still
  removes unowned leftovers and refuses any other module tree. The installer then only ever sees
  `kernel-sp11`. The service is gone, so a system that never ran it (support RPM older than 2.1) needs 2.1
  or 2.2 and one reboot before 2.3.

## Peripherals and userspace

- Firmware: ADSP/CDSP/GPU blobs come from this device's Windows DriverStore (`surfacepro_ext_adsp8380*`,
  `qcnspmcdm_ext_cdsp8380*`, `qcdx8380*`); Fedora's `qcom-firmware` has no Denali directory. The Denali
  DT requests exactly `qcadsp8380.mbn`, `adsp_dtb.mbn`, `qccdsp8380.mbn`, `cdsp_dtb.mbn` and the zap shader
  `qcdxkmsuc8380.mbn` (all ELF); Windows ships the DT blobs as `adsp_dtbs.elf`/`cdsp_dtbs.elf`, and the
  support RPM installs them under the DT names only. Not shipped since 2.3: the `*_dtbs.elf` copies;
  `*.jsn` (the kernel's pd-mapper, `CONFIG_QCOM_PD_MAPPER=m`, is created by `qcom_common` as the
  `pd-mapper` aux device and needs no files; no userspace pd-mapper is installed); `qcdxkmsucpurwa.mbn`
  (X1P zap shader); `qcvss8380.mbn` (the iris node is `status = "disabled"` in `hamoa.dtsi` and Denali does
  not enable it). Step 60 compares the Denali directory with the DT's `firmware-name` list.
- Audio: ooaklee `sp11-audio-v19c` topology and UCM. Its `x1e80100.conf` matcher lacks the 5G variant
  and is patched via `UCM_SP11_REGEX`. `alsa-ucm` ships `conf.d/x1e80100/x1e80100.conf` as a symlink;
  the support RPM replaces it and re-applies on an `alsa-ucm` trigger.
- Wi-Fi: WCN7850, PCI 17cb:1107, `qmi-board-id=255`; no exact `board-2.bin` entry, so the 17cb:3378
  entry is extracted with `ath12k-bdencoder` as `board.bin`. `disable-rfkill` is in the Denali DTS.
  `board-2.bin` is identical in the F44 (20260910) and F45 Beta (20260810) `atheros-firmware` packages.
- Bluetooth address: the controller enumerates without a public address; `sp11-bt-set-addr.c` (OE
  commit 69f40d5) sets it over raw HCI management before `bluetooth.service`, triggered by udev.
  Upstream's `parse_mac` copies the printed octets in order, but the MGMT payload is a little-endian
  `bdaddr_t`, so the unpatched helper sets the byte-reversed address; `30-build-support-rpm.sh` patches
  `out[i]` to `out[5 - i]` before compiling. The helper validates the index and the address itself;
  `sp11-bt-apply` only maps the unit instance `hciN` to `N`.
- Pen: unmodified upstream iptsd 3.1.0 (`a83bc1232f7096f8b33b50fdbda249cd640de670`) on the kernel's
  HIDRAW bridge (`hidraw` parent `001C:045E:0C83.*`, created by `mshw0485_touch` with `ipts_hid_bridge`
  defaulting to on); integration templates from OE `userspace/iptsd-sp11`; the build needs cmake for
  meson to find Microsoft.GSL. The kernel's own "Microsoft Surface G6 Pen" input device is silent by
  design; inking comes from the `sp11-iptsd@dev-hidrawN.service` started by the udev rule.
- Live media boots with `modprobe.blacklist=qcom_q6v5_pas rd.driver.blacklist=qcom_q6v5_pas` (an ADSP
  restart resets USB-C while rooted on USB), so no audio or battery in the live session; the installed
  system drops those arguments via the kernel-install plugin and `sp11-first-boot.service`. Anaconda carries
  neither argument into the boot entry, but turns the first into `/etc/modprobe.d/anaconda-denylist.conf`,
  which the kernel-install plugin removes before Anaconda rebuilds the initramfs. (`module_blacklist=` would
  avoid that file, but the kernel logs it with `pr_err` on every load attempt.)
- Windows dual-boot: `/etc/grub.d/29_sp11_windows` + `/usr/libexec/sp11/sp11-grub-modules` (copies
  `chain.mod` and its dependency closure from `moddep.lst` into `/boot/grub2/arm64-efi`; run by the
  generator on every grub2-mkconfig and by an RPM trigger on `grub2-efi-aa64-modules`, which keeps the copy
  matched to the GRUB image). Booting Windows through this entry works on the tested unit.

## Sensors (Snapdragon Sensor Core)

- **No sensor is on a bus Linux can see.** Windows' `Sensor` class holds two ACPI stubs, `MSHW048A` (display) and
  `MSHW048B` (keyboard, "Qualcomm All-Ways Aware Sensor Platform Device", `qcSensors.dll`: a QMI/protobuf client,
  `sns_client.pb`, `sns_suid.pb`, `sns_surface_imu.pb`). The chips, from the registry JSONs: ST LSM6DSV accel+gyro on
  the SSC's I3C buses 2 (display) and 1 (keyboard), AKM AK0991x magnetometer on I2C 4/3, AMS TCS3430 ALS/colour on
  I2C 4, TMD2755 ALS/prox, LPS22DF barometer on I2C 7, all on QUP instances the ADSP's sensor framework (SSC,
  protection domain `sensor_pd` inside `qcadsp8380.mbn`, `adsps.jsn`) owns. The Denali DTS has no sensor nodes
  (`&i2c0`/`&i2c4` carry "Something @…" comments only); the T14s bit-banged LIS2DW12 is a different board.
- Kernel: nothing to change. `CONFIG_QCOM_FASTRPC=m` with the ADSP `fastrpc` node (`hamoa.dtsi:4372`,
  `qcom,non-secure-domain`, hence `/dev/fastrpc-adsp`), `FASTRPC_IOCTL_INIT_ATTACH_SNS`, `QRTR`/`QRTR_SMD=m`,
  `qcom_pd_mapper` advertising `msm/adsp/sensor_pd` for x1e80100. Installed system only: the live session
  blacklists the ADSP.
- Stack (denisix/ubuntu-surface-pro-11 `SENSORS.md` reports 13 sensors working on an SP11 this way): `hexagonrpcd -s`
  attaches to the sensors PD and serves the DSP a virtual tree from `-R DIR`: `/vendor/etc/sensors/config` ←
  `DIR/sensors/config/`, `/vendor/etc/sensors/sns_reg_config` ← `DIR/sensors/sns_reg.conf`,
  `/persist/sensors/registry/registry` ← `DIR/sensors/registry/`, `/sys/devices/soc0/*` ← `DIR/socinfo/*`
  (`rpcd_builder.c`); without `-R` it guesses `/usr/share/qcom/<qcom,SOC>/<first word of model>/<device>` from the DT,
  `x1e80100/Microsoft/denali-oled` here. `libssc` finds `QMI_SERVICE_SSC` (0x190 = 400) on QRTR. Upstream
  iio-sensor-proxy 3.9 has `drv-ssc-{accel,light,compass,proximity}.c` behind `-Dssc-support`; Fedora builds it
  `disabled` (no libssc package), its udev rule enables `ssc-light ssc-compass` on `fastrpc-adsp*`, `ssc-accel` is
  the opt-in, its unit already allows `AF_QIPCRTR`. Fedora's `iiosensorproxy_t` has no `qipcrtr_socket` rule, so
  `sp11-sensors` loads a CIL module.
- Inputs. Unelevated: `DriverStore/FileRepository/surfacepro_snscfgcrd8380.inf_*` (65 JSON, `json.lst`,
  `sns_reg_config`, `golden_color_calibration.bin`, the platform files `hw_platform`=CRD, `soc_id`=615,
  `revision`=3.1, …). **Every text file there is CRLF.** `sns_reg_config`, `json.lst` and the platform files are
  shipped as LF (step 45 strips the CR, step 46 refuses one): the DSP kept the CR in the values it parsed and asked
  hexagonrpcd for `.../registry\r/sns_secure_database.bin` (round 2 on the device, 101-byte message, exactly one
  CR), so with the Windows bytes it never found its registry. The JSON configs (CRLF inside JSON is whitespace) and
  the registry files stay as Windows has them; denisix ships the same set that way. Windows' `json.lst` is not exact: it names
  `8380_crd_tcs3430_0.json` twice and omits `sns_cal.json`, so step 45 ships every JSON of the package and asserts
  the unique listed set exists (the list itself stays as Windows wrote it). Elevated only (SYSTEM/Administrators ACL, denied
  to WSL and unelevated PowerShell): `C:\Windows\System32\drivers\DriverData\Qualcomm\fastRPC\persist\sensors\registry\registry\`
  (the pre-parsed registry the framework wrote under Windows, per unit: platform data and calibration; denisix:
  321 files, the framework does not initialise without it, the JSON path needs an Android-only `oemconfig.so`) and
  `...\fastRPC\vendor\etc\sensors\config\` (calibration overrides). `Start-Process -Verb RunAs` on a cancelled UAC
  prompt returns no process object, so `exit $p.ExitCode` is 0: step 75 treats that as failure explicitly.
- Packaging: `hexagonrpc` 0.5.0 (commit pinned in `sp11.conf`; meson puts its units under libdir = `/usr/lib64`,
  the spec moves them; `sscregistrygen` is built but not installed upstream; adds the `fastrpc` sysusers entry and
  a `GROUP=fastrpc, MODE=0660` rule for `fastrpc-*`; built with `-Dhexagonrpcd_verbose=true`; releases 2 and 3
  carried the sensor-framework write support as a patch in `files/sensors/` (see the third and fourth device
  runs below); since release 4 the pin is the project's fork, `HEXAGONRPC_REPO`
  github.com/FadyAckad/hexagonrpc, branch `sp11-sensors` = upstream 598b591 plus the same four commits, no patch
  in the repo; `git_pin` fetches the commit by full hash, which GitHub serves for any reachable commit), `libssc`
  0.4.4+ (`libssc.so.2`; meson declares the QMI mock
  server unconditionally: `python3-devel`, `protobuf-compiler` for `protoc`, `protobuf-c-compiler` for
  `protoc-gen-c`; the spec deletes the installed mock server), `iio-sensor-proxy` = Fedora's SRPM of the target
  release with `-Dssc-support=enabled`, release `<fedora>.sp11.1` (step 45 refuses an SRPM with patches: refresh the
  template), `sp11-sensors` (payload under `/usr/share/qcom/x1e80100/Microsoft/denali-oled`, `files/sensors/`).
  Codeberg serves `git fetch --depth 1 origin <sha>` only with the full hash (`git_pin` uses it).
- Runtime design: udev `SYSTEMD_WANTS` on the `fastrpc-adsp` misc device starts `hexagonrpcd-adsp-sensorspd.service`
  (drop-in since 1.3: `-R /var/lib/sp11/hexagonrpc`, `ExecCondition=+sp11-sensors-guard`, `Restart=on-failure`,
  `RestartSec=5`, `StartLimitBurst=4` per 5 min; the stock `[Install]` stays unused because the node exists only
  after the ADSP booted. 1.3 had the guard as `ExecStartPre` with `RestartPreventExitStatus=3`, which does not
  work: that setting covers the main process only, and on the host's systemd 259 an `ExecStartPre` exit 3 was
  restarted four times until the start limit, while an `ExecCondition` exit 1-254 skips the unit without a
  failure, hence 1.4) and `sp11-sensors-online.service`, which polls `qrtr-lookup`
  (row format `%9u %7u %8u %4u %5u %s`, header line first) for service 400 and then `try-restart`s
  iio-sensor-proxy: the proxy probes SSC sensors on the udev "add" only, seconds before the DSP has read the
  registry (since 1.5 the restart is skipped when `busctl` already shows `HasAccelerometer` and `HasAmbientLight`
  true: with an accepted registry the framework is up within a second of the attach and the proxy's own probe
  finds the sensors, as the fourth device run showed). The daemon serves `/var/lib/sp11/hexagonrpc`: links to the
  package's `sensors/config`, `sensors/sns_reg.conf` and `socinfo`, and `sensors/persist/` (1.5; `fastrpc`-owned,
  mapped to the DSP's `/persist/sensors/registry`) holding the `C`-copied registry in `persist/registry/`.
  `sp11-sensors-resume.service` restarts the daemon `After=suspend.target` (the stock unit has
  `Conflicts=suspend.target`, and nothing restarts a conflict-stopped unit; `sleep.target` is the wrong anchor, it is
  active before the suspend). `91-sp11-sensors.conf` excludes `iio-sensor-proxy`; libdnf5 appends `excludepkgs`
  across drop-ins (verified with `dnf --dump-main-config` in the 45 Beta root: kernel list plus iio-sensor-proxy),
  and the exclusion also filters a local RPM of the package ("from @commandline is filtered out by exclude
  filtering", verified in the same root): the four RPMs go in one transaction, a later SP11 build of the proxy
  needs `--setopt=disable_excludes='*'`.
- ADSP safety: nothing in the stack writes `/sys/class/remoteproc/*/state` (step 45 greps the stage for it;
  `sp11-sensors-check` only reads it). hexagonrpcd only attaches to the existing sensors PD (`INIT_ATTACH_SNS`),
  never creates a PD (`-c`) nor supplies DSP libraries (`dsp/` absent → empty), and serves Windows' own bytes. Its
  exit leaves the sensors running on the DSP (denisix: the stock daemon exits on an unimplemented write after the
  registry is read; hence the restart policy). Stopping the ADSP through remoteproc resets the SoC (denisix).
- First device run (2026-09-19, `sp11-sensors` 1.0 on the 45 Beta install): the daemon attached
  (`INIT_ATTACH_SNS`), both remoteprocs stayed `running` through two suspend/resume cycles (the resume unit
  re-attached), audio unaffected, SELinux enforcing with no AVC, so the stack is safe for the ADSP. But the
  registry never reached the DSP: `sp11-sensors-online` found QMI service 400 already registered at attach time,
  the DSP requested only `oemconfig.so` after the attach, and every `ssccli`/proxy request ended in libssc's
  "'registry' sensor timed out after 30s, is hexagonrpcd running?". Cause, from the kernel: the PAS driver's
  `RPROC_AUTO_BOOT_RESTART_IF_FW_AVAILABLE` restarts the UEFI-started ADSP with the Linux firmware at probe
  time (`rproc_boot`, "restarting adsp with new firmware"), and on the installed system that probe happens in
  the initramfs (dracut's `qcom-adsp` pre-udev hook loads the driver; the support policy and
  `devicetree-firmware` put the firmware there), before the LUKS prompt: the framework initialised ~20 s before
  hexagonrpcd could exist. The framework registers its QMI service regardless of the registry, so service 400 is
  no readiness signal; a reading (`ssccli --sensor light`) is. Fix in 1.1: the `95sp11-sensors` dracut module
  (payload + `hexagonrpcd` + `stdbuf` in the initramfs, pre-udev hook 31 after qcom-adsp's 30, polls for
  `/dev/fastrpc-adsp` up to 8 s, attaches an instance that dies at switch-root; `%posttrans` regenerates the
  running kernel's initramfs), the drop-in runs the daemon under `stdbuf -oL` (its `openat` log lines are on
  stdout, fully buffered on the journal socket, so 1.0 showed only stderr), and `sp11-sensors-wait` probes the
  light sensor instead of the service list. `ssccli` hangs in its synchronous registry lookup before its own
  `--timeout` applies, so a `timeout`-killed run prints nothing.
- Second device run (1.1): the initramfs hook attached 350 ms after the node, 20 ms after "adsp is now up", and
  the DSP refused it (`Could not attach to FastRPC node`: the sensors PD was not up yet; the hook did not retry).
  The root-side attach at 22 s showed, thanks to `stdbuf`, what the DSP asks for after every attach: `oemconfig.so`,
  then `<output dir>\r/sns_secure_database.bin`, then the directory: the CRLF defect above. So the framework does
  retry its registry on a listener attach; a correct payload may work from the root side alone, and the initramfs
  hook (1.2: re-attaches every 200 ms for up to ~60 s of failures) covers the boot-time read as well.
- Third device run (1.2, 2026-09-19 evening): a 1.1 boot had hung at a black screen before the LUKS prompt (never
  explained: the hung boot leaves no journal; the initramfs attach is the only new element in that phase), the next
  boot came up. With 1.2 the initramfs hook's first attach was refused (sensors PD not up 20 ms after the ADSP),
  the retry attached, the DSP asked for `oemconfig.so` and then method 24, on which upstream's daemon quits. The
  root-side attach at 25 s then logged `Tried to open /persist/sensors/registry/registry/DIR for writing` (`DIR`
  is the framework's own 3-byte marker, present in the registry exported from Windows; a verification write test
  must not use that name), the daemon refused, and the kernel logged `fatal error received: err_qdi.c:1205:EF:sensor_process:0x4:sns_registry_4:
  0x67:sns_registry_sensor.c:279:SNS_RC_SUCCESS == rc`, `crash detected in adsp`, recovery in 5 s (which also took
  the CDSP down: `sleep_statsi.c:537`), `/dev/fastrpc-adsp` re-created, udev started the unit again, and so on every
  5 s: **an ADSP crash loop**, with the battery indicator flapping (battery status comes over pmic_glink from the
  ADSP). Stopped with `systemctl mask --now`, `dnf remove sp11-sensors`, `dracut -f`, reboot. So the registry
  initialisation of this firmware writes into its registry directory (method 24 = `apps_std_fremove`, sc
  `0x18020000`: 2 in, 0 out; then `fopen(.../DIR, w)`) and asserts when a write is refused; denisix's private
  hexagonrpcd patch ("method 24 stub", "write support") is exactly what got them past it. The DSP repeats the
  registry initialisation on every attach, so an early attach is not needed. Fix in round 4: `hexagonrpc`
  0.5.0-2 with a patch, since release 4 the fork's commits (hexagonfs gains create/write/truncate/unlink/rename
  for mapped directories; `apps_std` gains `fopen` 0, `fwrite` 5, `fsync` 23, `fremove` 24, `ftrunc` 32,
  `frename` 33, and `fopen_with_env` opens `w`/`a`/`+` modes read-write and accepts absolute names with unknown
  search variables; `invoke_requested_procedure` answers unsupported requests with `AEE_EUNSUPPORTED` and empty
  output buffers instead of ending the session; the method ids follow quic/fastrpc `inc/apps_std.h`, the
  extended ids > 30 travel in the first prim word); a harness against the patched hexagonfs covers
  create/write/append/truncate/rename/remove and refusal outside mapped directories. `sp11-sensors` 1.3 serves
  `/var/lib/sp11/hexagonrpc` (tmpfiles: links to the package's config/sns_reg.conf/socinfo, a `C`-copied registry
  owned by `fastrpc`; `sp11-sensors-reset` rebuilds it), drops the initramfs module (its `%posttrans` `dracut -f`
  stays to purge the 1.1/1.2 hook), and adds `sp11-sensors-guard`: no attach once `crash detected in adsp` is in
  the boot's kernel log, at most 12 attaches per boot, exit 3. 1.3 ran the guard as `ExecStartPre` with
  `RestartPreventExitStatus=3`; transient test units on the host's systemd 259 showed that combination restarting
  the failed pre-start four times until the start limit (the setting judges the main process only), while an
  `ExecCondition` exit 1-254 skips the unit without a failure (`Skipped due to 'exec-condition'`, no restart), so
  1.4 runs it that way and 46 asserts the drop-in carries neither of the two settings. 46 also verifies the upgrade
  path the device takes: with `SENSORS_PREVIOUS_RPMS="<hexagonrpc 0.5.0-1> <sp11-sensors 1.2>"` it installs the
  previous release into a fresh overlay, masks the unit as the owner did to stop the loop, and puts the current
  two on top with `rpm -U` and scriptlets: hook removed, working copy created, mask kept, policy module present.
  46 passes (104 checks, among them a write as the `fastrpc` user into the copy and the patched daemon's strings
  in the RPM); handed over as round 4 (1.4 replaced 1.3 in the folder before any device run). Not run on the
  device yet.
- Fourth device run (hexagonrpc 0.5.0-2 + `sp11-sensors` 1.4, 2026-09-19 night): **sensor data for the first
  time**. Without the initramfs hook the ADSP still boots in the initramfs, but `/dev/fastrpc-adsp` appears only
  with the root's udev (17.8 s); the daemon attached at 18.4 s (guard exit 0, attach count 1). The DSP read
  `sns_reg_config`, stat'ed and **removed** `sns_secure_database.bin`, removed every registry entry (341 `remove(`
  lines) and re-parsed the JSON configuration (so the framework parses JSON without `oemconfig.so`, contrary to
  denisix's note); it then opened `/persist/sensors/registry/fstempfile` for writing (ENOSYS: the registry's
  parent is a virtual directory in `rpcd_builder.c`), missed two entries it had not been able to write, opened
  `sns_secure_database.bin` for writing and wrote it with an input buffer longer than the 256 bytes the listener
  inlines, on which upstream's listener quits (`Large (>256B) input buffers aren't implemented`, exit 0, 1.1 s
  after the start; `Restart=on-failure` leaves it). The sensors ran regardless for the rest of the session:
  `ssccli` light 12 lux, accelerometer/gyroscope/magnetometer/compass streams, `monitor-sensor` light + compass +
  orientation, iio-sensor-proxy's own probe at 19.6 s had already found the SSC sensors (the wait unit's restart
  at 24 s was redundant), SELinux enforcing with no AVC, no ADSP crash, battery steady. Why the re-parse: the
  registry's `sns_reg_config` entry records the **mtime** of every parsed JSON (62 of the 65 DriverStore JSONs and
  the two Surface calibration overrides match their Windows file times to the second; the two overrides are what
  the framework parsed, not the DriverStore copies), and the payload's files carried the build time (`install`
  without `-p`, then rpm's clamping to the changelog date), so every file counted as changed. Orientation:
  `bottom-up` with the device upright on its kickstand (accel x=+0.77, y=+7.39, z=+6.35 m/s²): the Sensor Core
  reports the Android convention (reaction force; x right, y up, z out of the screen; libssc's own matrix from
  the SSC placement attribute is all zeros → identity), while iio-sensor-proxy's `test-orientation.c` wants y<0
  for normal, x>0 for left-up, and `tilt_calc` z>0 for face-up. One CDSP crash (`sleep_statsi.c:537`,
  "handling crash #1 in cdsp", recovered in 5 s) at 24.16 s, 130 ms after the wait unit began restarting
  iio-sensor-proxy (every sensor stream closed); none in rounds 1-2, and in round 3 the CDSP fell with the same
  assert 5 s after the ADSP crash: the CDSP firmware's sleep-stats code trips on some ADSP/sensor state change.
  Unexplained; nothing on Linux uses the CDSP.
- Round 5 (hexagonrpc 0.5.0-3, `sp11-sensors` 1.5): the listener fetches long input buffers with
  `adsp_listener_get_in_bufs2` (method 5 of the interface, quic/fastrpc `inc/adsp_listener.h`; the first 256
  bytes arrive with `next2`, the rest is fetched from offset 256 as `listener_android.c` does); the builder maps
  `/persist/sensors/registry` as a whole to `DIR/sensors/persist` when that directory exists (`fstempfile`, then
  the rename into `persist/registry/`; otherwise the upstream layout), so the working copy is
  `/var/lib/sp11/hexagonrpc/sensors/persist/registry` (tmpfiles, run from `%posttrans` since 1.6: on an upgrade
  `%post` runs while the previous release's payload files are still in place, and the copy took 1.4's
  `sns_reg_version` along, caught by 46's upgrade section; `%posttrans` also removes the 1.3/1.4 copy); the payload
  keeps Windows' mtimes (`install -p`, `source_date_epoch_from_changelog 0` and
  `clamp_mtime_to_source_date_epoch 0` in the spec; 46 compares two JSONs' mtimes with the registry's stamps and
  tmpfiles' `C` keeps them, as the device showed for `tdm_uid.bin`); `ACCEL_MOUNT_MATRIX="-1,0,0;0,-1,0;0,0,1"`
  on the fastrpc-adsp node (the x flip is inferred from the Android convention, not yet seen);
  `sp11-sensors-wait` restarts the proxy only when `busctl` shows it without accelerometer or light sensor; the
  check counts crashes per remote processor and prints the daemon log's tail. 45+46 pass (118 checks, the
  upgrade from the round-4 packages included; the RPM carries the JSONs with mtime 1747743184 and the overrides
  with 1789827151, the registry's stamps). Handed over as round 5, not run on the device yet. The hexagonrpc
  changes also exist as four topic commits (hexagonfs write ops, apps_std methods, listener, builder;
  `git format-patch` series in the round-5 folder, identical to the patch): the sustainable form is a fork of
  linux-msm/hexagonrpc pinned by `HEXAGONRPC_REPO`/`HEXAGONRPC_COMMIT` (no patch in this repo) and a pull request
  upstream, both the owner's to create; until then the patch stays as the build input.
- 1.6 (same night, replacing 1.5 before any device run): Windows keeps `sns_reg_version` (9 bytes, `version=1`,
  no line ending) and `parsed_file_list.csv` (CRLF, written by the DSP itself, kept byte for byte) in the
  registry's **parent** directory (`persist\sensors\registry\`), and `75-export-sensor-registry.sh` copies them
  from there into the entries export (its line 47); served among the entries, the DSP deleted them as stale
  entries in round 4 and then tried to create `sns_reg_version` (the `fstempfile` open). Step 45 moves them to
  the payload's `sensors/registry-parent/` and tmpfiles `C`-copies them beside the registry copy
  (`sensors/persist/`); 46 asserts both places. This matches psacal's report in upstream PR #21 (SC8280XP,
  Windows firmware: the DSP creates `sns_reg_version` through method 5 when it is missing, and a JSON-format
  `sns_reg_config` makes it "generate oversized messages", i.e. the large input buffers).
- Upstream state (checked 2026-09-19 against linux-msm/hexagonrpc): no pull request carries these changes. PR #21
  (z3ntu, draft since 2026-03-20, for issue #19 "Support opening files for writing", the same
  `.../registry/registry/DIR` refusal as round 3) stubs `fwrite` (accepts the `DIR` marker and a `version=`
  string, nothing reaches disk), mocks `fremove`, hard-codes `fopen_with_env_fd`, and adds an `sns_reg_version`
  mapping in the registry's parent; it conflicts with main since the interface rework (PR #13) and its author
  has little time. Maintainer guidance in that thread (lumag): real writes belong in a writable directory under
  `/var`, attempts to modify `/usr/share/qcom` should fail loudly; our series does that (writes go into the
  `-R` tree the daemon is pointed at, the package stays read-only). Nobody implements the large-buffer fetch,
  the temporary file's directory, `ftrunc`/`frename`/`fsync`. Main has not moved past 598b591; none of the 14
  forks carries write support beyond z3ntu's branch. Owner's decision: fork only for now
  (github.com/FadyAckad/hexagonrpc, created 2026-09-19 with main = 598b591), no pull request yet; the four-commit
  series in the round-5 folder references issue #19 and PR #21 for later. The `sp11-sensors` branch was pushed
  on 2026-09-20 (head 7a7c4f1, the four commits with the owner as author and committer, no other trailer); since
  then `HEXAGONRPC_REPO`/`HEXAGONRPC_COMMIT` point at the fork, `Patch0` and the patch file are gone, the release
  is `4.git7a7c4f1.sp11` (the numeric part must rise: rpm compares `git<hash>` as a string), and step 46's
  upgrade section covers 0.5.0-3 → 0.5.0-4 with `sp11-sensors` 1.6 kept. A fifth commit followed the same day
  (head `79d1bed`, release `6.git79d1bed.sp11`): fixes to the write paths the other four added, on the device
  since 2026-09-21 — see the round-7 bullets below.
- Fifth device run (hexagonrpc 0.5.0-3 + `sp11-sensors` 1.6, 2026-09-20 00:17, check at 00:20): **the stack
  works as designed.** Node at 17.9 s, attach at 18.5 s (guard 0, attach count 1), the daemon `active (running)`
  two hours later. The DSP read `sns_reg_config`, then the whole `sns_secure_database.bin` (75 reads of 512 plus
  121 bytes = 38521, the exported file's size), listed the registry and **kept it**: no `remove(` lines, the 343
  entries still carry their Windows dates, the served JSON's mtime equals the stamp in the registry's
  `sns_reg_config`. It then rewrote `parsed_file_list.csv` (15817 → 15478 bytes) and the secure database in one
  38521-byte write (76 `write(5, ...)` lines, no "Large"/"Could not fetch" line). No ADSP crash, **no CDSP crash**
  (the proxy's own probe found the sensors at 19.7 s, `sp11-sensors-wait` logged "already has the sensors, no
  restart"). `monitor-sensor`: orientation `normal`, tilt `vertical` then `tilted-up` with the device upright, so
  the mount matrix is right for landscape; light 18 lux; accelerometer/gyroscope/magnetometer/compass streams;
  `ACCEL_MOUNT_MATRIX` visible on the udev node; SELinux enforcing, no AVC. Artefact: the check's `find -newer
  tmpfiles.conf` said 0 although the DSP wrote, because the clock was two hours behind at boot (RTC/Windows
  mismatch, see the diag notes) when the DSP wrote and the tmpfiles config was installed with the corrected clock
  minutes earlier; the next check version should compare against `/run/sp11-sensors/attaches` (same clock
  domain as the writes) and print the DSP's write activity (`openat(..., w`, `remove`, `rename`, `Could not`)
  instead of head/tail only. Round-4's `remove(sns_secure_database.bin)` was therefore part of the re-parse the
  mtime mismatch caused, not a per-boot habit.
- Unknowns after the fifth run: the portrait orientations (x flip inferred, not yet reported), suspend/resume
  with the writing daemon (the resume unit re-attaches; the DSP then checks its own persisted registry), whether
  the CDSP assert stays away, AVCs beyond `qipcrtr_socket`.
- Round 7 (hexagonrpc 0.5.0-6, `sp11-sensors` unchanged): the write support of rounds 4 and 5 had defects that
  review found afterwards, none of which the device ran. `hexagonfs_close` destroyed a descriptor while a
  second file number still referenced it (a walk ending on `.`, `..` or the search directory hands one out),
  which is exactly what the close inside create/unlink/rename freed, and `fastrpc_apps_std_deinit` ascended
  from the root although destroying a descriptor walks its `->up` chain; `hexagonfs_mapped_or_empty_ops`
  pointed `.write`/`.truncate` at the implementations that dereference a NULL context, so a write to an absent
  mapped directory dereferenced NULL instead of returning `-ENOENT`; `outbufs_calculate_size` padded
  zero-length buffers `outbufs_encode` never writes (an overstated length and uninitialised bytes on the wire)
  and `alloc_outbufs4` did not skip the method id an extended method carries in the first primitive word;
  `'+'` implied `O_CREAT`; `stat` claimed the write bit for read-only files, which sends the DSP down a write
  path that can only fail; a short `write(2)` was reported as an error; and the persist layout was probed at
  `DIR/sensors/persist` rather than at the registry inside it, so a persist directory without one would hide
  the packaged registry behind a tree nothing can create at runtime. `rpm/hexagonrpc.spec.in` gained a
  `%check` running upstream's three unit tests in the buildroot (two of them compile the changed files:
  `iobuffer.c`, and `hexagonfs.c` with `hexagonfs_mapped.c`), and step 46 asserts the new probe constant in
  the daemon. Nothing under `files/sensors/` had to change — the tmpfiles file already creates
  `…/sensors/persist/registry`, which is what the stricter probe needs — so the rebuilt `sp11-sensors` is
  payload-identical (`rpm -qp --dump`: same paths, sizes and digests) to the one on the device and is not
  handed over. The fork's commit was amended the same evening (2026-09-20 22:28) before anything was handed
  over (head `79d1bed`, comment wording only, no code line changed), hence release 6 rather than 5.
- Round 7 result (hexagonrpc 0.5.0-6 on the device, 2026-09-21, checks at 10:00 and, after three
  suspend/resume cycles, 10:03): **the write paths hold, and the stack survives suspend.** The daemon started
  at 19.1 s; the DSP read `sns_reg_config`, kept the registry (no `remove(` line) and, all within a second of
  the attach, made the same per-boot writes Windows makes: the `DIR` marker, `parsed_file_list.csv` (15478
  bytes), `sns_secure_database.bin` (38521 bytes, three times), `sns_ccd.json.ccd_te0_sensor0` (815 bytes) and
  `qsh_camera.dbg_flags` (295 bytes). The last two carry 2026-09-19 dates in the Windows export while the
  other `sns_ccd`/`qsh_camera` entries date from 2026-06-02, so Windows refreshes them on every boot as well.
  Refused with ENOENT, the DSP continuing past each: `oemconfig.so` and `sns_tppe.so` (DSP libraries, which
  hexagonrpcd deliberately does not serve) and `c:/Data/test/cam_registry_dump.txt` (a camera debug dump to a
  Windows path); no `Unsupported`, `Refusing` or `Large` line. All five sensors streamed, `monitor-sensor`
  reported orientation `normal`, tilt and light, SELinux enforcing without an AVC for the stack's domains, no
  ADSP crash. Suspend/resume (open since the fifth run): the daemon stopped with each suspend
  (`Conflicts=suspend.target`) and `sp11-sensors-resume` restarted it (attach count 4); on those re-attaches
  the DSP made no file request at all (263 `write(` lines in both checks, no file newer than the attach
  marker), because it does its registry work once per ADSP boot and the ADSP stays up through suspend; after
  the third resume all five sensors streamed again, no ADSP crash. One CDSP crash, `sleep_statsi.c:537` at
  149.95 s, recovered in 136 ms, before any suspend and ~130 s after the daemon's last request; through the
  boot clock's two-hour offset it falls within about a second of the first check closing its magnetometer
  stream and opening the compass stream. It is the same assert as in the fourth device run (130 ms after
  iio-sensor-proxy's restart closed every stream) and in round 3, and the fifth run's check ran the same
  streams without it: a CDSP firmware fault triggered intermittently by sensor streams starting or stopping on
  the ADSP, not by the daemon or by suspend. Nothing on Linux uses the CDSP (`/dev/fastrpc-cdsp` has no
  client) and no stream was interrupted; tracked, not fixed.

## Bluetooth dual-boot pairings

- Windows keeps LE bonds in `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys\<adapter>\
  <device>`: `LTK` (16 B), `KeyLength`, `ERand` (QWORD, little-endian → BlueZ `Rand` decimal), `EDIV`,
  `IRK`, `AddressType` (1 = random), `AuthReq` (0x04 MITM). The `Keys` key is SYSTEM-only, but
  `reg save` of the parent `Parameters` key works from an elevated prompt.
- BlueZ `info` fields: `[LongTermKey] Key/Authenticated/EncSize/EDiv/Rand` where `Authenticated` is the
  MGMT LTK type (0 legacy, 1 legacy+MITM, 2 SC, 3 SC+MITM); `[IdentityResolvingKey] Key`;
  `[General] AddressType=static|public`. Windows' `AuthReq` is the requested value (the keyboard shows
  the SC bit yet has non-zero EDIV/Rand), so the converter decides Secure Connections from
  `EDIV == ERand == 0` and MITM from AuthReq bit 0x04. Both Surface devices: legacy pairing, authenticated,
  static addresses. Keyboard USB ID 045E:0C7A, pen 045E:0C0F.
- `scripts/70-export-bt-pairings.sh` (WSL, one UAC prompt, always exports afresh because a re-pairing
  rewrites the keys in place) → `build/out/sp11-bt-pairings.tar.gz`;
  converter `scripts/bt-pairings-from-hive.py` (python3-hivex, LE only, filtered by `BT_PAIRING_USB_IDS`);
  importer `/usr/libexec/sp11/sp11-bt-import-pairings` (also inside the tarball). Verified on 44
  Workstation (keyboard connects over BLE with battery reporting) and 45 Beta Workstation (keyboard and
  pen connect without pairing again).

## Hardware-verified status

### Fedora 44 GA Workstation (2026-09-13/14, support RPM 1.7)

Working: boot, install, display/GPU, Wi-Fi, Bluetooth with the correct address, touch, pen inking,
audio, battery, Flatpak, Windows entry in GRUB before UEFI Firmware Settings, shared Windows pairings
for keyboard and pen, `sp11-bt-import-pairings` and `sp11-diag` under `/usr/libexec/sp11`. Suspend and
resume confirmed on 2026-09-17.

Support RPM 1.7 (`sp11-diag` enumerates paired devices instead of fixed addresses; otherwise identical
to 1.6, which added `sp11-grub-defaults` and the dnf kernel exclusion) was confirmed working on the
installed system on 2026-09-14. `sp11-iptsd` 3.1.0-2.sp11 restarts the running pen daemon on upgrade.
The ISO in `build/out/` (sha256 `eb62a087…7fee`, 2026-09-14 evening) contains both.

### Fedora 45 Beta 1.3 Workstation (2026-09-16)

Built with `FEDORA_TARGET=beta` and installed on the tested unit, onto a LUKS-encrypted root. Confirmed:
the media boots and installs, the installed system runs (dnf, desktop applications), and the SP11 kernel is
the booted one. `qcom_q6v5_pas` loads on the installed system, so the live-only blacklist is being dropped
as intended.

`dnf upgrade --refresh` on the fresh install added a stock `kernel-uki-dtbloader-7.2.5-300.fc45` boot entry,
because the exclusion list predated that package; support RPM 1.8 adds `kernel-uki-*`, 1.9 corrects the
dnf5 override hint and 2.0 adds the Adreno microcode to the initramfs. Removing the stray kernel needed
`dnf --setopt=disable_excludes='*' remove`.

Benign boot-time messages on this unit: `qcom_pmic_glink … Failed to create device link (0x180) with
supplier …` for the PD and USB nodes (probe deferral, retried); `surface_hid … unexpected descriptor length:
got 0, expected 9` then `error -71` for one Surface Aggregator HID endpoint that nothing depends on.

Confirmed working on the installed system by the owner on 2026-09-16: Bluetooth, audio, pen, Wi-Fi,
battery, Flatpak and the Windows GRUB entry; in a second round the same day, keyboard/touchpad, GPU
acceleration, the Bluetooth pairing import, no early-boot Adreno error with support RPM 2.0, a clean
`dnf upgrade --refresh` after the `kernel-uki-*` exclusion, and support RPM 2.1 as an upgrade (stock kernel
removed, `dracut --regenerate-all -f` clean). The 44 GA list above carries over to 45 Beta. Suspend and
resume confirmed on 2026-09-17.

### Kernel 7.2.5 on Fedora 45 Beta Workstation (2026-09-17)

`kernel-sp11-7.2.5-sp11v23` (`KERNEL_STABLE_VERSION=7.2.5`, built with `FEDORA_TARGET=beta`) installed next
to 7.2.0 on the 45 Beta install. Confirmed working by the owner: Bluetooth, touchscreen, Wi-Fi, pen,
suspend and resume, speakers, microphone, GPU acceleration, keyboard/touchpad, battery, Flatpak, the
Windows GRUB entry, the keyboard and pen pairings shared with Windows, backlight control (brightness
slider) and multi-touch (rjindael/fedora-surface-pro-11's HID-over-SPI patches give single touch only).
7.2.5 is the build default since then; no ISO with it has been built yet.

### Kernel config policy rev 1, SELinux (2026-09-18)

`kernel-sp11-7.2.5-sp11v23.1` (`KERNEL_CONFIG_REV=1`, `FEDORA_TARGET=beta`) and support RPM 2.5, installed by
the owner as an update on the 45 Beta Workstation system next to the AppArmor kernels: boots, nothing
regressed (confirmed 2026-09-18/19). **SELinux is still disabled there**: the installation's boot arguments
carry `selinux=0` and its `/etc/selinux/config` says `disabled`, both written by the installer (see the
`liveinst` bullet in the Kernel section), so `sp11-diag` shows `getenforce: Disabled`,
an LSM list without `selinux` (`lockdown,capability,yama,bpf,landlock,ipe,ima,evm`, i.e. the policy build with
AppArmor gone and IPE in) and no relabel boot ever happened. After the manual enabling procedure (see the
`liveinst` bullet) the same system runs SELinux **enforcing** since 2026-09-19 (permissive first, no kernel AVC
in either mode; pen, Bluetooth and audio up under enforcing). Verified off-hardware before the hand-off: the shipped config differs from the AppArmor
build only by the policy and what it pulls in (`SECURITY_APPARMOR*` off, `IGH_ECAT*` off, `SECURITY_IPE` on with
its verity properties, `DEFAULT_SECURITY_SELINUX`, `CONFIG_LSM`, `ZSTD_COMPRESS` y→m because AppArmor's
`EXPORT_BINARY` had selected it built-in, plus `LOCALVERSION`/`VERSION_SIGNATURE`); 7816 modules (`ec_master`
gone, `zstd_compress` new); both Denali DTBs byte-identical to the AppArmor build; `36-verify-kernel-install.sh`
passes against the 45 Beta live root; `35-verify-support-rpm.sh` passes on both paths for 2.5. The ISO has not
been rebuilt. 2.5 was rebuilt on 2026-09-19 with `sp11-selinux-restore` under the same version (never released
before); the automatic restore was confirmed on the device the same day.

### Sensors stack (2026-09-19)

Built for Fedora 45 (`FEDORA_TARGET=beta`): `hexagonrpc-0.5.0-1.git598b591.sp11`, `libssc-0.4.4-2.git54dd13e.sp11`
(+devel), `iio-sensor-proxy-3.9-3.sp11.1` (the mock chain built all three on the first run), `sp11-sensors-1.0-1`
(this unit's registry: 345 files, 6 calibration overrides from `vendor\etc\sensors\config`, among them
`factory_color_calibration.bin`, `tdm_uid.bin`, `acs_multiplier.bin` and the Surface accel/gyro calibration JSONs
that replace the package's copies) and support RPM 2.6 (`sp11-diag` runs `sp11-sensors-check`; 35 passes on both
paths). `46-verify-sensors-rpms.sh` passes against the 45 Beta live root; the RPMs were handed over. 1.0 ran on the device
the same day (safe, no data; see the Sensors section); `sp11-sensors-1.1-1` with the initramfs module passes 46
(75 checks, including a dracut image built from the root's own dracut and inspected with `lsinitrd`) and was
handed over for the second round. 1.2 (round 3) ended in the ADSP crash loop described in the Sensors section.
Round 4, `hexagonrpc-0.5.0-2` plus `sp11-sensors-1.4-1` (46: 104 checks, including the in-place upgrade from
the round-3 packages), **produced sensor data on the device** on 2026-09-19: `ssccli` readings from the light
sensor, accelerometer, gyroscope, magnetometer and compass, `monitor-sensor` with light, compass and an
orientation (inverted, see the Sensors section), SELinux enforcing, no ADSP crash; the daemon stopped on the
framework's first large write and the orientation needs the mount matrix. Round 5, `hexagonrpc-0.5.0-3` plus
`sp11-sensors-1.6-1` (46: 128 checks, upgrade from round 4 included; 1.5 was replaced by 1.6 in the folder before
any device run), **ran on the device on 2026-09-20**: daemon running for the whole session, registry from Windows
accepted without a re-parse, the framework's secure database and file list written back, no ADSP or CDSP crash,
orientation `normal` upright, all five sensors streaming, SELinux enforcing without AVC (details in the Sensors
section). Portrait orientations and suspend/resume with this stack are not reported yet. The same morning the
patch left the repository: `hexagonrpc-0.5.0-4.git7a7c4f1.sp11` is built from the owner's fork (branch
`sp11-sensors`), 46 passes with it (125 checks, the upgrade from 0.5.0-3 with `sp11-sensors` 1.6 kept
included), and against 0.5.0-3 the daemon's and the library's `.text` sections are byte-identical, the
section list and sizes equal, only the build ids and rpm's package note differ; handed over as round 6
(optional on the device, which runs the identical 0.5.0-3).
Round 7 (2026-09-21): `hexagonrpc-0.5.0-6.git79d1bed.sp11` alone — fixes to the write paths of rounds 4 and 5
(descriptor lifetimes, the write operations of an absent mapped directory, the encoded output buffers, the `+`
mode, the reported write bit, short writes, and the persist probe), with upstream's unit tests now run in the
buildroot (`%check`, 3/3). 45+46 pass with no failure (127 `ok` lines; earlier rounds' counts predate the two
checks added here and are not comparable), the upgrade from 0.5.0-4 with the `sp11-sensors` package kept
included; the rebuilt package is payload-identical to the installed one, so only the daemon was handed over.
Ran on the device on 2026-09-21: registry kept, every per-boot write served, all five sensors streaming, and
intact through three suspend/resume cycles (the DSP makes no file request on a re-attach); one CDSP
`sleep_statsi.c:537` assert at a sensor stream change, recovered in 136 ms, not caused by the daemon.

## References

rjindael/fedora-surface-pro-11 (Fedora bring-up notes); ooaklee/linux-surface-pro-11-oe (kernel, audio,
iptsd releases, ADRs); ooaklee/lexr.sh `internal/image/fedora/*.go` (remaster design reference);
denisix/ubuntu-surface-pro-11 (`SENSORS.md`: the SSC sensor stack on an SP11 under Ubuntu); linux-msm/hexagonrpc;
DylanVanAssche/libssc (codeberg);
Fedora wiki "Snapdragon WoA Laptop Install"; Arch wiki "Bluetooth" (dual-boot pairing).
