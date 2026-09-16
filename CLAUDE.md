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
- `build/` (git-ignored): `cache/` (downloads, pinned checkouts, `rpm-deps/`), `kernel/` (source tree and
  payload), `work/iso/` (extracted live root, root-owned), `rpms/`, `out/` (ISO, `.sha256`, pairing
  tarball), `bt-pairings/` (exported hive; secret), `hardware.env`.
- Bump `VERSION=` in `scripts/30-build-support-rpm.sh` whenever the support payload changes, so
  `dnf upgrade` works on the installed system. Its `%posttrans` regenerates `grub.cfg`. Steps 20/30/40
  skip only when the cached RPM matches (kernel ABI file list, `%{VERSION}`, iptsd version-release and
  commit), so a bump alone triggers the rebuild; `IPTSD_RPM_RELEASE` in `sp11.conf` versions the iptsd spec.
- Step 10 honours `FORCE=1` only for the two dnf-downloaded caches (`build/cache/wifi/f<release>`,
  `build/cache/rpm-deps/f<release>`); checksum-pinned downloads are never re-fetched.

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
  debs with SHA256SUMS are on the OE release page.
- `python3 debian/scripts/misc/annotations --file debian.qcom-x1e/config/annotations --arch arm64
  --flavour qcom-x1e --export` reproduces the released config exactly except `CONFIG_VERSION_SIGNATURE`.
  The ABI is injected with `CONFIG_LOCALVERSION="-jg-0sp11v23-qcom-x1e"`. Native build: ~15 min,
  7816 modules, same set as ooaklee's deb. Image is `arch/arm64/boot/vmlinuz.efi` (EFI zboot PE).
- Relevant config: EROFS with LZMA and xattrs as module; `CONFIG_LSM="landlock,lockdown,yama,integrity,
  apparmor"` (AppArmor active, SELinux inactive, Fedora runs without MAC);
  `CONFIG_SECURITY_APPARMOR_RESTRICT_USERNS=y` (denies unprivileged user namespaces without a profile;
  Fedora has none, so `kernel.apparmor_restrict_unprivileged_userns=0` is shipped in
  `/usr/lib/sysctl.d/90-sp11.conf`, otherwise Flatpak's bwrap fails with EPERM); no `CRYPTO_FIPS`;
  `MODULE_SIG=y` with an ephemeral key; zstd modules; `FW_LOADER_COMPRESS_XZ=y`.
- Fedora's `depmod -b BASE` expects `BASE/lib/modules`; the payload uses `/usr/lib/modules`, so
  `20-build-kernel.sh` uses a temporary `lib -> usr/lib` symlink.

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
  (set by `gen_grub_cfgstub`, which Anaconda calls to write the ESP stub). Module loading works with
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
  candidate while `kernel-core` stays installed. Anaconda rewrites `/etc/default/grub`, persists
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

## Peripherals and userspace

- Firmware: ADSP/CDSP/GPU blobs come from this device's Windows DriverStore (`surfacepro_ext_adsp8380*`,
  `qcnspmcdm_ext_cdsp8380*`, `qcdx8380*`); Fedora's `qcom-firmware` has no Denali directory. The DTS
  names `adsp_dtb.mbn`/`cdsp_dtb.mbn`; Windows ships `adsp_dtbs.elf`/`cdsp_dtbs.elf`; both names are
  installed. GPU zap shader `qcdxkmsuc8380.mbn`.
- Audio: ooaklee `sp11-audio-v19c` topology and UCM. Its `x1e80100.conf` matcher lacks the 5G variant
  and is patched via `UCM_SP11_REGEX`. `alsa-ucm` ships `conf.d/x1e80100/x1e80100.conf` as a symlink;
  the support RPM replaces it and re-applies on an `alsa-ucm` trigger.
- Wi-Fi: WCN7850, PCI 17cb:1107, `qmi-board-id=255`; no exact `board-2.bin` entry, so the 17cb:3378
  entry is extracted with `ath12k-bdencoder` as `board.bin`. `disable-rfkill` is in the Denali DTS.
- Bluetooth address: the controller enumerates without a public address; `sp11-bt-set-addr.c` (OE
  commit 69f40d5) sets it over raw HCI management before `bluetooth.service`, triggered by udev.
  Upstream's `parse_mac` copies the printed octets in order, but the MGMT payload is a little-endian
  `bdaddr_t`, so the unpatched helper sets the byte-reversed address; `30-build-support-rpm.sh` patches
  `out[i]` to `out[5 - i]` before compiling. `sp11-bt-import-pairings` detects a byte-reversed adapter
  directory under `/var/lib/bluetooth` and says so.
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
  importer `/usr/libexec/sp11/sp11-bt-import-pairings` (also inside the tarball). Verified: keyboard
  connects over BLE with battery reporting after import.

## Hardware-verified status (2026-09-13/14, support RPM 1.7)

Working: boot, install, display/GPU, Wi-Fi, Bluetooth with the correct address, touch, pen inking,
audio, battery, Flatpak, Windows entry in GRUB before UEFI Firmware Settings, shared Windows pairings
for keyboard and pen, `sp11-bt-import-pairings` and `sp11-diag` under `/usr/libexec/sp11`.

Support RPM 1.7 (`sp11-diag` enumerates paired devices instead of fixed addresses; otherwise identical
to 1.6, which added `sp11-grub-defaults` and the dnf kernel exclusion) was confirmed working on the
installed system on 2026-09-14. `sp11-iptsd` 3.1.0-2.sp11 restarts the running pen daemon on upgrade.
The ISO in `build/out/` (sha256 `eb62a087…7fee`, 2026-09-14 evening) contains both.

## References

rjindael/fedora-surface-pro-11 (Fedora bring-up notes); ooaklee/linux-surface-pro-11-oe (kernel, audio,
iptsd releases, ADRs); ooaklee/lexr.sh `internal/image/fedora/*.go` (remaster design reference);
Fedora wiki "Snapdragon WoA Laptop Install"; Arch wiki "Bluetooth" (dual-boot pairing).
