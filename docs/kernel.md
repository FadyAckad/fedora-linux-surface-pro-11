# Kernel
Fedora's kernel package rebuilt with the SP11 patch set: sources, build, revisions, configuration, rebase, install.

## Sources and packages

- The kernel is Fedora's own `kernel` source RPM for `FEDORA_RELEASE` (`KERNEL_SRPM`, sha256 pinned in `sp11.conf`;
  Koji keeps every build under `kojipkgs.fedoraproject.org/packages/kernel/<version>/<release>.fc<n>/src/`), rebuilt
  with the SP11 patch set (the commits `KERNEL_PATCH_BASE_COMMIT..KERNEL_PATCH_COMMIT` of the project's kernel fork,
  `KERNEL_PATCH_REPO`; manifest in `docs/kernel-patches.md`) and `payload/kernel-local`. The result is Fedora's
  package family with the same names, provides and scriptlets (`kernel`, `kernel-core`,
  `kernel-modules{,-core,-extra,-internal}`, `kernel-uki-dtbloader`, `kernel-devel`, ...), uname
  `<version>-<release>.sp11.<rev>.fc<n>.aarch64`. First build: `kernel-7.2.5-300.fc45` with revision 1, uname
  `7.2.5-300.sp11.1.fc45.aarch64` (2026-09-23); revision 2 (a CDSP boot-order patch, dropped again) the same day;
  revisions 3 and 4 (configuration additions only) on 2026-09-24; revision 5 (`kernel-7.2.7-300.fc45`, the patch
  set rebased onto `v7.2.7`) on 2026-09-25.
- Fedora's `linux-<version>.tar.xz` inside the source RPM is the stable tag's tree: for 7.2.5 byte-identical to
  kernel.org's `linux-7.2.tar.xz` plus `patch-7.2.5.xz`, for 7.2.7 every path, mode and blob of `v7.2.7`. Fedora's
  own `patch-7.2-redhat.patch` touches 61 files in 7.2.5 and 63 in 7.2.7, none of the patch set's (crypto and
  lockdown policy, secure-boot state in `/chosen`, some x86/s390, a few quirks).

## kernel.spec slots and the build

- `kernel.spec` provides the slots step 20 uses, so the spec's only edit is the buildid line:
  `# define buildid .local` becomes `%define buildid .sp11.<rev>` (step 20 dies unless exactly one such line
  exists); `Patch999999: linux-kernel-test.patch` (empty in the SRPM; `ApplyOptionalPatch` applies it when it has
  more than 9 lines) receives the patch set: step 10 writes the pinned commits out with `git format-patch` (from a
  shallow partial clone, `build/cache/kernel-patches.git`, about 5 MB), step 20 checks that the series rebuilds the
  pinned commit's tree (`kernel_series_check`: `git apply --cached` onto the base in a throwaway index) and
  concatenates it; `Source3001: kernel-local` (comments only in the SRPM) is merged into every configuration. The
  spec applies patches with `git --work-tree=. apply`, which is strict: no fuzz, exact hunk line counts (GNU `patch`
  accepted the old tablet-switch patch with a hunk one line short, `git apply` refuses it). `process_configs.sh`
  runs with checks that fail on a new symbol no configuration sets, which is why `kernel-local` sets
  `CONFIG_TOUCHSCREEN_MSHW0485=m` (the only symbol the patch set adds) and spells out every symbol Kconfig derives
  from its other lines.
- Build (step 20): `rpmbuild -bs` on the host with `dist .fc<n>` and `fedora <n>`, then `mock --rebuild` in the
  `MOCK_CONFIG` buildroot with `--uniqueext=sp11-kernel` (a root of its own, so the long build neither waits for nor
  blocks the root steps 40/45 use; `mock_rebuild_family` in `lib.sh`) and `KERNEL_MOCK_OPTS`: `--with baseonly` (no
  debug, realtime, perf, tools, selftests),
  `--without efiuki kmap doc headers cross_headers kabichk kabidwchk ynl`. Debuginfo stays on: `--without debuginfo`
  makes the spec set `CONFIG_DEBUG_INFO_NONE`, which drops BTF and the options that need it (sched_ext,
  `NET_SCH_BPF`, `IO_URING_BPF_OPS`, ...), so the configuration would no longer be Fedora's. `kernel-uki-dtbloader`
  is still built. Every binary RPM of the build except the `-debuginfo` and `-debugsource` packages lands in
  `build/rpms`; step 20's cache is the `kernel-core` RPM of the configured uname. The spec signs the image through
  pesign's rpmbuild helper; outside Fedora's build system the image stays unsigned, so Secure Boot stays off as
  before.

## Checks on the result

