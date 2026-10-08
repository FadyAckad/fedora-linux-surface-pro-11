# Kernel
Fedora's kernel package rebuilt with the SP11 patch set: sources, build, revisions, configuration, rebase, install.

## Sources and packages

- The inputs: Fedora's `kernel` source RPM for `FEDORA_RELEASE` (`KERNEL_SRPM`, sha256 pinned in `sp11.conf`), the
  SP11 patch set (the commits `KERNEL_PATCH_BASE_COMMIT..KERNEL_PATCH_COMMIT` of the kernel fork
  `KERNEL_PATCH_REPO`; manifest `docs/kernel-patches.md`) and the fragment `payload/kernel-local`.
- The result: Fedora's package family with the same names, provides and scriptlets (`kernel`, `kernel-core`,
  `kernel-modules{,-core,-extra,-internal}`, `kernel-uki-dtbloader`, `kernel-devel`, ...), uname
  `<version>-<release>.sp11.<rev>.fc<n>.aarch64`.
- The tarball `linux-<version>.tar.xz` is the stable tag's tree (7.2.5, 7.2.7, 7.2.8 and 7.2.9 checked). Fedora's
  own `patch-7.2-redhat.patch` (61 files in 7.2.5, 63 in 7.2.7, 62 in 7.2.8, 63 in 7.2.9) shares only the media
  `Kconfig`, `Makefile` and `MAINTAINERS` with the patch set, applied after it.

### The builds, by revision

| Revision | Date | Fedora kernel | Content |
|---|---|---|---|
| 1 | 2026-09-23 | `kernel-7.2.5-300.fc45` | First build |
| 2 | 2026-09-23 | `kernel-7.2.5-300.fc45` | CDSP boot-order patch, dropped |
| 3 and 4 | 2026-09-24 | `kernel-7.2.5-300.fc45` | Configuration only |
| 5 | 2026-09-25 | `kernel-7.2.7-300.fc45` | Rebased onto `v7.2.7` |
| 6 | 2026-09-26 | `kernel-7.2.7-300.fc45` | The cameras (`docs/camera.md`) |
| 7 | 2026-09-26 | `kernel-7.2.7-300.fc45` | Front camera privacy LED |
| 8 | 2026-09-27 | `kernel-7.2.7-300.fc45` | IMX681 frame length |
| 9 | 2026-09-28 | `kernel-7.2.7-300.fc45` | OV13858 pixel rate, IMX681 control lock |
| 10 | 2026-10-02 | `kernel-7.2.8-300.fc45` | Rebased onto `v7.2.8` |
| 11 | 2026-10-08 | `kernel-7.2.9-300.fc45` | Rebased onto `v7.2.9` |

## kernel.spec slots and the build

- The buildid slot, the spec's only edit: `# define buildid .local` becomes `%define buildid .sp11.<rev>`; step 20
  dies unless exactly one such line exists.
- The patch slot `Patch999999: linux-kernel-test.patch` receives the series step 10 writes with `git format-patch`
  from a shallow partial clone (about 5 MB) and step 20 checks against the pinned tree (`kernel_series_check` in
  `lib.sh`) before concatenating it.
- The configuration slot `Source3001: kernel-local`, merged into every configuration; `process_configs.sh` fails on
  a symbol no configuration sets, so `kernel-local` sets the patch set's new symbols
  (`CONFIG_TOUCHSCREEN_MSHW0485`, `CONFIG_VIDEO_IMX681`, `CONFIG_VIDEO_VD55G0`) and every symbol Kconfig derives
  from them.
- Strict patching: the spec applies patches with `git --work-tree=. apply`, no fuzz, exact hunk counts; GNU `patch`
  accepted a hunk one line short that `git apply` refuses.
- The build (step 20): `rpmbuild -bs` on the host with `dist .fc<n>` and `fedora <n>`, then `mock --rebuild` in the
  `MOCK_CONFIG` buildroot with `--uniqueext=sp11-kernel` (a root apart from steps 40/45) and `KERNEL_MOCK_OPTS`
  (`--with baseonly`, `--without efiuki kmap doc headers cross_headers kabichk kabidwchk ynl`). Debuginfo stays on:
  `--without debuginfo` sets `CONFIG_DEBUG_INFO_NONE`, and the configuration would not be Fedora's.

