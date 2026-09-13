# CLAUDE.md — Fedora live ISO for Surface Pro 11 (5G, X1E80100, OLED)

Working notes for future sessions. Facts below were verified during the 2026-09-13 build; re-verify
anything that depends on a newer Fedora, GRUB, Anaconda or ooaklee release before relying on it.

## Repository

- `sp11.conf` holds every version, URL, regex and boot-policy string. Scripts source it via `scripts/lib.sh`.
- `scripts/NN-*.sh` are the pipeline steps; each is idempotent and skips finished work unless `FORCE=1`.
  `scripts/build-all.sh` runs them in order; `scripts/60-verify-rootfs.sh` is an optional post-build check.
- `rpm/*.spec.in` are templates rendered by `render()` in `lib.sh` (`@KEY@` placeholders; unrendered
  placeholders fail the build). `files/` holds the payload shipped in `sp11-surface-support`.
- `build/` is git-ignored: `cache/` (downloads, pinned checkouts), `kernel/` (source tree, payload),
  `work/iso/` (extracted live root, root-owned), `rpms/`, `out/` (ISO + `.sha256`), `hardware.env`.
- Ground rules from the owner: never commit/push/branch, short professional communication, no compliments,
  validate instead of guessing, revisit their requirement list at the end of a task.

## Host

WSL2 Fedora 44 aarch64 running on the Surface itself; 12 cores, 11 GiB RAM, passwordless sudo, Windows
mounted at `/mnt/c`, `powershell.exe` interop available (used for SMBIOS/panel/Bluetooth detection).
No Docker/podman. `awk` was missing until `gawk` was installed; `xz` and `openssl` CLI likewise.

## Target hardware (this machine)

- Product `Microsoft Surface Pro with 5G, 11th Edition`, SKU `Surface_Pro_with_5G_11th_Edition_2077`,
  X1E80100, Samsung (SDC) OLED 2880x1920, UEFI <firmware version>.
- Bluetooth address `AA:BB:CC:DD:EE:FF`, Wi-Fi address `AA:BB:CC:DD:EE:FE` (from Windows).
- Device tree: `qcom/x1e80100-microsoft-denali-oled.dtb`. The X1P LCD variant uses
  `x1p64100-microsoft-denali.dtb` and is not this machine.
- Every upstream regex/matcher was written for the non-5G SKU (`Microsoft Surface Pro, 11th Edition`,
  SKU `..._2076`) and must allow `( with 5G)?` / `(_with_5G)?`. `scripts/05-detect-hardware.sh`
  self-tests all regexes against both SKUs and against the live Windows values.
- stubble's `x1e80100-microsoft-denali.json` hardware IDs (Fedora `stubble` package) do NOT match this
  SKU (CHIDs computed and compared: zero matches), so automatic DTB selection cannot work here; the DTB is
  always loaded explicitly (GRUB `devicetree` on live media, `GRUB_DEVICETREE` in BLS entries).

## Kernel

- Source: ooaklee/linux_ms_dev_kit-sp11, release tag `sp11-qcom-x1e-7.2.0-jg-0sp11v23`, commit
  `ce78e6ebc3d70c4a316b5721a62478ca87d6cb46`, ABI `7.2.0-jg-0sp11v23-qcom-x1e`. Source tarball and debs
  are on the OE release page with SHA256SUMS.
- Config: `python3 debian/scripts/misc/annotations --file debian.qcom-x1e/config/annotations --arch arm64
  --flavour qcom-x1e --export` reproduces the shipped config exactly except `CONFIG_VERSION_SIGNATURE`.
  The ABI is injected with `CONFIG_LOCALVERSION="-jg-0sp11v23-qcom-x1e"` (Ubuntu injects it via
  `KERNELRELEASE=` at build time). Native build: ~15 min, 7816 modules, identical set to ooaklee's deb.
- Kernel image is `arch/arm64/boot/vmlinuz.efi` (EFI zboot PE, 2 sections, no stubble). ooaklee's own
  release is also `external-required` DTB delivery (no embedded DTBs).