- Step 20's checks on the result: every `KERNEL_PKGS` package at the configured uname; `vmlinuz` and the Denali OLED
  DTB in `kernel-core` (compatible `microsoft,denali-oled`, a `microsoft,mshw0485` touch controller node); a driver
  in the packages for every enabled user of the RPMh power domains and of the interconnect in that DTB
  (`scripts/sync-state-drivers.py`: the module aliases `depmod` writes for the unpacked packages,
  `modules.builtin.modinfo`, and for built-in drivers that record no alias the compatible strings in the unpacked
  zboot image; see the sync-state bullet); the configuration equals the one in Fedora's own `kernel-core` of the
  same version (`KERNEL_STOCK_CORE_RPM`, pinned) plus exactly the `kernel-local` lines (and Fedora's own line of
  each symbol `kernel-local` overrides), compared in both directions and without the values Kconfig derives from the
  toolchain (`CC_VERSION_TEXT`, `GCC_VERSION`, `CC_HAS_*`, ...); the modules `mshw0485_touch`, `soundwire-qcom`,
  `snd-soc-wsa884x`, `surface_aggregator_registry` and the parameters `ipts_hid_bridge` and
  `sp11_feedback_active_offset2_zero`. The source RPM's `kernel-aarch64-fedora.config` is no reference: it is the
  input Kconfig resolves during the build (options with unmet dependencies drop out, derived ones are added).

## Revisions

- `KERNEL_SP11_REV` (in the buildid) and `KERNEL_SP11_REV_SHA256` (`kernel_rev_sha256` in `lib.sh`: the revision
  number, the effective `kernel-local` lines and the two pinned commits, whose ids fix the patch set) pin what a
  revision contains; step 20 refuses a patch set or fragment that differs and prints the value to set. Bump the
  revision with every change: `kernel-core` is install-only, and the same uname rebuilt with other content would own
  the installed kernel's `/boot` and module paths. A new Fedora kernel changes the uname by itself, but the patches
  change with the rebase, so it is a new revision too. The buildid must not contain `rt|auto|uki|64k|debug`, or
  `20-grub.install` does not make the kernel the saved default.

## Configuration

