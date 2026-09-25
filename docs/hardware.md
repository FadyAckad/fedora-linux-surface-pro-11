# Hardware
The tested unit, its peripherals and their userspace, and the Bluetooth pairings shared with Windows.

## Target hardware (tested unit)

- Product `Microsoft Surface Pro with 5G, 11th Edition`, SKU `Surface_Pro_with_5G_11th_Edition_2077`, X1E80100,
  Samsung (SDC) OLED 2880x1920.
- Bluetooth and Wi-Fi addresses are per unit. `05-detect-hardware.sh` reads the Bluetooth address into
  `build/hardware.env`; the support RPM carries it in `/etc/sp11/bluetooth-address`.
- Device tree `qcom/x1e80100-microsoft-denali-oled.dtb`; the X1P LCD variant (`x1p64100-microsoft-denali.dtb`) is a
  different machine.
- Upstream regexes are written for the non-5G SKU (`Microsoft Surface Pro, 11th Edition`, SKU `_2076`) and need
  `( with 5G)?` / `(_with_5G)?`. `05-detect-hardware.sh` self-tests every regex against both SKUs and the live
  Windows values.
- stubble's `x1e80100-microsoft-denali.json` (the hardware-ID table of Fedora's `kernel-uki-dtbloader`) was written
  for SKUs 2076 and 2085: none of its SMBIOS-based IDs matches this SKU (product name, SKU and baseboard differ;
  computed). Fedora 45's stubble snapshot (20260320) also has IDs built from manufacturer, family and the panel's
  EDID (`SDC4195`). On the device `systemd-analyze chid` lists the EDID-based `ext1` ID (manufacturer, family,
  panel) `ca2ff828-b404-5253-9e0e-579c93bfb059`, and the `.hwids` section of the SP11 build of
  `kernel-uki-dtbloader` maps exactly that ID to `microsoft,denali-oled` (2026-09-23). Linux takes the EDID from the
  panel; the stub needs it from the firmware at boot, which is not verified, so the DTB is still loaded explicitly
  (`GRUB_DEVICETREE`) until a boot of the dtbloader image shows it.