- Config facts that matter: EROFS+LZMA+xattr built in as module, `CONFIG_LSM="landlock,lockdown,yama,
  integrity,apparmor"` (AppArmor active, SELinux compiled but inactive → Fedora runs without MAC),
  `CONFIG_SECURITY_APPARMOR_RESTRICT_USERNS=y` (see Flatpak below), no `CONFIG_CRYPTO_FIPS`,
  `MODULE_SIG=y` with an ephemeral build key, module compression zstd, `FW_LOADER_COMPRESS_XZ=y`.
- `depmod -b BASE` on Fedora expects `BASE/lib/modules`; the payload uses `/usr/lib/modules`, so
  `20-build-kernel.sh` points a temporary `lib -> usr/lib` symlink at it.

## Fedora 44 live media facts

- ISO `Fedora-Workstation-Live-44-1.7.aarch64.iso`, volume id `Fedora-WS-Live-44`, built by kiwi.
  Live root is `/LiveOS/squashfs.img` but is actually **EROFS (LZMA, fragments, dedupe)**, 2.36 GB.
- Boot layout: hybrid GPT + El Torito UEFI image + appended ESP; `/EFI/BOOT/grub.cfg` stub does
  `search --file --set=root /boot/0x503d6c7e` then `configfile ($root)/boot/grub2/grub.cfg`.
  Kernel `/boot/aarch64/loader/linux` (stubble PE with 21 `.dtbauto` sections), initrd
  `/boot/aarch64/loader/initrd`, font `/boot/aarch64/loader/grub2/fonts/unicode.pf2`.
  `xorriso -indev SRC -outdev DST -boot_image any replay -map ...` reproduces the layout.
- Fedora's aarch64 GRUB image contains `devicetree`, `gfxterm`, `loadfont`, `blscfg`, `fat`, `efi_gop`,
  `all_video`, `search_fs_uuid`, `part_gpt`, `fwsetup`; it does NOT contain `efi_uga`, `video_bochs`,
  `video_cirrus` or `chain`/`chainloader` (Fedora builds `chain` only for x86). `insmod` of
  `/usr/lib/grub/arm64-efi/*.mod` from `grub2-efi-aa64-modules` works while Secure Boot is disabled
  (lockdown is tied to Secure Boot state); GRUB looks for modules under `$prefix/arm64-efi/`, and
  `$prefix` is `/boot/grub2` on installed Fedora.
- Stock live initramfs was built with `dracut --no-hostonly --no-hostonly-cmdline --install /.profile
  --add "dmsquash-live livenet pollcdrom" --omit multipath`; reproduce it in a chroot of the live root.
  It includes the `fips` dracut modules by default; the pipeline omits them.
- Anaconda (44.30) discovers installable kernels from `/boot/vmlinuz-*` in the live root and calls
  `kernel-install add <ver> /lib/modules/<ver>/vmlinuz`. Deleting the stock `/boot/vmlinuz-*` makes the
  custom kernel the only candidate while `kernel-core` stays installed. Anaconda writes `/etc/default/grub`
  itself (no `GRUB_DEVICETREE`), persists `modprobe.blacklist=` into `/etc/modprobe.d/anaconda-denylist.conf`,
  and preserves `clk_ignore_unused pd_ignore_unused arm64.nopauth` (not `systemd.tpm2_wait=0`).
- Fedora's `20-grub.install` adds `devicetree /dtb-<ver>/$GRUB_DEVICETREE` to BLS entries and copies
  `/usr/lib/modules/<ver>/dtb` to `/boot/dtb-<ver>`; systemd's `90-loaderentry.install` reads
  `/etc/kernel/devicetree`. The pipeline's `15-sp11-surface.install` sets both before they run.
  Verified in a chroot: `scripts/60-verify-rootfs.sh`.
