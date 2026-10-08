# Fedora media
The live media, GRUB, Anaconda, kernel-install, the live initramfs and root, and the Fedora 45 differences.

## Source media

- `FEDORA_TARGET` in `sp11.conf` picks the compose family: `ga` (`releases/<n>/`), `beta`
  (`releases/test/<n>_Beta/`) or `nightly` (`development/<n>/`, needs `FEDORA_COMPOSE=<stamp>`). `FEDORA_RELEASE`
  stays the numeric release (`--releasever`, `%{dist}`, cache keys); `FEDORA_MEDIA_VERSION` is the version string
  inside the ISO name (`45_Beta`).
- The CHECKSUM file name differs per family: GA `Fedora-Workstation-<v>-<c>-<arch>-CHECKSUM`, Beta
  `Fedora-Workstation-iso-<v>-<c>-<arch>-CHECKSUM`, nightly `Fedora-Workstation-iso-<n>-<arch>-<stamp>-CHECKSUM`;
  the body is the same clearsigned BSD digest, checked with `sha256sum -c --ignore-missing`.
- `FEDORA_EDITION` (default `Workstation`) names the desktop as in the ISO file name, `FEDORA_PRODUCT` the compose
  directory and CHECKSUM: KDE Plasma Desktop is edition `KDE-Desktop` but product `KDE` (`KDE/`,
  `Fedora-KDE-iso-45_Beta-1.3-aarch64-CHECKSUM`); every other value is a spin under `Spins/`, which share the
  `Spins` CHECKSUM. `KDE-Mobile` is a spin.

## ISO layout

- `Fedora-Workstation-Live-44-1.7.aarch64.iso`, volume id `Fedora-WS-Live-44`, built by kiwi. The live root
  `/LiveOS/squashfs.img` is EROFS (LZMA, fragments, dedupe), 2.36 GB.
- Hybrid GPT + El Torito UEFI image + appended ESP. `/EFI/BOOT/grub.cfg` does
  `search --file --set=root /boot/0x503d6c7e`, then `configfile ($root)/boot/grub2/grub.cfg`.
- Loader paths under `/boot/aarch64/loader/`: `linux`, `initrd`, the font `grub2/fonts/unicode.pf2`. Step 50 reads
  them from the ISO, maps `sp11-console.pf2` in beside the font and reproduces the layout with
  `xorriso ... -boot_image any replay -map ...`.

### KDE Plasma Desktop image

- `Fedora-KDE-Desktop-Live-45_Beta-1.3.aarch64.iso`, 3.4 GB, volume id `Fedora-KDE-Live-45`: the same kiwi layout,
  loader paths and live menu, so step 50 remasters it unchanged. It carries Plasma 6.7.4, the same stock kernel
  set (7.2.0-61), Anaconda 45.22 with `slitherer` (see Anaconda) and every iptsd and sensors dependency, so
  step 50 installs no dependency RPM.
- Step 50 replaces Fedora's iio-sensor-proxy with the SP11 build, which satisfies KWin's `Requires`; KWin reads
  orientation and light over D-Bus itself (`net.hadess.SensorProxy`, not `qt6-qtsensors`). `sp11-sensors-check`'s
  mutter query fails on Plasma with a D-Bus error; the rest of its output applies.

## GRUB image, font and modules

- Fedora's aarch64 GRUB image lacks `efi_uga`, `video_bochs`, `video_cirrus` and `chain`. `insmod NAME` resolves
  `$prefix/arm64-efi/NAME.mod` and works with Secure Boot disabled; `grub2-efi-aa64-modules` provides
  `/usr/lib/grub/arm64-efi/*.mod`.
- GRUB has no text-scale setting (`gfxterm` sizes its cell from the loaded PF2 font), so only a large font keeps
  the menu legible at the panel's native mode. Step 30 builds `sp11-console.pf2` with
  `grub2-mkfont -s "$GRUB_FONT_SIZE"` from DejaVu Sans Mono; at 40 pt the cell is 24x48 px, 120x40 characters at
  2880x1920. DejaVu's Bitstream-Vera licence needs the extra `License:` term and a font name without "Bitstream"
  or "Vera".
- `00_header` honours `GRUB_FONT`: a single `if loadfont <path>` replaces its own font search, so exactly one font
  is loaded. The result (grub2 2.12-76.fc45) is `if loadfont /grub2/fonts/sp11-console.pf2` and
  `set gfxmode=2880x1920,auto`.
- The font file must be under `/boot`: on the LUKS layout nothing else is readable by GRUB, 00_header's own
  fallback `/usr/share/grub/unicode.pf2` included.
