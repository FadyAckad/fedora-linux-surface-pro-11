# Kernel
The ooaklee kernel (releases on ooaklee/linux-surface-pro-11-oe, "OE"): stable update, SP11 revisions, LSM, SELinux.

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
  previous kernel in GRUB as the fallback; the content pin described in `docs/pipeline.md` makes step 20 refuse
  the mismatch. `make kernelrelease` is a no-sync-config target and `setlocalversion`
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
