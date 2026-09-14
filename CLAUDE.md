# CLAUDE.md — Fedora live ISO for Surface Pro 11 (5G, X1E80100, OLED)

Working notes for future sessions. Everything below was verified during the September 2026 build.
Re-verify anything that depends on a newer Fedora, GRUB, Anaconda or ooaklee release.

## Ground rules from the owner

Never commit, push or create branches. Short, professional communication; no compliments. Validate
instead of guessing. Revisit the owner's requirement list at the end of a task. `README.md` is the
user-facing guide; keep it concise and current when behaviour changes. Do not rebuild or change the
ISO on your own initiative: deliver improvements as support-RPM/script changes and ask the owner
whether each one should also go into the ISO.

## Repository

- `sp11.conf`: every version, URL, regex and boot-policy string; scripts source it via `scripts/lib.sh`.
- `scripts/NN-*.sh`: pipeline steps, idempotent, `FORCE=1` rebuilds. `build-all.sh` runs all;
  `60-verify-rootfs.sh` checks the remastered root, simulates Anaconda's kernel-install in a chroot,
  and tests the Windows generator against a fake ESP on a loop device.
- `rpm/*.spec.in`: templates rendered by `render()` (`@KEY@` placeholders; leftovers fail the build).
- `files/`: payload of `sp11-surface-support` plus the live GRUB menu template.
- `build/` (git-ignored): `cache/`, `kernel/` (source tree and payload), `work/iso/` (extracted live
  root, root-owned), `rpms/`, `out/` (ISO and `.sha256`), `hardware.env`.
- Bump `VERSION=` in `scripts/30-build-support-rpm.sh` whenever the support payload changes, so
  `dnf upgrade` works on the installed system. The RPM's `%posttrans` regenerates `grub.cfg`.

## Host

WSL2 Fedora 44 aarch64 on the Surface itself; 12 cores, 11 GiB RAM, passwordless sudo, Windows at
`/mnt/c`, `powershell.exe` interop (used for SMBIOS, panel and Bluetooth detection). No Docker.
Tools that were missing and are now in `00-setup-host.sh`: gawk, xz, openssl, cmake, dosfstools.

## Target hardware (this machine)

- Product `Microsoft Surface Pro with 5G, 11th Edition`, SKU `Surface_Pro_with_5G_11th_Edition_2077`,
  X1E80100, Samsung (SDC) OLED 2880x1920, UEFI <firmware version>, two ESPs on the NVMe (Windows and Fedora).
- Bluetooth `AA:BB:CC:DD:EE:FF`, Wi-Fi `AA:BB:CC:DD:EE:FE`.
- Device tree `qcom/x1e80100-microsoft-denali-oled.dtb`; the X1P LCD variant
  (`x1p64100-microsoft-denali.dtb`) is a different machine.
- Upstream regexes are written for the non-5G SKU (`Microsoft Surface Pro, 11th Edition`, SKU `_2076`)
  and need `( with 5G)?` / `(_with_5G)?`. `05-detect-hardware.sh` self-tests every regex against both
  SKUs and the live Windows values.
- stubble's `x1e80100-microsoft-denali.json` hardware IDs do not match this SKU (CHIDs computed:
  zero matches), so automatic DTB selection cannot work; the DTB is always loaded explicitly.

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

## Fedora 44 live media

- `Fedora-Workstation-Live-44-1.7.aarch64.iso`, volume id `Fedora-WS-Live-44`, built by kiwi. The
  live root `/LiveOS/squashfs.img` is EROFS (LZMA, fragments, dedupe), 2.36 GB.
- Hybrid GPT + El Torito UEFI image + appended ESP. `/EFI/BOOT/grub.cfg` does `search --file
  --set=root /boot/0x503d6c7e` then `configfile ($root)/boot/grub2/grub.cfg`. Kernel
  `/boot/aarch64/loader/linux` (stubble PE, 21 `.dtbauto` sections), initrd `/boot/aarch64/loader/initrd`,
  font `/boot/aarch64/loader/grub2/fonts/unicode.pf2`. `xorriso ... -boot_image any replay -map ...`
  reproduces the layout; `50-build-iso.sh` reads these paths from the ISO instead of assuming them.