- A `GRUB_FONT` naming a missing file makes 00_header run `grub2-probe` on it and grub2-mkconfig fails outright, so
  `sp11-grub-defaults` writes an empty `GRUB_FONT=` (the supported opt-out) whenever the copy into
  `/boot/grub2/fonts/` did not happen.
- The ESP stub `EFI/fedora/grub.cfg`, which Anaconda writes with `gen_grub_cfgstub`, does
  `search --fs-uuid <boot uuid>` and `configfile $prefix/grub.cfg` with `$prefix` set to `/boot/grub2`; it names
  one /boot, so a second Fedora on the same ESP takes the menu over. Fedora's aarch64 os-prober has no EFI Windows
  probe (`os-probes/mounted/efi/` holds only `05shell`), so `GRUB_DISABLE_OS_PROBER=false` never finds Windows;
  the Windows generator is `29_sp11_windows` to precede `30_uefi-firmware` (UEFI Firmware Settings) in
  `/etc/grub.d/` order.

## Live initramfs and live menu

- The stock live initramfs is `dracut --no-hostonly --no-hostonly-cmdline` with `--install /.profile`,
  `--add "dmsquash-live livenet pollcdrom"` and `--omit multipath`; step 50 runs the same in a chroot of the live
  root, plus the Fedora 45 omissions below.
- Fedora's live `grub.cfg` is kept (`set default="1"` selects the media check, `timeout=10`). Step 50 changes only
  what the SP11 needs: the console-font block replaces `terminal_output console` after the
  `search --file --set=root <marker>` line, every `linux` line gets `$sp11_args` (installed + live-only
  arguments) and every `initrd` line a following `devicetree $sp11_dtb`; an unrecognised layout stops the build.
- `rd.live.check` needs the ISO checksum that `implantisomd5` writes and xorriso's remastering drops; step 50
  implants it again and checks the result with `checkisomd5`.

## Anaconda

- Anaconda (44.30 and 45.22) discovers kernels only from `/boot/vmlinuz-*` (45.22 also `vmlinuz-dtbloader.efi`)
  and runs `kernel-install add <ver> /lib/modules/<ver>/vmlinuz` for each. Step 50 installs the SP11 kernel with
  `--noscripts`, so it copies `vmlinuz` and `.vmlinuz.hmac` to `/boot` itself, as `20-grub.install` would.
- Only `preserved_arguments` (`clk_ignore_unused pd_ignore_unused arm64.nopauth`, in 45.22 also
  `systemd.tpm2_wait`) reach the boot args from the live command line, plus `rhgb quiet` and storage arguments;
  `modprobe.blacklist`, `rd.driver.blacklist`, the soundwire argument and the live root's `/etc/default/grub`
  never do. Anaconda's commands and their output are in `/var/log/anaconda/program.log`.

Installation order, from `modules/boss/installation.py`:

1. Payload: `PrepareSystemForInstallationTask` writes `/etc/modprobe.d/anaconda-denylist.conf` from
   `modprobe.blacklist=`; the live root is rsynced without `--delete`, excluding `/boot/loader/`.
2. Bootloader: `/etc/default/grub` is truncated with `GRUB_CMDLINE_LINUX` set to Anaconda's boot args,
   grub2-mkconfig creates `/etc/kernel/cmdline`, then `CreateBLSEntriesTask` deletes every BLS entry, runs
   `kernel-install add` and grub2-mkconfig again.