- `mkfs.erofs -Ededupe` is single-threaded in erofs-utils 1.9.4 (hours); `-Efragments -C1048576
  --workers=N -zlzma,level=6` finishes in ~5 min and is only slightly larger. Use `--file-contexts`
  from the root's own SELinux policy.
- `grep -q` at the end of a pipeline under `set -o pipefail` fails spuriously (SIGPIPE); use
  `grep ... >/dev/null`.
- Fedora's `os-prober` on aarch64 ships no EFI Windows probe (`/usr/libexec/os-probes/mounted/efi/`
  has only `05shell`), so `GRUB_DISABLE_OS_PROBER=false` never finds Windows on this platform.

## Peripherals and userspace

- Firmware: ADSP/CDSP/GPU blobs come from this device's Windows DriverStore
  (`surfacepro_ext_adsp8380*`, `qcnspmcdm_ext_cdsp8380*`, `qcdx8380*`); Fedora's `qcom-firmware` has no
  Denali directory. The DTS names `adsp_dtb.mbn`/`cdsp_dtb.mbn`; Windows ships `adsp_dtbs.elf`/
  `cdsp_dtbs.elf`, so both names are installed. GPU zap shader: `qcdxkmsuc8380.mbn`.
- Audio: ooaklee release `sp11-audio-v19c` (topology + UCM); its `x1e80100.conf` matcher lacks the 5G
  variant and is patched via `UCM_SP11_REGEX`. `alsa-ucm` ships `conf.d/x1e80100/x1e80100.conf` as a
  symlink; the support RPM replaces it (re-applied by an RPM trigger on `alsa-ucm`).
- Wi-Fi: WCN7850, PCI subsystem 17cb:1107, `qmi-board-id=255`; no exact entry in `board-2.bin`, so the
  17cb:3378 entry is extracted with `ath12k-bdencoder` as `board.bin` (rjindael/ooaklee approach).
  `disable-rfkill` is already in the Denali DTS.
- Bluetooth: controller enumerates without a public address; `sp11-bt-set-addr.c` (OE commit
  69f40d5) sets it via raw HCI mgmt before `bluetooth.service`, triggered by udev.
- Pen: unmodified upstream iptsd 3.1.0 (`a83bc1232f7096f8b33b50fdbda249cd640de670`) on the kernel's
  HIDRAW bridge `001C:045E:0C83`; integration templates from OE `userspace/iptsd-sp11`. Needs `cmake`
  installed for meson to find Microsoft.GSL.
- Live session intentionally boots with `modprobe.blacklist=qcom_q6v5_pas rd.driver.blacklist=qcom_q6v5_pas`
  (ADSP restart resets USB-C while rooted on USB), so no audio/battery on the live USB; the installed
  system drops those arguments (kernel-install plugin + `sp11-first-boot.service`).

## Hardware results so far (reported by the owner, 2026-09-13)

- ISO boots, installs, and everything works except Flatpak: `bwrap: Creating new namespace failed:
  Permission denied`. Cause: `CONFIG_SECURITY_APPARMOR_RESTRICT_USERNS=y` with no AppArmor profiles on
  Fedora. Fix: `kernel.apparmor_restrict_unprivileged_userns = 0` via `/usr/lib/sysctl.d/90-sp11.conf`
  in `sp11-surface-support` ≥ 1.1.
- Windows is absent from the installed GRUB menu (two ESPs on the disk; no `chain` in Fedora's aarch64
  GRUB). Addressed by `/etc/grub.d/41_sp11_windows` in `sp11-surface-support` ≥ 1.2 (see that file).

## Reference material used

- rjindael/fedora-surface-pro-11 (Fedora bring-up notes, grubby/BLS handling, Wi-Fi board fixup).
- ooaklee/linux-surface-pro-11-oe (kernel/audio/iptsd releases, ADRs) and ooaklee/lexr.sh
  (`internal/image/fedora/*.go` documents a Fedora remaster design; its hardware boot was never
  qualified, issue #17). Fedora wiki "Snapdragon WoA Laptop Install" for the kernel arguments.