- Fedora's aarch64 GRUB image has `devicetree`, `gfxterm`, `loadfont`, `blscfg`, `fat`, `efi_gop`,
  `all_video`, `search_fs_uuid`, `part_gpt`, `fwsetup`, `efinet`, `net`, `boot`. It lacks `efi_uga`,
  `video_bochs`, `video_cirrus` and `chain` (Fedora builds `chain` into x86 images only).
- `insmod NAME` resolves `$prefix/arm64-efi/NAME.mod`; on installed Fedora `$prefix` is `/boot/grub2`
  (set by `gen_grub_cfgstub`, which Anaconda calls to write the ESP stub). Module loading is refused only
  under lockdown, which is tied to Secure Boot being enabled. `grub2-efi-aa64-modules` (installed by
  default) provides the version-matched `/usr/lib/grub/arm64-efi/*.mod`.
- Fedora's os-prober has no EFI Windows probe on aarch64 (`os-probes/mounted/efi/` holds only
  `05shell`), so `GRUB_DISABLE_OS_PROBER=false` never finds Windows.
- GRUB menu order follows `/etc/grub.d/` filename order; `30_uefi-firmware` emits UEFI Firmware
  Settings, hence the Windows generator is `29_sp11_windows`.
- Stock live initramfs arguments: `dracut --no-hostonly --no-hostonly-cmdline --install /.profile
  --add "dmsquash-live livenet pollcdrom" --omit multipath`; it includes the `fips` dracut modules,
  which the pipeline omits. Generate it in a chroot of the live root.
- `rd.live.check` needs an implanted ISO checksum, which xorriso remastering does not carry over; the
  media-check menu entry was therefore removed.
- Anaconda 44.30 discovers kernels from `/boot/vmlinuz-*` and runs `kernel-install add <ver>
  /lib/modules/<ver>/vmlinuz`. Deleting stock `/boot/vmlinuz-*` makes the SP11 kernel the only
  candidate while `kernel-core` stays installed. Anaconda rewrites `/etc/default/grub`, persists
  `modprobe.blacklist=` into `/etc/modprobe.d/anaconda-denylist.conf`, preserves `clk_ignore_unused
  pd_ignore_unused arm64.nopauth` but not `systemd.tpm2_wait=0`. Its grub2-mkconfig runs in a chroot
  with `/dev` bound but no udev database.
- Fedora's `20-grub.install` writes `devicetree /dtb-<ver>/$GRUB_DEVICETREE` into the BLS entry and
  copies `/usr/lib/modules/<ver>/dtb` to `/boot/dtb-<ver>`; systemd's `90-loaderentry.install` reads
  `/etc/kernel/devicetree`. `15-sp11-surface.install` sets both before they run.
- `mkfs.erofs -Ededupe` is single-threaded in erofs-utils 1.9.4 (hours). `-Efragments -C1048576
  --workers=N -zlzma,level=6` takes ~5 min and is only slightly larger. Use `--file-contexts` from the
  root's own SELinux policy.
- In a chroot without udev, `lsblk` reports empty PARTTYPE/FSTYPE; use `blkid -c /dev/null -o device
  -t TYPE=vfat` and `blkid -p -s PART_ENTRY_TYPE -o value DEV` instead.
- `grep -q` at the end of a pipeline under `pipefail` fails spuriously (SIGPIPE); use `grep ... >/dev/null`.
- Under `set -e -o pipefail`, `var=$(ls pattern | head -1)` exits the script silently when the glob does
  not match (`ls` fails, the assignment inherits the status). Append `|| true` inside the substitution.
- Never install RPMs into the live root with `--nodeps`. Workstation Live lacks `spdlog`, which
  `sp11-iptsd` links against; the first ISO shipped a pen daemon that could not load, so udev's
  `check-device` failed and no `sp11-iptsd@` unit ever started. `LIVE_EXTRA_PKGS` in `sp11.conf` lists
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
- Bluetooth: the controller enumerates without a public address; `sp11-bt-set-addr.c` (OE commit
  69f40d5) sets it over raw HCI management before `bluetooth.service`, triggered by udev. Upstream's
  `parse_mac` copies the printed octets in order, but the MGMT payload is a little-endian `bdaddr_t`, so
  the controller came up byte-reversed (`FF:EE:DD:CC:BB:AA`). `30-build-support-rpm.sh` patches
  `out[i]` to `out[5 - i]` before compiling (support RPM ≥ 1.4). Changing the address moves BlueZ's storage
  directory; pairings made under the reversed address are orphaned and stay in the old directory.