3. Configuration: `RecreateInitrdsTask` runs `dracut -f`.
4. On a BTRFS root (Fedora's default layout) `FixBTRFSBootloaderTask` repeats step 2 after step 3, so every
   entry's options and `/etc/kernel/cmdline` are rewritten from Anaconda's arguments after the kernel-install
   plugin ran; the `devicetree` line, the initramfs and the removed denylist survive, the GRUB settings and the
   SP11-only arguments do not.

### The Web UI viewer

- `webui_web_engine` in `[User Interface]` is `firefox` in the `fedora` profile (Workstation's parent) and
  `slitherer` (QtWebView on Qt WebEngine) in `/etc/anaconda/profile.d/fedora-kde.conf` and the spins' profiles;
  `/usr/bin/anaconda` merges the defaults, the profile and `/etc/anaconda/conf.d/*.conf` into
  `/run/anaconda/anaconda.conf`, which `/usr/libexec/anaconda/webui-desktop` reads.
- On the device slitherer draws the installer corrupted (truncated text, the language list missing) while the
  Plasma desktop is fine; its GPU rendering is the cause (`QTWEBENGINE_CHROMIUM_FLAGS=--disable-gpu` draws
  correctly, and KHelpCenter, widget-based on the same Qt WebEngine, draws correctly with the GPU, so nothing
  system-wide is changed). QtWebView versus Fedora's forced `QT_QPA_PLATFORM=xcb` (RHBZ 2483236) is not separated.
- Step 50 writes `/etc/anaconda/conf.d/90-sp11-webui.conf` (`webui_web_engine = firefox`) into any root that has
  `/usr/bin/slitherer` and stops when such a root has no Firefox (LXQt and SoaS in 45 Beta 1.3); Workstation has
  no slitherer. Step 60 checks that the resolved viewer is `firefox`.

## kernel-install and BLS entries

- Fedora's `10_linux` (`update_bls_cmdline`) rewrites every BLS entry's `options` on each grub2-mkconfig from
  `root=… ro $GRUB_CMDLINE_LINUX $GRUB_CMDLINE_LINUX_DEFAULT`, and `/etc/kernel/cmdline` when it is missing or
  older than `/etc/default/grub`. `20-grub.install` takes a new entry's options from `/etc/kernel/cmdline`
  (running grub2-mkconfig first when that file is the older one), writes `devicetree /dtb-<ver>/$GRUB_DEVICETREE`
  and copies `/usr/lib/modules/<ver>/dtb` to `/boot/dtb-<ver>`.
- kernel-install resolves `layout=other` here ("Entry-token directory … not found"), so `90-loaderentry.install`
  quits and `/etc/kernel/devicetree` is never read.
- `15-sp11-surface.install` runs before `20-grub.install`: `sp11-grub-defaults` (the single writer of the
  `/etc/default/grub` policy, also run by `sp11-first-boot`, the support RPM's `%posttrans` and step 50), then the
  SP11 arguments appended to `/etc/kernel/cmdline` (now the newer file, so 20-grub does not rerun mkconfig), then
  the Anaconda denylist removed before the initramfs rebuild. Live-only arguments are not filtered; step 60 checks
  that no Anaconda config mentions them.
- Anaconda's last grub2-mkconfig still strips the SP11-only arguments (the soundwire argument; on 44 also
  `systemd.tpm2_wait=0`) and on BTRFS the GRUB settings, so the first boot runs without them; `sp11-first-boot`
  fixes both for the second boot with `grubby --update-kernel=ALL --args` (which also updates
  `GRUB_CMDLINE_LINUX` and `/etc/kernel/cmdline`), `sp11-grub-defaults` and grub2-mkconfig.

## Live root repack

- `mkfs.erofs -Ededupe` is single-threaded in erofs-utils 1.9.4 (hours);
  `-Efragments -C1048576 --workers=N -zlzma,level=6` takes ~5 min and is only slightly larger. Use
  `--file-contexts` from the root's own SELinux policy.
- `mkfs.erofs -T` alone implies `--all-time`, so every file gets the build time and Anaconda's `rsync -t` copies
  that onto the installed system; step 50 passes `--mkfs-time` since 2026-09-22 and asserts that
  `/usr/lib/os-release` keeps its time. Systems installed from an ISO built up to 2026-09-21 carry the build date
  on every file (`rpm -V` flags the times; no malfunction).

## Chroot and RPM pitfalls

- In a chroot without udev `lsblk` reports empty PARTTYPE/FSTYPE; use `blkid -c /dev/null -o device -t TYPE=vfat`
  and `blkid -p -s PART_ENTRY_TYPE -o value DEV`.
- `%systemd_postun_with_restart NAME@.service` on a template unit is a no-op (`systemctl try-restart` rejects a
  name without instance); restart `'NAME@*.service'` explicitly.
- dracut `install_items` applies to `--no-hostonly` builds too, so step 50 parks the support RPM's drop-in during
  the live initramfs run and installs only the GPU zap shader.
- `rpm --noscripts` also skips triggers, so step 50 runs `sp11-ucm-apply` in the chroot itself; on a normal install
  the support RPM's `%triggerin -- alsa-ucm` and `%triggerin -- grub2-efi-aa64-modules` fire for its own
  installation too and systemd's file triggers reload systemd and udev, so the spec needs no `%post`.
- Never install RPMs into the live root with `--nodeps`: `sp11-iptsd` without `spdlog` (which Workstation Live
  lacks) fails udev's `check-device`, so no `sp11-iptsd@` unit starts; `LIVE_EXTRA_PKGS` in `sp11.conf` lists
  what step 10 downloads and step 50 installs first, step 50 refuses unmet dependencies (`rpm -U --test`) and
  step 60 checks that the shipped binaries load.

## Fedora 45 differences (verified 2026-09-16 against 45 Beta 1.3)

### Building for the target release

- fmt 11.2.0 → 12.1.0 and spdlog 1.15.3 → 1.17.0 change the sonames `sp11-iptsd` links against, so a host-built
  RPM cannot install into an F45 root: `IPTSD_BUILD_MODE=auto` builds iptsd in `mock` for the target whenever
  `FEDORA_RELEASE` differs from `rpm -E %{fedora}`, as the kernel and the sensors chain always are;
  `sp11-bt-set-addr` is libc-only.
- `mock_rebuild` in `lib.sh` passes `--no-bootstrap-image` (no podman) and retries once with `--isolation=simple`
  for WSL; `rpm/sp11-iptsd.spec.in` needs `BuildRequires: cmake`, as meson finds Microsoft.GSL only through its
  CMake config.

### kernel-uki-dtbloader

- On aarch64 Fedora's images boot `kernel-uki-dtbloader` and carry no `kernel-core` (the 44 1.7 and 45 Beta sets:
  `kernel`, `kernel-modules{,-core,-extra}`, `kernel-uki-dtbloader`): a systemd-stub UKI with `.dtbauto` device
  trees and a `.hwids` table from Fedora's `stubble` package, which `Conflicts:` with `kernel-core` of the same
  version. Its `%posttrans` runs `kernel-install add` on `vmlinuz-dtbloader.efi`, `20-grub.install` writes an
  ordinary BLS entry, and the stub replaces a DTB it did not choose with its own of the same compatible.
- The SP11 media install `kernel-core` instead (`KERNEL_PKGS`): this unit's SMBIOS hardware IDs match no stubble
  entry (`docs/hardware.md`), and Fedora documents `kernel-core` with `GRUB_DEVICETREE` as the manual path.
  `kernel-tools` and `kernel-tools-libs` track the kernel version too but own nothing in `/boot`.

### The dnf5 repository override

- The support RPM keeps stock kernels off installed systems with
  `/usr/share/dnf5/repos.override.d/90-sp11-kernel.repo`, a `[*]` section with
  `excludepkgs=kernel,kernel-core,…,kernel-uki-*` that dnf5 5.4 applies to configured repositories only, so a
  kernel RPM given as a file installs from `@commandline` (step 35 checks this). Support 1.6–2.7 used a global
  `[main] excludepkgs` in `libdnf5.conf.d`, which also hid local RPMs of those names.
- dnf5 has no `--disableexcludes`; the override is `dnf --setopt=disable_excludes='*' ...`.

### Rescue image and initramfs content

- No rescue image (`dracut_rescue_image="no"` in the support RPM's drop-in): `51-dracut-rescue.install` copies the
  kernel's BLS entry with the version replaced, so `devicetree /dtb-<version>/…` becomes
  `/dtb-0-rescue-<machine-id>/…`, a directory nothing creates.
- `LIVE_DRACUT_OMIT` in step 50 omits two new aarch64 dracut modules that defeat the live-media policy:
  `devicetree-firmware`, whose `--no-hostonly` path globs `$fw_dir/qcom/x1e80100/*/*/*.mbn|elf` (the Denali set),
  and `qcom-adsp`, which modprobes `qcom_q6v5_pas` from a pre-udev hook past the live-only DSP blacklist. The
  installed initramfs needs the Adreno microcode for plymouth's GPU probe, or early boot logs
  `failed to load gen70500_sqe.fw` until switch-root: `payload/90-sp11.conf` installs `qcom/gen70500_sqe.fw.xz`
  and `qcom/gen70500_gmu.bin.xz` from `qcom-firmware`, a support RPM `Requires:` since 2.0.

### Stock kernel removal from the live root

- Step 50 erases the stock set (`KERNEL_STOCK_PKGS`) from the live root with `rpm -e --noscripts` before installing
  the SP11 build of the same packages, so the installer only ever sees the SP11 kernel; a stock kernel left
  installed without its `/boot` image breaks `dracut --regenerate-all` (dracut 111 falls back to
  `/boot/efi/<machine-id>/<ver>/initrd` and fails with `Can't write to ...`). The depmod outputs are `%ghost`, so
  nothing stays behind; step 50 still removes unowned leftovers and refuses any other module tree.
- `/boot/loader/entries` is `0700 root`, so an unprivileged shell cannot expand a glob inside it: the BLS cleanup
  runs root-side (`as_root find ... -delete`); the earlier `rm -rf .../entries/*.conf` was a silent no-op that
  shipped the source media's stock and rescue entries.