## Checks on the result

- Step 20 checks the built packages: every `KERNEL_PKGS` package at the configured uname; `vmlinuz` and the Denali
  OLED DTB in `kernel-core`, with the camera sensors (`sony,imx681`, `ovti,ov13858`, `st,vd55g0`) and the `privacy`
  LED; a driver for every enabled user of the RPMh power domains and the interconnect
  (`scripts/sync-state-drivers.py`); the configuration equal to the pinned stock `kernel-core`
  (`KERNEL_STOCK_CORE_RPM`; the source RPM's `kernel-aarch64-fedora.config` is only Kconfig's input) plus the
  `kernel-local` lines; the patch set's modules and parameters.

## Revisions

- The pins: `KERNEL_SP11_REV` (in the buildid) and `KERNEL_SP11_REV_SHA256` (`kernel_rev_sha256` in `lib.sh`, over
  the revision number, the effective `kernel-local` lines and the two pinned commits); step 20 refuses a patch set
  or fragment that differs and prints the value to set.
- Bump the revision with every change, a new Fedora kernel included: `kernel-core` is install-only, and a rebuilt
  uname with other content would own the installed kernel's `/boot` and module paths.
- The buildid must not contain `rt|auto|uki|64k|debug`, or `20-grub.install` does not make the kernel the saved
  default.

## Configuration

- Fedora's configuration (`CONFIG_LSM="lockdown,yama,integrity,selinux,bpf,landlock,ipe"`, zboot `vmlinuz`) has
  what the SP11 needs beyond the patch set but the two drivers of "Sync state and the CDSP": the Surface Aggregator
  stack (patch 0055 keeps `BATTERY_SURFACE` from binding), pmic_glink's battmgr and UCSI, PAS remoteproc,
  pd-mapper, FastRPC, QRTR, ath12k, `BT_QCA`, the X1E audio, GPI DMA, `SPI_QCOM_GENI`, `HIDRAW=y`, `KEYBOARD_GPIO`,
  `PINCTRL_QCOM_SPMI_PMIC` and the camera stack but its two new sensors (`docs/camera.md`).
- `ARM_SCMI_CPUFREQ=m` does not load on its own (modpost cannot generate SCMI-bus aliases); the support RPM loads it
  through `modules-load.d` (Fedora's "Snapdragon WoA Laptop Install" wiki fix).

## Extraction from v23.2

- Revision 1's patch set came from the v23.2 kernel (ooaklee's linux_ms_dev_kit-sp11 v23 on jglathe's X1E tree,
  plus the 7.2.5 update and the POS patch); the patches and what was left out: `docs/kernel-patches.md`.
- SKU-specific code: patch 0042 (the OLED link-rate quirk) matches `DMI_PRODUCT_NAME` exactly against "Microsoft
  Surface Pro, 11th Edition" and never applies on the 5G SKU, whose panel works without it; everything else keys on
  the `microsoft,denali` compatible of both SKUs. ooaklee's ADSP attach series is left out, as mainline's PAS
  driver (`lite_pas_id` 0x1f, `lite_dtb_pas_id` 0x29, `qcom_pas_load`) itself restarts the UEFI-started ADSP with
  the full firmware.
- Carried as validated, not cleaned up: `gpi.c`, `spi-geni-qcom.c`, the AudioReach files and `lpass-wsa-macro.c`
  are 7.1-based copies missing some 7.2 changes; ooaklee's re-lift onto 7.2.2 lost touch, pen and the right
  speaker, so a clean-up needs its own revision and device test.

Re-extraction:

