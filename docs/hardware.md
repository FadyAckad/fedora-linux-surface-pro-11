# Hardware
The tested unit, its peripherals and userspace, and the Bluetooth pairings shared with Windows.

## Target hardware (tested unit)

- Product `Microsoft Surface Pro with 5G, 11th Edition`, SKU `Surface_Pro_with_5G_11th_Edition_2077`, X1E80100,
  Samsung (SDC) OLED 2880x1920. The Bluetooth and Wi-Fi addresses are per unit: `05-detect-hardware.sh` writes the
  Bluetooth address to `build/hardware.env`, the support RPM to `/etc/sp11/bluetooth-address`.
- Device tree `qcom/x1e80100-microsoft-denali-oled.dtb`; the X1P LCD variant (`x1p64100-microsoft-denali.dtb`) is a
  different machine. Upstream regexes match only the non-5G SKU (`Microsoft Surface Pro, 11th Edition`, `_2076`) and
  need `( with 5G)?` / `(_with_5G)?`; `05-detect-hardware.sh` self-tests every regex against both SKUs.
- DTB loader: stubble's `x1e80100-microsoft-denali.json` (Fedora's `kernel-uki-dtbloader` hardware-ID table) matches
  this SKU only by its EDID-based `ext1` ID, `ca2ff828-b404-5253-9e0e-579c93bfb059` in `systemd-analyze chid`, which
  the SP11 build's `.hwids` section maps to `microsoft,denali-oled`. Not verified that the stub gets the panel's
  EDID at boot, so the DTB is still loaded explicitly (`GRUB_DEVICETREE`).
- Windows identity queries (`05-detect-hardware.sh`): the built-in panel is the `WmiMonitorID` instance whose
  `WmiMonitorConnectionParams.VideoOutputTechnology` is 2147483648; the controller address is
  `DEVPKEY_Bluetooth_RadioAddress` of the Bluetooth-class device `QCA_SHB\UART_H4_HMT\...`, formatted `{0:X12}`;
  radios under `USB\` are skipped.

## Peripherals and userspace

- Firmware: the ADSP, CDSP and GPU blobs come from Windows' DriverStore (`surfacepro_ext_adsp8380*`,
  `qcnspmcdm_ext_cdsp8380*`, `qcdx8380*`), Fedora's `qcom-firmware` having no Denali directory. The Denali DT
  requests `qcadsp8380.mbn`, `adsp_dtb.mbn`, `qccdsp8380.mbn`, `cdsp_dtb.mbn` and the zap shader
  `qcdxkmsuc8380.mbn`; Windows' `adsp_dtbs.elf`/`cdsp_dtbs.elf` get the DT names.
- Not shipped since support 2.3: the `*_dtbs.elf` copies; `*.jsn` (the in-kernel pd-mapper,
  `CONFIG_QCOM_PD_MAPPER=m`, needs none); `qcdxkmsucpurwa.mbn` (the X1P zap shader); `qcvss8380.mbn` (Denali leaves
  the iris node disabled).
- Audio: ooaklee's `sp11-audio-v19c` topology and UCM, with its `x1e80100.conf` matcher patched for the 5G variant
  (`UCM_SP11_REGEX`) and the microphone gain v19c leaves at 0 dB inserted into the UCM Mic device (`UCM_MIC_GAIN`,
  +16 dB). The support RPM replaces `alsa-ucm`'s `conf.d/x1e80100/x1e80100.conf` symlink and re-applies on an
  `alsa-ucm` trigger.
- Wi-Fi: WCN7850, PCI 17cb:1107, `qmi-board-id=255`; `disable-rfkill` is in the Denali DTS. Fedora's `board-2.bin`
  has no exact entry, so the 17cb:3378 entry is extracted with `ath12k-bdencoder` as `board.bin`.
- Bluetooth address: the controller enumerates without one; `sp11-bt-set-addr.c` (OE commit 69f40d5) sets it over
  raw HCI management before `bluetooth.service` (udev-triggered). Upstream's `parse_mac` fills the little-endian
  `bdaddr_t` in printed order, so `30-build-support-rpm.sh` patches `out[i]` to `out[5 - i]`; `sp11-bt-apply` only
  maps the unit instance `hciN` to `N`.
- Pen: unmodified upstream iptsd 3.1.0 (`a83bc1232f7096f8b33b50fdbda249cd640de670`); the build needs cmake for
  meson to find Microsoft.GSL. It runs on the HIDRAW bridge of `mshw0485_touch` (patch 0050), `hidraw` parent
  `001C:045E:0C83.*`, as `sp11-iptsd@dev-hidrawN.service` started by udev; the kernel's "Microsoft Surface G6 Pen"
  input device is silent by design.
- Live-only DSP blacklist: an ADSP restart resets USB-C while rooted on USB, so the live media boots with
  `modprobe.blacklist=qcom_q6v5_pas rd.driver.blacklist=qcom_q6v5_pas` (no audio or battery live). The installed
  system drops both via the kernel-install plugin and `sp11-first-boot.service`; the plugin also removes Anaconda's
  `/etc/modprobe.d/anaconda-denylist.conf`, made from the first argument, before the initramfs rebuild
  (`module_blacklist=` would avoid the file but spams `pr_err`).
- Windows dual-boot: `/etc/grub.d/29_sp11_windows` with `/usr/libexec/sp11/sp11-grub-modules`, which copies
  `chain.mod` and its dependency closure from `moddep.lst` into `/boot/grub2/arm64-efi` on every grub2-mkconfig and
  on an RPM trigger on `grub2-efi-aa64-modules`.

## Bluetooth dual-boot pairings

- Windows' LE bonds: `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys\<adapter>\<device>` holds
  `LTK` (16 B), `KeyLength`, `ERand` (QWORD, little-endian → BlueZ `Rand` decimal), `EDIV`, `IRK`, `AddressType`
  (1 = random) and `AuthReq` (0x04 MITM). `Keys` is SYSTEM-only; `reg save` of its parent `Parameters` works
  elevated.
- BlueZ `info` fields: `[LongTermKey] Key/Authenticated/EncSize/EDiv/Rand` (`Authenticated` is the MGMT LTK type:
  0 legacy, 1 legacy+MITM, 2 SC, 3 SC+MITM), `[IdentityResolvingKey] Key`, `[General] AddressType=static|public`.
  Windows' `AuthReq` is only the requested value (the keyboard shows SC yet non-zero EDIV/Rand): Secure Connections
  is decided from `EDIV == ERand == 0`, MITM from AuthReq bit 0x04.
- Tools: `scripts/70-export-bt-pairings.sh` (WSL, one UAC prompt; always afresh, a re-pairing rewrites the keys)
  writes `build/out/sp11-bt-pairings.tar.gz`; `scripts/bt-pairings-from-hive.py` converts (python3-hivex, LE only,
  `BT_PAIRING_USB_IDS`); `/usr/libexec/sp11/sp11-bt-import-pairings`, also inside the tarball, imports.
- Both devices: legacy pairing, authenticated, static addresses; keyboard 045E:0C7A, pen 045E:0C0F; both connect
  without pairing again (`docs/verified.md`).