- Configuration: Fedora's (`CONFIG_LSM="lockdown,yama,integrity,selinux,bpf,landlock,ipe"`, SELinux default,
  `CRYPTO_FIPS=y`, zboot `vmlinuz`, EROFS with LZMA, XZ firmware). What the SP11 needs beyond the patch set is
  already there, but for the two drivers of the sync-state bullet: the Surface Aggregator stack
  (`SURFACE_AGGREGATOR_REGISTRY`, `_TABLET_SWITCH`, `SURFACE_HID`, `SURFACE_PLATFORM_PROFILE`,
  `SENSORS_SURFACE_FAN`, `BATTERY_SURFACE` — patch 0055 keeps it from binding on the SP11), battmgr and UCSI over
  pmic_glink, PAS remoteproc and pd-mapper, FastRPC and QRTR, ath12k, `BT_QCA`, the X1E audio drivers, GPI DMA,
  `SPI_QCOM_GENI`, `HIDRAW=y`, `KEYBOARD_GPIO`, `PINCTRL_QCOM_SPMI_PMIC`. `ARM_SCMI_CPUFREQ=m` does not load on its
  own (modpost cannot generate SCMI-bus aliases; ooaklee's config had it built in), so the support RPM loads it
  through `modules-load.d`, the fix Fedora's "Snapdragon WoA Laptop Install" wiki page gives.

## Extraction from v23.2

- The patch set and how revision 1 was extracted from the v23.2 kernel (ooaklee's linux_ms_dev_kit-sp11 v23, built
  on Ubuntu's qcom-x1e concept kernel and jglathe's X1E tree, plus the 7.2.5 update and the POS patch): see
  `docs/kernel-patches.md`. Method, for a future re-extraction: a blobless clone of ooaklee/linux_ms_dev_kit-sp11
  (`--filter=blob:none --shallow-since`, branch `lexr-0.3.0-demo` = `ce78e6eb`) gives the history; jglathe's 7.2.0
  head `746b3477` is the second parent of ooaklee's merge `cb825d66`, so `git diff 746b3477 ce78e6eb` is ooaklee's
  own work (89 files outside `debian*/` and `ubuntu/`), and `git log <v7.2>..746b3477` the jglathe base (709
  commits: 100 Ubuntu packaging, 24 AppArmor, 207 other boards' device trees, 376 left, of which 44 act on this
  machine, plus an rpmsg helper one of them calls). Which base commits act on this machine came from the built v23.2
  tree: the Denali DTB's enabled compatibles mapped through `modules.alias`/`modules.builtin.modinfo` to modules,
  their dependencies, and the source and header files kbuild's `.cmd` files list for them. A file-level comparison
  with the v23.2 source does not reveal a missing prerequisite commit: compile the touched directories with Fedora's
  configuration on the host (`make prepare modules_prepare`, then `make <dir>/ ...`, with Fedora's
  `Makefile.rhelver` copied into the tree) before the mock build (60 min on the WSL host).
- Carried as validated, not cleaned up: `gpi.c`, `spi-geni-qcom.c`, the AudioReach files and `lpass-wsa-macro.c` are
  7.1-based copies that leave out some 7.2 upstream changes (GPI `DMA_PRIVATE`, GENI SPI tracepoints, AudioReach
  push/pull and watermark support, an enum-control fix). ooaklee's own re-lift of the stack onto 7.2.2 lost touch,
  pen and the right speaker on the device, so any clean-up is a separate revision with its own device test.
- Patch 0042 (OLED link-rate quirk) matches `DMI_PRODUCT_NAME` exactly against "Microsoft Surface Pro, 11th
  Edition", so it never applies on the 5G SKU; the 5G unit's panel works without it. Every other SP11-specific code
  path keys on the `microsoft,denali` compatible, which both SKUs carry.
- The ADSP: mainline's PAS driver has the X1E ADSP's "lite" firmware IDs (`lite_pas_id` 0x1f, `lite_dtb_pas_id`
  0x29) and shuts the UEFI-started firmware down in `qcom_pas_load` before it boots the Linux one. v23 did the same
  through ooaklee's attach series ("restarting adsp with new firmware"), which the patch set leaves out.

## Sync state and the CDSP

- Sync state, and the CDSP (no listed feature uses it): until every enabled user of an RPMh power-domain or
  interconnect provider has its driver bound, the provider does not reach `sync_state`, and Linux keeps the votes it
  sends at boot: the highest level on every rail its drivers touch and full bandwidth on every interconnect node,
  sleep votes included. Fedora's configuration has no driver for two devices the X1E80100 device tree enables, the
  video clock controller (`SM_VIDEOCC_8550`, a user of `rpmhpd`) and the crypto engine (`CRYPTO_DEV_QCE`, a user of
  `aggre2_noc` and `mc_virt`), and with `DRIVER_DEFERRED_PROBE_TIMEOUT=-1` the kernel neither forces the sync nor
  prints `sync_state() pending`. Under the held rail votes the CDSP (rails CX, MXC and NSP) entered its first sleep
  20 ms after it started and never woke: FastRPC's channel open timed out (`failed to create endpoint`, error -12,
  no `/dev/fastrpc-cdsp`), sysmon's shutdown request and the SMP2P stop went unanswered, no crash was reported, and
  `/sys/kernel/debug/qcom_stats/cdsp` stayed at `Count: 0`; a restart only lasted until its next sleep. v23.2
  carried both drivers. The state shows in `/sys/bus/platform/drivers/{qcom-rpmhpd,qnoc-x1e80100}/*/state_synced`
  (0: still holding), the devices a provider waits for are its links in `/sys/class/devlink/` that are not `active`,
  and writing `1` without a newline to `state_synced` forces the sync: on revision 2 that made the stuck CDSP answer
  at once (2026-09-24). Revision 3 adds both drivers in `kernel-local`; revision 4 limits the crypto engine to its
  hashes (`CRYPTO_DEV_QCE_ENABLE_SHA`), because its AES XTS (the engine refuses equal key halves) and CTR fail the
  kernel's self-tests at every boot. dm-crypt never uses the engine: it allocates its ciphers with
  `CRYPTO_ALG_ALLOCATES_MEMORY` masked, which the engine's ciphers set. Whether the CDSP is awake shows in a QMI
  test ping over QRTR (message 0x20 with TLV 0x01 `ping` to node 10 port 1; the ADSP is node 5). Ruled out on the
  way: the CDSP's boot order against the ADSP (revision 2), FastRPC's load time (loaded in the initramfs), the QDSS
  clock. `sp11-diag` lists the providers still waiting. Once the CDSP sleeps and wakes, its firmware can report a
  `sleep_stats` fatal error once in a boot (`fatal error received: sleep_statsi.c…`; v23.2 and revision 4 alike, and
  Qualcomm's public tracker shows it on other boards); remoteproc restarts the CDSP by itself.

## Rebase to a new Fedora kernel

- Rebase straight from the pinned base to the stable tag of the new Fedora kernel, whatever lies between: a stable
  tag contains every earlier one of its series. From 7.2.5 to 7.2.7, every stable change to a file of the patch set
  came with 7.2.6; 7.2.7 touches none of them.
- Procedure (step by step, every command with its expected output: the project skill
  `.claude/skills/sp11-kernel-update/`): set `KERNEL_FEDORA_VERSION`, `KERNEL_FEDORA_RELEASE` and the two checksum
  lines (source RPM, stock `kernel-core`) in `sp11.conf`. In a clone of the kernel fork (stable tags from
  `gregkh/linux`), rebase a detached copy of `sp11/<old>` with `git rebase --onto v<new> v<old>`, resolve the
  conflicts, and give every adapted commit an `[sp11: ...]` note after its trailers. Let `git rebase --continue`
  commit a resolved conflict: it keeps the original author, while a plain `git commit` in between records the
  current user as the author (compare `git log --format='%an %ad'` of both branches). Set `KERNEL_PATCH_BASE_COMMIT`
  and `KERNEL_PATCH_COMMIT` and bump `KERNEL_SP11_REV`;
  `KERNEL_PATCH_REPO=<path of the clone> scripts/10-fetch-sources.sh` builds the branch before it is pushed (a local
  clone ignores the blob filter: the cache takes 280 MB instead of 5 MB). The branch is pushed once the kernel
  passed its device test and never rewritten afterwards (`sp11.conf` pins its commits); a copy re-signed for the
  push (`git am` of the series) has other commit ids, and when its tree (`git rev-parse <head>^{tree}`) is the
  tested one, pinning its head keeps the revision number.
- A clean textual merge is not a correct one. Review every stable change to a file the series touches
  (`git log --no-merges v<old>..v<new> -- <files>`) and compare the branches with `git range-diff`. At 7.2.6,
  `spi_geni_init()` replaced its `out_pm` label by a scoped runtime-PM guard while a `goto out_pm` of the SP11 QSPI
  path merged without a conflict (it would not have compiled), and the SoundWire port check `pn >= maxport` merged
  cleanly but refuses the SP11's CPS feedback port 13 (patch 0058 accepts it again). Then compile the directories
  the series touches on the host with Fedora's configuration plus `kernel-local` (`make O=<dir> olddefconfig`, then
  `make <dir>/ ...` and `make dtbs`; under two minutes) before the mock build. Step 20's sync-state check shows
  whether Fedora's new configuration still has a driver for every user of the rails and the interconnect.