- Windows identity queries (`05-detect-hardware.sh`): the built-in panel is the `WmiMonitorID` instance whose
  `WmiMonitorConnectionParams.VideoOutputTechnology` is 2147483648 (internal); the controller address is
  `DEVPKEY_Bluetooth_RadioAddress` (`{a92f26ca-eda7-4b1d-9db2-27b68aa5a2eb} 1`) on the Bluetooth-class device
  `QCA_SHB\UART_H4_HMT\...`, formatted `{0:X12}`. Radios under `USB\` are skipped.

## Peripherals and userspace

- Firmware: ADSP/CDSP/GPU blobs come from this device's Windows DriverStore (`surfacepro_ext_adsp8380*`,
  `qcnspmcdm_ext_cdsp8380*`, `qcdx8380*`); Fedora's `qcom-firmware` has no Denali directory. The Denali DT requests
  exactly `qcadsp8380.mbn`, `adsp_dtb.mbn`, `qccdsp8380.mbn`, `cdsp_dtb.mbn` and the zap shader `qcdxkmsuc8380.mbn`
  (all ELF); Windows ships the DT blobs as `adsp_dtbs.elf`/`cdsp_dtbs.elf`, and the support RPM installs them under
  the DT names only. Not shipped since 2.3: the `*_dtbs.elf` copies; `*.jsn` (the kernel's pd-mapper,
  `CONFIG_QCOM_PD_MAPPER=m`, is created by `qcom_common` as the `pd-mapper` aux device and needs no files; no
  userspace pd-mapper is installed); `qcdxkmsucpurwa.mbn` (X1P zap shader); `qcvss8380.mbn` (the iris node is
  `status = "disabled"` in `hamoa.dtsi` and Denali does not enable it). Step 60 compares the Denali directory with
  the DT's `firmware-name` list.
- Audio: ooaklee `sp11-audio-v19c` topology and UCM. Its `x1e80100.conf` matcher lacks the 5G variant and is patched
  via `UCM_SP11_REGEX`. `alsa-ucm` ships `conf.d/x1e80100/x1e80100.conf` as a symlink; the support RPM replaces it
  and re-applies on an `alsa-ucm` trigger.
- Wi-Fi: WCN7850, PCI 17cb:1107, `qmi-board-id=255`; no exact `board-2.bin` entry, so the 17cb:3378 entry is
  extracted with `ath12k-bdencoder` as `board.bin`. `disable-rfkill` is in the Denali DTS. `board-2.bin` is
  identical in the F44 (20260910) and F45 Beta (20260810) `atheros-firmware` packages.
- Bluetooth address: the controller enumerates without a public address; `sp11-bt-set-addr.c` (OE commit 69f40d5)
  sets it over raw HCI management before `bluetooth.service`, triggered by udev. Upstream's `parse_mac` copies the
  printed octets in order, but the MGMT payload is a little-endian `bdaddr_t`, so the unpatched helper sets the
  byte-reversed address; `30-build-support-rpm.sh` patches `out[i]` to `out[5 - i]` before compiling. The helper
  validates the index and the address itself; `sp11-bt-apply` only maps the unit instance `hciN` to `N`.
- Pen: unmodified upstream iptsd 3.1.0 (`a83bc1232f7096f8b33b50fdbda249cd640de670`) on the kernel's HIDRAW bridge
  (`hidraw` parent `001C:045E:0C83.*`, created by `mshw0485_touch` (patch 0050) with `ipts_hid_bridge` defaulting to
  on); integration templates from OE `userspace/iptsd-sp11`; the build needs cmake for meson to find Microsoft.GSL.
  The kernel's own "Microsoft Surface G6 Pen" input device is silent by design; inking comes from the
  `sp11-iptsd@dev-hidrawN.service` started by the udev rule.
- Live media boots with `modprobe.blacklist=qcom_q6v5_pas rd.driver.blacklist=qcom_q6v5_pas` (an ADSP restart resets
  USB-C while rooted on USB), so no audio or battery in the live session; the installed system drops those arguments
  via the kernel-install plugin and `sp11-first-boot.service`. Anaconda carries neither argument into the boot
  entry, but turns the first into `/etc/modprobe.d/anaconda-denylist.conf`, which the kernel-install plugin removes
  before Anaconda rebuilds the initramfs. (`module_blacklist=` would avoid that file, but the kernel logs it with
  `pr_err` on every load attempt.)
- Windows dual-boot: `/etc/grub.d/29_sp11_windows` + `/usr/libexec/sp11/sp11-grub-modules` (copies `chain.mod` and
  its dependency closure from `moddep.lst` into `/boot/grub2/arm64-efi`; run by the generator on every
  grub2-mkconfig and by an RPM trigger on `grub2-efi-aa64-modules`, which keeps the copy matched to the GRUB image).
  Booting Windows through this entry works on the tested unit.

## Bluetooth dual-boot pairings

- Windows keeps LE bonds in `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys\<adapter>\ <device>`:
  `LTK` (16 B), `KeyLength`, `ERand` (QWORD, little-endian → BlueZ `Rand` decimal), `EDIV`, `IRK`, `AddressType` (1
  = random), `AuthReq` (0x04 MITM). The `Keys` key is SYSTEM-only, but `reg save` of the parent `Parameters` key
  works from an elevated prompt.
- BlueZ `info` fields: `[LongTermKey] Key/Authenticated/EncSize/EDiv/Rand` where `Authenticated` is the MGMT LTK
  type (0 legacy, 1 legacy+MITM, 2 SC, 3 SC+MITM); `[IdentityResolvingKey] Key`;
  `[General] AddressType=static|public`. Windows' `AuthReq` is the requested value (the keyboard shows the SC bit
  yet has non-zero EDIV/Rand), so the converter decides Secure Connections from `EDIV == ERand == 0` and MITM from
  AuthReq bit 0x04. Both Surface devices: legacy pairing, authenticated, static addresses. Keyboard USB ID
  045E:0C7A, pen 045E:0C0F.
- `scripts/70-export-bt-pairings.sh` (WSL, one UAC prompt, always exports afresh because a re-pairing rewrites the
  keys in place) → `build/out/sp11-bt-pairings.tar.gz`; converter `scripts/bt-pairings-from-hive.py` (python3-hivex,
  LE only, filtered by `BT_PAIRING_USB_IDS`); importer `/usr/libexec/sp11/sp11-bt-import-pairings` (also inside the
  tarball). Verified on 44 Workstation (keyboard connects over BLE with battery reporting) and 45 Beta Workstation
  (keyboard and pen connect without pairing again).
