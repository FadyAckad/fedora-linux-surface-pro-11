# Fedora media
The live media, GRUB, Anaconda, kernel-install, the live initramfs and root, and the Fedora 45 differences.

## Source media

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

## ISO layout

- `Fedora-Workstation-Live-44-1.7.aarch64.iso`, volume id `Fedora-WS-Live-44`, built by kiwi. The live root
  `/LiveOS/squashfs.img` is EROFS (LZMA, fragments, dedupe), 2.36 GB.
- Hybrid GPT + El Torito UEFI image + appended ESP. `/EFI/BOOT/grub.cfg` does
  `search --file --set=root /boot/0x503d6c7e` then `configfile ($root)/boot/grub2/grub.cfg`. Kernel
  `/boot/aarch64/loader/linux`, initrd `/boot/aarch64/loader/initrd`, font
  `/boot/aarch64/loader/grub2/fonts/unicode.pf2` (step 50 maps `sp11-console.pf2` in beside it, lifted out of the
  live root rather than generated a second time). `xorriso ... -boot_image any replay -map ...` reproduces the
  layout; `50-build-iso.sh` reads these paths from the ISO instead of assuming them.

## GRUB image, font and modules

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

## Live initramfs and live menu

- Stock live initramfs arguments:
  `dracut --no-hostonly --no-hostonly-cmdline --install /.profile --add "dmsquash-live livenet pollcdrom" --omit multipath`;
  it includes the `fips` dracut modules, and so does the SP11 one (Fedora's kernel has `CRYPTO_FIPS`). Generate it
  in a chroot of the live root.
- Fedora's live `grub.cfg` (read from each ISO): `set default="1"` (the media check), `timeout=10`, `load_video`,
  `terminal_output console`, `search --file --set=root <marker>`, then "Start …", "Test this media & start …"
  (`rd.live.check`) and a Troubleshooting submenu with basic graphics. Step 50 keeps it and changes only what the
  SP11 needs: `terminal_output console` gives way to the console-font block after the `search` line, every `linux`
  line gets `$sp11_args` (installed + live-only arguments) and every `initrd` line a `devicetree $sp11_dtb` after
  it; a layout the transformation does not recognise stops the build. `rd.live.check` needs the ISO checksum that
  `implantisomd5` writes and xorriso's remastering drops, so step 50 implants it again and checks the result with
  `checkisomd5` (both from `isomd5sum`, as Fedora's image build uses).

## Anaconda

- Anaconda 44.30 and 45.22 (code read in a Fedora 44 and a Workstation 45 Beta live root; same task order in both)
  discover kernels only from `/boot/vmlinuz-*` (`live_os/utils.py`) and run
  `kernel-install add <ver> /lib/modules/<ver>/vmlinuz` for each (45.22 also knows `vmlinuz-dtbloader.efi`; the 44
  1.7 and 45 Beta media carry no `kernel-core`, see `kernel-uki-dtbloader` below). Step 50 installs the SP11 kernel
  packages with `--noscripts`, so it copies `vmlinuz` and `.vmlinuz.hmac` to `/boot` itself, as `20-grub.install`
  would. Queue order (`modules/boss/installation.py`): payload (`PrepareSystemForInstallationTask` writes
  `/etc/modprobe.d/anaconda-denylist.conf` from `modprobe.blacklist=`; rsync of the live root without `--delete`,
  excluding `/boot/loader/`, then `/boot/grub2`, `/etc/sysconfig` and `/usr/lib/grub` copied again without xattrs) →
  bootloader (`InstallBootloaderTask`: `write_defaults` truncates `/etc/default/grub` and sets `GRUB_CMDLINE_LINUX`
  to Anaconda's boot args, then grub2-mkconfig, which creates `/etc/kernel/cmdline`; `CreateBLSEntriesTask`: deletes
  every BLS entry, `kernel-install add`, `grub2-mkconfig -o /etc/grub2.cfg`) → configuration queue
  (`RecreateInitrdsTask`: `dracut -f`). Only `preserved_arguments` from the live command line reach the boot args
  (`clk_ignore_unused pd_ignore_unused arm64.nopauth` among them, 45.22 also `systemd.tpm2_wait`; never
  `modprobe.blacklist`, `rd.driver.blacklist` or the soundwire argument), plus `rhgb quiet` and storage arguments.
  Command lines and their output go to `/var/log/anaconda/program.log` on the installed system. Its grub2-mkconfig
  runs in a chroot with `/dev` bound but no udev database. The live root's `/etc/default/grub` never reaches an
  installation. On a BTRFS root (Fedora's default layout, with or without LUKS) `FixBTRFSBootloaderTask` runs after
  `RecreateInitrdsTask` and repeats `ConfigureBootloaderTask` and `InstallBootloaderTask`: `/etc/default/grub` is
  truncated again and grub2-mkconfig rewrites every entry's options and `/etc/kernel/cmdline` from Anaconda's
  arguments, after the kernel-install plugin ran. The entry's `devicetree` line, the initramfs and the removed
  denylist survive; the GRUB settings and the SP11-only arguments do not.

## kernel-install and BLS entries

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
  (rewritten after `/etc/default/grub`, so 20-grub does not rerun mkconfig) and removes the Anaconda denylist before
  Anaconda's initramfs rebuild. Anaconda's last grub2-mkconfig still strips the SP11-only arguments from the entry
  (the soundwire argument; on 44 also `systemd.tpm2_wait=0`), and on BTRFS the GRUB settings as well, so the first
  boot runs without them until `sp11-first-boot` (`grubby --update-kernel=ALL --args`, which also updates
  `GRUB_CMDLINE_LINUX` and `/etc/kernel/cmdline`, then `sp11-grub-defaults` and grub2-mkconfig) fixes both for the
  second boot. Reproduced for the non-BTRFS order in an overlay of a Fedora 44 root with real grub2-mkconfig runs (a
  `grub2-probe`/`grub2-mkrelpath` stub for the overlay root, an ext4 loop at `/boot`). The plugin does not filter
  live-only arguments; step 60 checks that no Anaconda config mentions them.

## Live root repack

- `mkfs.erofs -Ededupe` is single-threaded in erofs-utils 1.9.4 (hours).
  `-Efragments -C1048576 --workers=N -zlzma,level=6` takes ~5 min and is only slightly larger. Use `--file-contexts`
  from the root's own SELinux policy.
- `mkfs.erofs -T` alone implies `--all-time`: every file gets the build time, and Anaconda's `rsync -t` copies
  that onto the installed system. Every ISO up to 2026-09-21 was built that way, so on the tested unit
  `ls -l /usr/bin/bash` shows the ISO's build date, Python recompiles its timestamp-checked bytecode (7985 of the
  live root's 8178 `.pyc` files) at every start of an unprivileged process, and `rpm -V` flags the times; no
  malfunction. Step 50 passes `--mkfs-time` since 2026-09-22 and asserts that `/usr/lib/os-release` keeps its
  time from the source image.

## Chroot and RPM pitfalls

- In a chroot without udev, `lsblk` reports empty PARTTYPE/FSTYPE; use `blkid -c /dev/null -o device -t TYPE=vfat`
  and `blkid -p -s PART_ENTRY_TYPE -o value DEV` instead.
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
  `sp11-bt-set-addr` is libc-only; the kernel and the sensors chain (hexagonrpc, libssc, iio-sensor-proxy) are built
  by mock for the target release as well.
- `rpm/sp11-iptsd.spec.in` must carry `BuildRequires: cmake`: meson locates Microsoft.GSL only through its CMake
  config. The host build masked this because `00-setup-host.sh` installs cmake as an iptsd build dependency.
- The boot kernel on aarch64 is owned by `kernel-uki-dtbloader`, not `kernel-core` (Workstation Live installs no
  `kernel-core` at all). Not new in 45: Koji's package list of the 44 1.7 Workstation image shows the same set
  (`kernel`, `kernel-modules{,-core,-extra}`, `kernel-uki-dtbloader`, no `kernel-core`); the kiwi description
  (`components/boot.xml`, profile BootCoreLive) names it. It is a systemd-stub UKI
  (`ukify --hwids=/usr/share/stubble/hwids`) with `.dtbauto` device trees and a `.hwids` table from Fedora's
  `stubble` package (hardware IDs from github.com/ubuntu/stubble); `%posttrans` runs `kernel-install add` on
  `vmlinuz-dtbloader.efi`, and `20-grub.install` writes an ordinary BLS entry (with `devicetree` when
  `GRUB_DEVICETREE` is set; the stub then replaces a DTB it did not choose with its own embedded one of the same
  compatible). It `Conflicts:` with `kernel-core` of the same version and provides `installonlypkg(kernel)` and
  `kernel-core-uname-r`. The SP11 media install `kernel-core` in its place (`KERNEL_PKGS`): this unit's SMBIOS
  hardware IDs match no stubble entry (see `docs/hardware.md`), and Fedora documents `kernel-core` with
  `GRUB_DEVICETREE` as the manual path. The SP11 build of `kernel-uki-dtbloader` is built for a later test.
  `kernel-tools` and `kernel-tools-libs` track the kernel version too but own nothing in `/boot` and cannot create
  entries.
- Stock kernels are kept off installed systems by a dnf5 repository override the support RPM ships
  (`/usr/share/dnf5/repos.override.d/90-sp11-kernel.repo`: `[*]` with
  `excludepkgs=kernel,kernel-core,…,kernel-uki-*`). dnf5 5.4 loads the override directories in `/usr/share/dnf5` and
  `/etc/dnf`, accepts globbed repository IDs and per-repository `excludepkgs`, and applies them to configured
  repositories only: verified in the 45 Beta root on 2026-09-23 (step 35), a `kernel-core` offered by a local
  repository is hidden, visible again with `--setopt=disable_excludes='*'`, and the same RPM given as a file
  installs from `@commandline`. That is the difference from support 1.6–2.7's global `[main] excludepkgs` in
  `libdnf5.conf.d`, which also hid local RPMs of the same names. dnf5 has no `--disableexcludes` (DNF4 spelling);
  the override is `dnf --setopt=disable_excludes='*' ...`.
- No rescue image (`dracut_rescue_image="no"` in the support RPM's drop-in): `51-dracut-rescue.install` (from
  `dracut-config-rescue`, installed by default) copies the kernel's BLS entry and replaces the kernel version in it,
  so the entry's `devicetree /dtb-<version>/…` becomes `/dtb-0-rescue-<machine-id>/…`, a directory nothing creates.
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
  `qcom/gen70500_sqe.fw.xz` and `qcom/gen70500_gmu.bin.xz`; `payload/90-sp11.conf` installs both and the support RPM
  now `Requires: qcom-firmware`. With 2.0 or later the error is gone on the installed 45 Beta Workstation system.
  The live initramfs still carries only the zap shader (step 50 parks the drop-in).
- A stock kernel whose packages stay installed without its `/boot` image breaks `dracut --regenerate-all`: dracut
  111 without an output path writes `/boot/initramfs-<ver>.img` only when `/boot/vmlinuz-<ver>` exists; otherwise,
  with `/boot/efi` mounted, it falls back to `/boot/efi/<machine-id>/<ver>/initrd`, fails with `Can't write to ...`,
  carries on to the next kernel and exits non-zero. Step 50 therefore erases the stock set (`KERNEL_STOCK_PKGS`)
  from the live root with `rpm -e --noscripts` before it installs the SP11 build of the same packages (a plain
  erase, so dependencies are still checked: nothing outside the kernel family requires those packages; erasing
  `glibc` is a working negative control). The erase leaves no module tree and no `/boot` file behind (the depmod
  outputs are `%ghost`); step 50 still removes unowned leftovers and refuses any other module tree, so the installer
  only ever sees the SP11 kernel.