## Install and removal

- `kernel-core` provides `installonlypkg(kernel)` and `kernel-core-uname-r`, so dnf installs each SP11 kernel next
  to the previous ones; `installonly_limit` (3) counts per package name, so the old `kernel-sp11` packages count
  apart from `kernel-core`. `20-grub.install` makes the added kernel the saved default when `/etc/sysconfig/kernel`
  has `UPDATEDEFAULT=yes` and `DEFAULTKERNEL=kernel-core`. `kernel-install remove` leaves `saved_entry` naming the
  removed entry; GRUB then boots the first one. Each SP11 kernel takes about 195 MB in `/boot` (step 36,
  7.2.5-300.sp11.1: image, System.map, config, symvers, the initramfs with the DSP firmware, and 103 MB of device
  trees, because Fedora's `kernel-core` copies the trees of every arm64 machine it supports); a full `/boot` makes
  dracut fail inside `kernel-install`, whose status the scriptlets ignore (`|| :`, as Fedora does), so the package
  installs without an entry and only the transaction's output says so: `df -h /boot` before a kernel install.
- A chroot test of that path needs a real filesystem at `/boot` (an ext4 loop image; `mkfs.ext4` from the root,
  since the host has no e2fsprogs): on an overlay root `grub2-editenv` fails with
  `failed to get canonical path of overlay`, so `saved_entry` never changes. The step 60 simulation does not check
  it.

## SELinux

- SELinux: Fedora's kernel runs the targeted policy enforcing. Installations made from ISOs built before 2026-09-22
  (AppArmor kernels) were installed with SELinux disabled (`selinux=0` in the boot arguments, `SELINUX=disabled`);
  support RPM 3.0 no longer carries `sp11-selinux-restore`, so such a system needs the manual procedure once:
  `sudo grubby --update-kernel=ALL --remove-args=selinux=0`, `SELINUX=enforcing` in `/etc/selinux/config`,
  `sudo touch /.autorelabel`, reboot (relabel and one more reboot follow). The tested unit was reinstalled from
  SELinux media on 2026-09-22.

## History

2026-09-13 to 2026-09-22 the project built ooaklee's linux_ms_dev_kit-sp11 v23 (Linux 7.2.0) from source
with its Ubuntu-derived configuration, later with the kernel.org 7.2.5 update, a configuration policy for Fedora's
LSM stack (revision 1, 2026-09-18) and the POS tablet switch (revision 2, 2026-09-21), packaged as `kernel-sp11`
(`7.2.5-jg-0sp11v23.2-qcom-x1e`). 2026-09-23: replaced by Fedora's `kernel-7.2.5-300.fc45` with the patch set
extracted from that tree (revision 1, tested on the device that day), then the CDSP boot order (revision 2, no
effect). 2026-09-24: the CDSP's fault traced to the boot-time votes Linux never released, fixed by configuration
(revisions 3 and 4). 2026-09-25: rebased onto Fedora's `kernel-7.2.7-300.fc45` (revision 5, branch `sp11/7.2.7`).