- Pen: unmodified upstream iptsd 3.1.0 (`a83bc1232f7096f8b33b50fdbda249cd640de670`) on the kernel's
  HIDRAW bridge `001C:045E:0C83`; integration templates from OE `userspace/iptsd-sp11`; needs cmake.
- Live media boots with `modprobe.blacklist=qcom_q6v5_pas rd.driver.blacklist=qcom_q6v5_pas` (an ADSP
  restart resets USB-C while rooted on USB), so no audio or battery in the live session; the installed
  system drops those arguments via the kernel-install plugin and `sp11-first-boot.service`.
- Windows dual-boot: `/etc/grub.d/29_sp11_windows` + `/usr/libexec/sp11/sp11-grub-modules` (copies
  `chain.mod` and its dependency closure from `moddep.lst` into `/boot/grub2/arm64-efi`, re-run by an RPM
  trigger on `grub2-efi-aa64-modules`). Chainloading through GRUB changes the measured boot path; a
  BitLocker recovery prompt on the first Windows boot is possible.

## Bluetooth dual-boot pairings

- Windows keeps bonds in `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys\<adapter>`:
  LE devices as subkeys `<device>` with `LTK` (16 B), `KeyLength`, `ERand` (QWORD, little-endian → BlueZ
  `Rand` decimal), `EDIV`, `IRK`, `AddressType` (1 = random), `AuthReq` (0x04 MITM, 0x08 Secure
  Connections); classic devices as 16-byte values named by address. The `Keys` key is SYSTEM-only, but
  `reg save` of the parent `Parameters` key works from an elevated prompt (backup semantics).
- BlueZ 5.86 `info` fields: `[LongTermKey] Key/Authenticated/EncSize/EDiv/Rand` where `Authenticated` is the
  MGMT LTK type (0 legacy, 1 legacy+MITM, 2 SC, 3 SC+MITM); `[IdentityResolvingKey] Key`; `[LinkKey]
  Key/Type/PINLength`; `[General] AddressType=static|public`. Static random addresses need the `0xC0` bits.
  Windows' `AuthReq` is the requested value (the keyboard shows the SC bit yet has non-zero EDIV/Rand), so
  the converter decides Secure Connections from `EDIV == ERand == 0` and takes MITM from AuthReq bit 0x04.
  Dual-mode devices (earbuds) have both a link key value and an LE subkey; they merge into one info with
  `SupportedTechnologies=BR/EDR;LE;`. Windows' own IRK (`CentralIRK`) is not imported: BlueZ runs with
  Privacy off, so peripherals see the public adapter address the bond already identifies.
- Both Surface devices are BLE with static addresses: keyboard `11:22:33:44:55:66` (USB IDs 045E:0C7A),
  pen `11:22:33:44:55:77` (045E:0C0F). Adapter `AA:BB:CC:DD:EE:FF` on both OSes (set by
  `sp11-bluetooth-address@.service`), which is what makes key transfer possible.
- `scripts/70-export-bt-pairings.sh` (WSL, one UAC prompt) → `build/out/sp11-bt-pairings.tar.gz` with
  `files/sp11-bt-import-pairings`; converter `scripts/bt-pairings-from-hive.py` (python3-hivex). Tested with
  a synthetic hive built from `C:\Users\Default\NTUSER.DAT` and an overlay chroot of the live root.
  BitLocker state of `C:` is unknown (needs elevation), so nothing reads the NTFS partition from Linux.

## Hardware-verified status (owner reports, 2026-09-13)

Boot, install, display/GPU, Wi-Fi, Bluetooth, touch, pen, audio, battery: working. Flatpak: working
with the sysctl fix (support RPM 1.1). Windows entry in GRUB: working (RPM 1.2); RPM 1.3 only moves it
before UEFI Firmware Settings. Bluetooth pairing import (2026-09-14): the import refused because the
controller address was byte-reversed; RPM 1.4 fixes the helper, hardware result pending. The current
`build/out` ISO was built with RPM 1.1; rerun `scripts/50-build-iso.sh` before distributing new media.

## References

rjindael/fedora-surface-pro-11 (Fedora bring-up notes); ooaklee/linux-surface-pro-11-oe (kernel, audio,
iptsd releases, ADRs); ooaklee/lexr.sh `internal/image/fedora/*.go` (remaster design reference, never
hardware-qualified, issue #17); Fedora wiki "Snapdragon WoA Laptop Install".
