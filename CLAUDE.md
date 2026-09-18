# CLAUDE.md — Fedora live ISO for Surface Pro 11 (5G, X1E80100, OLED)

Working notes for future sessions. Everything below was verified in September 2026 on the tested unit
listed under Target hardware.
Re-verify anything that depends on a newer Fedora, GRUB, Anaconda or ooaklee release.

## Repository

- `sp11.conf`: every version, URL, regex and boot-policy string; scripts source it via `scripts/lib.sh`.
- `scripts/NN-*.sh`: pipeline steps, idempotent, `FORCE=1` rebuilds. `build-all.sh` runs 00–50;
  `60-verify-rootfs.sh` checks the remastered root; `70-export-bt-pairings.sh` is a separate tool.
- `rpm/*.spec.in`: templates rendered by `render()` (`@KEY@` placeholders; leftovers fail the build).
- `files/`: payload of `sp11-surface-support` (installed under `/usr/libexec/sp11`, `/etc/grub.d`,
  `/usr/lib/...`), the live GRUB menu template and `README-iso.txt.in` (the note inside the ISO; it
  carries the redistribution warning and credits).
- The repo is public under GPL-3.0-or-later (`LICENSE`; the support RPM's `License:` tag must agree).
  Tracked files carry no per-unit identifiers: Bluetooth/Wi-Fi/peripheral addresses, firmware versions,
  local paths and the owner's name stay out of `CLAUDE.md`, `README.md`, `files/` and `scripts/`.
  Per-unit values live in `build/hardware.env`, `build/bt-pairings/` and, inside the built RPM,
  `/etc/sp11/bluetooth-address`. Check before staging:
  `git grep -nE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'` must show only the `AA:BB:CC:DD:EE:FF` placeholders.
- `CLAUDE.local.md` (git-ignored, loaded by Claude Code after this file) holds the owner's private working
  rules and hand-off notes. `.gitattributes` forces LF. `.gitignore` also blocks `hardware.env`, `*.hiv`,
  `*.iso`, `*.rpm` and the pairing tarball anywhere in the tree.
- `build/` (git-ignored): `cache/` (downloads, pinned checkouts, `rpm-deps/`, `patch-<v>.xz`), `kernel/`
  (one source tree per stable version, payload, logs), `work/iso/` (extracted live root, root-owned),
  `rpms/`, `out/` (ISO, `.sha256`, pairing tarball), `bt-pairings/` (exported hive; secret), `hardware.env`.
- Bump `VERSION=` in `scripts/30-build-support-rpm.sh` whenever the support payload changes, so
  `dnf upgrade` works on the installed system. Its `%posttrans` regenerates `grub.cfg`. Steps 20/30/40
  skip only when the cached RPM matches (kernel ABI file list; support `%{VERSION}` and the
  `.fc<release>` dist tag; iptsd version-release and commit), so a bump or a `FEDORA_RELEASE` switch
  triggers the rebuild; `IPTSD_RPM_RELEASE` in `sp11.conf` versions the iptsd spec. `build_rpm` and
  `mock_rebuild` delete every older RPM of the same name, so `build/rpms/` holds one release's set; copy it
  aside (`build/rpms-fc<release>/`) before switching.
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
  7.2.5 stable update (ABI `7.2.5-jg-0sp11v23-qcom-x1e`, see `KERNEL_STABLE_VERSION` below).
- `python3 debian/scripts/misc/annotations --file debian.qcom-x1e/config/annotations --arch arm64
  --flavour qcom-x1e --export` reproduces the released config exactly except `CONFIG_VERSION_SIGNATURE`.
  The ABI is injected with `CONFIG_LOCALVERSION="-jg-0sp11v23-qcom-x1e"`. Native build of a fresh tree:
  ~45 min on 12 cores, 7816 modules, same set as ooaklee's deb. A stopped build resumes where it left off
  (the background task dies with the Claude session or WSL); `FORCE=1` on a built tree takes ~5 min.
  Image is `arch/arm64/boot/vmlinuz.efi` (EFI zboot PE).
- Relevant config: EROFS with LZMA and xattrs as module; `CONFIG_LSM="landlock,lockdown,yama,integrity,
  apparmor"` (AppArmor active, SELinux inactive, Fedora runs without MAC);
  `CONFIG_SECURITY_APPARMOR_RESTRICT_USERNS=y` (denies unprivileged user namespaces without a profile;
  Fedora has none, so `kernel.apparmor_restrict_unprivileged_userns=0` is shipped in
  `/usr/lib/sysctl.d/90-sp11.conf`, otherwise Flatpak's bwrap fails with EPERM); no `CRYPTO_FIPS`;
  `MODULE_SIG=y` with an ephemeral key; zstd modules; `FW_LOADER_COMPRESS_XZ=y`.
- Fedora's `depmod -b BASE` expects `BASE/lib/modules`; the payload uses `/usr/lib/modules`, so
  `20-build-kernel.sh` uses a temporary `lib -> usr/lib` symlink.
- `KERNEL_STABLE_VERSION` (default `7.2.5` in build mode; `KERNEL_STABLE_VERSION=` builds the release as
  published) applies kernel.org's cumulative `patch-<v>.xz` (sha256 pinned in the `sp11.conf` case table) to
  ooaklee's source in a tree of its own, `build/kernel/src/linux-<commit>-stable-<v>`, stamped
  `.sp11-stable-<v>` only after `patch --batch --forward --fuzz=1` applied without a reject.
  `KERNEL_UPSTREAM_VERSION` stays ooaklee's base; `KERNEL_BUILD_VERSION`, the ABI
  (`7.2.5-jg-0sp11v23-qcom-x1e`) and the RPM version follow the patch (`kernel-sp11-7.2.5-sp11v23`).
  `KERNEL_MODE=prebuilt` ignores the default and refuses an explicit value. `sp11.conf` also refuses a
  stable version whose `X.Y.0` base is not `KERNEL_UPSTREAM_VERSION`, so a new ooaklee release on another
  base fails early until the default is revisited.
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
  `/boot/aarch64/loader/grub2/fonts/unicode.pf2`. `xorriso ... -boot_image any replay -map ...`
  reproduces the layout; `50-build-iso.sh` reads these paths from the ISO instead of assuming them.
- Fedora's aarch64 GRUB image has `devicetree`, `gfxterm`, `loadfont`, `blscfg`, `fat`, `efi_gop`,
  `all_video`, `search_fs_uuid`, `part_gpt`, `fwsetup`, `efinet`, `net`, `boot`. It lacks `efi_uga`,
  `video_bochs`, `video_cirrus` and `chain` (Fedora builds `chain` into x86 images only).
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
- Anaconda 44.30 discovers kernels from `/boot/vmlinuz-*` and runs `kernel-install add <ver>
  /lib/modules/<ver>/vmlinuz`. Deleting stock `/boot/vmlinuz-*` makes the SP11 kernel the only
  candidate while the stock kernel packages stay installed (the 44 1.7 and 45 Beta media carry no
  `kernel-core`; see `kernel-uki-dtbloader` below). Anaconda rewrites `/etc/default/grub`, persists
  `modprobe.blacklist=` into `/etc/modprobe.d/anaconda-denylist.conf`, preserves `clk_ignore_unused
  pd_ignore_unused arm64.nopauth` but not `systemd.tpm2_wait=0`. Its grub2-mkconfig runs in a chroot
  with `/dev` bound but no udev database.
- Fedora's `20-grub.install` writes `devicetree /dtb-<ver>/$GRUB_DEVICETREE` into the BLS entry and
  copies `/usr/lib/modules/<ver>/dtb` to `/boot/dtb-<ver>`; systemd's `90-loaderentry.install` reads
  `/etc/kernel/devicetree`. `15-sp11-surface.install` sets both before they run, via
  `/usr/libexec/sp11/sp11-grub-defaults` (the single writer of the `/etc/default/grub` policy, also used by
  `sp11-first-boot` and `50-build-iso.sh`). It filters `/etc/kernel/cmdline` when present, otherwise
  `/proc/cmdline`, and persists the result only when it contains `root=` (never the live command line).
- `mkfs.erofs -Ededupe` is single-threaded in erofs-utils 1.9.4 (hours). `-Efragments -C1048576
  --workers=N -zlzma,level=6` takes ~5 min and is only slightly larger. Use `--file-contexts` from the
  root's own SELinux policy.
- In a chroot without udev, `lsblk` reports empty PARTTYPE/FSTYPE; use `blkid -c /dev/null -o device
  -t TYPE=vfat` and `blkid -p -s PART_ENTRY_TYPE -o value DEV` instead.
- `grep -q` at the end of a pipeline under `pipefail` fails spuriously (SIGPIPE); use `grep ... >/dev/null`.
- Under `set -e -o pipefail`, `var=$(ls pattern | head -1)` exits the script silently when the glob does
  not match (`ls` fails, the assignment inherits the status). Append `|| true` inside the substitution.
  The same applies to `var=$(grep ... | sed ...)` and `var=$(... | grep -v ...)` on empty input.
- `bash -n A B C` parses only `A` (`B C` become positional parameters); syntax-check files one at a time.
- `grep -v -q PATTERN FILE` cannot assert absence (it succeeds on any non-matching line); use `! grep -q`.
- `findmnt -R DIR` lists submounts only when DIR itself is a mount point; `mounts_under` in `lib.sh`
  matches the target prefix instead. Both `50` and `60` refuse to `rm -rf` a tree with mounts below it.
- `%systemd_postun_with_restart NAME@.service` on a template unit is a no-op (`systemctl try-restart`
  rejects a name without instance); restart `'NAME@*.service'` explicitly.
- dracut `install_items` applies to `--no-hostonly` builds too; `50` parks the support RPM's drop-in
  during the live initramfs run and installs only the GPU zap shader.
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
  system drops those arguments via the kernel-install plugin and `sp11-first-boot.service`.
- Windows dual-boot: `/etc/grub.d/29_sp11_windows` + `/usr/libexec/sp11/sp11-grub-modules` (copies
  `chain.mod` and its dependency closure from `moddep.lst` into `/boot/grub2/arm64-efi`, re-run by an
  RPM trigger on `grub2-efi-aa64-modules`). Booting Windows through this entry works on the tested unit.

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

Benign boot-time messages on this unit: `qcom_q6v5_pas … Handover signaled, but it already happened`;
`qcom_pmic_glink … Failed to create device link (0x180) with supplier …` for the PD and USB nodes (probe
deferral, retried); `surface_hid … unexpected descriptor length: got 0, expected 9` then `error -71` for one
Surface Aggregator HID endpoint that nothing depends on.

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
Windows GRUB entry and the keyboard and pen pairings shared with Windows. 7.2.5 is the build default since
then; no ISO with it has been built yet.

## References

rjindael/fedora-surface-pro-11 (Fedora bring-up notes); ooaklee/linux-surface-pro-11-oe (kernel, audio,
iptsd releases, ADRs); ooaklee/lexr.sh `internal/image/fedora/*.go` (remaster design reference);
Fedora wiki "Snapdragon WoA Laptop Install"; Arch wiki "Bluetooth" (dual-boot pairing).