1. The history: a blobless clone of ooaklee/linux_ms_dev_kit-sp11, branch `lexr-0.3.0-demo` (`ce78e6eb`).
2. The split: `git diff 746b3477 ce78e6eb` is ooaklee's own work, `git log <v7.2>..746b3477` jglathe's base.
3. The selection: the built v23.2 DTB's enabled compatibles, mapped through `modules.alias` and
   `modules.builtin.modinfo` to modules, dependencies and sources (kbuild's `.cmd` files).
4. The compile check before the hour-long mock build (`make prepare modules_prepare`, then `make <dir>/` with
   Fedora's configuration); a file comparison with v23.2 misses prerequisite commits.

## Sync state and the CDSP

No listed feature uses the CDSP.

- The mechanism: an RPMh power-domain or interconnect provider reaches `sync_state` only once every enabled user
  has its driver bound; until then Linux keeps the boot votes (rails at their highest level, interconnects at full
  bandwidth, sleep included) and, with `DRIVER_DEFERRED_PROBE_TIMEOUT=-1`, neither forces the sync nor prints
  `sync_state() pending`. Fedora lacked two users' drivers: the video clock controller (`SM_VIDEOCC_8550`, on
  `rpmhpd`) and the crypto engine (`CRYPTO_DEV_QCE`, on `aggre2_noc` and `mc_virt`).
- The symptom: the CDSP enters its first sleep 20 ms after it starts and never wakes: FastRPC's channel open times
  out (`failed to create endpoint`, error -12, no `/dev/fastrpc-cdsp`) and `/sys/kernel/debug/qcom_stats/cdsp`
  stays at `Count: 0`; a restart lasts until the next sleep.
- Reading the state: `/sys/bus/platform/drivers/{qcom-rpmhpd,qnoc-x1e80100}/*/state_synced` (0: still holding);
  `sp11-diag` lists the providers still waiting, their non-`active` links in `/sys/class/devlink/` naming the
  devices. CDSP awake or not: a QMI ping over QRTR to node 10 (the skill's `sp11-dsp-ping.py`; ADSP: node 5).
- Forcing the sync: write `1` without a newline to `state_synced`; the stuck CDSP answers at once.
- The fix in `kernel-local`: both drivers, the crypto engine limited to its hashes (`CRYPTO_DEV_QCE_ENABLE_SHA`)
  because its AES XTS and CTR fail the kernel's self-tests at boot; dm-crypt never uses the engine (it masks
  `CRYPTO_ALG_ALLOCATES_MEMORY`, which the engine's ciphers set). The CDSP's `sleep_stats` assert around sensor
  stream changes is known (`docs/sensors.md`, Known issues); remoteproc restarts the CDSP.

## Rebase to a new Fedora kernel

Every command with its expected output: `.claude/skills/sp11-kernel-update/`.

- Rebase straight from the pinned base onto the new stable tag, whatever lies between (a stable tag contains every
  earlier one).
- 7.2.5 to 7.2.7 (revision 5): every stable change to a file of the patch set came with 7.2.6, none with 7.2.7.
- 7.2.7 to 7.2.8 (revision 10): the 74 commits rebased unchanged, without a conflict; five stable commits touch
  files of the series, none its code.
- 7.2.8 to 7.2.9 (revision 11): the 74 commits rebased unchanged, without a conflict; no stable commit touches a
  file of the series, and Fedora's configuration differs only in `BUILD_SALT`. `i2c-qcom-geni` now selects the
  serial engine's clock-table entry for 32 or 19.2 MHz (it wrote index 0) and refuses to probe without one; X1E's
  QUP tables carry both. Its four buses carry the two PS8830 USB-C retimers.

### Procedure

1. Pin Fedora's kernel in `sp11.conf`: `KERNEL_FEDORA_VERSION`, `KERNEL_FEDORA_RELEASE` and the two checksum lines
   (source RPM, stock `kernel-core`).
2. Rebase a detached copy of `sp11/<old>` onto the new tag in a fork clone, resolve the conflicts and note each
   adaptation as `[sp11: ...]` after the trailers; `git rebase --continue` keeps the author, `git commit` does not.
3. Review: a clean merge is not a correct one; read every stable change to a file the series touches and compare
   the branches with `git range-diff`.
   - At 7.2.6 `spi_geni_init()` lost its `out_pm` label; the QSPI path's `goto out_pm` merged but did not compile.
   - 7.2.6's SoundWire check `pn >= maxport` merged cleanly but refused the CPS feedback port 13 (patch 0058).
4. Compile on the host before the mock build: the directories the series touches and the DTBs, with Fedora's
   configuration plus `kernel-local` (under two minutes).
5. Pin the patch set (`KERNEL_PATCH_BASE_COMMIT`, `KERNEL_PATCH_COMMIT`) and bump `KERNEL_SP11_REV`.
6. Build from the clone before the push: `KERNEL_PATCH_REPO=<clone>` for step 10 (a local clone takes 280 MB, not
   5 MB); step 20's sync-state check then covers Fedora's new configuration.
7. Push after the device test and never rewrite the branch (`sp11.conf` pins its commits); a re-signed copy with
   the tested tree (`git rev-parse <head>^{tree}`) keeps the revision number.

## Install and removal

- Install-only: `kernel-core` provides `installonlypkg(kernel)` and `kernel-core-uname-r`, so dnf keeps each SP11
  kernel next to the previous ones (`installonly_limit` 3, counted per package name, the old `kernel-sp11` apart);
  `20-grub.install` makes the added kernel the saved default when `/etc/sysconfig/kernel` has `UPDATEDEFAULT=yes`
  and `DEFAULTKERNEL=kernel-core`; after `kernel-install remove`, `saved_entry` still names the removed entry and
  GRUB boots the first one.
- Space in `/boot`: each SP11 kernel takes about 195 MB (103 MB of it the device trees of every arm64 machine).
  Run `df -h /boot` before an install: in a full `/boot` dracut fails inside `kernel-install`, whose status
  the scriptlets ignore (`|| :`, as Fedora does): the package installs without an entry and only the transaction's
  output says so.
- A chroot test of the install path needs a real filesystem at `/boot` (an ext4 loop image made from the root, the
  host lacking e2fsprogs); on an overlay root `grub2-editenv` fails (`failed to get canonical path of overlay`),
  so the step 60 simulation cannot check `saved_entry`.

## SELinux

- Fedora's kernel runs the targeted policy enforcing.
- Installations from ISOs built before 2026-09-22 (AppArmor kernels) have SELinux disabled (`selinux=0` in the boot
  arguments, `SELINUX=disabled`); support RPM 3.0 dropped `sp11-selinux-restore`, so such a system needs once:
  `sudo grubby --update-kernel=ALL --remove-args=selinux=0`, `SELINUX=enforcing` in `/etc/selinux/config`,
  `sudo touch /.autorelabel` and a reboot; the relabel and one more reboot follow.

## History

- 2026-09-13 to 2026-09-22: ooaklee's v23 kernel built as `kernel-sp11` (`7.2.5-jg-0sp11v23.2-qcom-x1e`).
- 2026-09-18 and 2026-09-21: `kernel-sp11` revisions 1 (Fedora's LSM stack) and 2 (the POS tablet-mode switch).
- 2026-09-23: `kernel-7.2.5-300.fc45` with the extracted patch set (revision 1); revision 2 had no effect.
- 2026-09-24: the CDSP fault traced to the held boot votes, fixed in `kernel-local` (revisions 3 and 4).
- 2026-09-25: rebased onto `kernel-7.2.7-300.fc45` (revision 5, `sp11/7.2.7`).
- 2026-09-26: the cameras (revision 6, turbineBMW's branch); the front camera's LED (revision 7).
- 2026-09-27: the IMX681's frame length (revision 8).
- 2026-09-28: revisions 6 to 8 pushed (`95a74f27`); revision 9, two camera fixes, passed and pushed (`30c57e66`).
- 2026-10-02: rebased onto `kernel-7.2.8-300.fc45` (revision 10, `sp11/7.2.8`); passed 2026-10-03 and pushed
  (`c9a90d97`).
- 2026-10-08: rebased onto `kernel-7.2.9-300.fc45` (revision 11, `sp11/7.2.9`); passed the same day and pushed
  (`0fdddb4d`).
