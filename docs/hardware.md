# Hardware
The tested unit and how the build identifies it, its firmware, audio, Wi-Fi, Bluetooth, pen, power supplies, video
codec and USB-C, the live-only DSP blacklist, the Windows GRUB entry, and the Bluetooth pairings shared with
Windows. Sleep and its wake sources: `docs/sleep.md`. The 5G modem: `docs/modem.md`. The cameras: `docs/camera.md`.

## Tested unit

- Product `Microsoft Surface Pro with 5G, 11th Edition`, SKU `Surface_Pro_with_5G_11th_Edition_2077`, X1E80100,
  Samsung (SDC) OLED 2880x1920. The Bluetooth and Wi-Fi addresses are per unit: step 05 writes the Bluetooth
  address to `build/hardware.env`, the support RPM to `/etc/sp11/bluetooth-address`.
- Device tree: `qcom/x1e80100-microsoft-denali-oled.dtb`; from 7.2.11 revision 3 the 5G SKU boots
  `qcom/x1e80100-microsoft-denali-oled-5g.dtb`, the same tree plus its modem. `dtb_for_sku` in `scripts/lib.sh`
  picks the tree by SKU (`SP11_SKU_5G_REGEX`); the SKUs without a modem keep the OLED tree. The X1P LCD variant
  (`x1p64100-microsoft-denali.dtb`) is a different machine.
- Upstream regexes match only the non-5G SKU (`Microsoft Surface Pro, 11th Edition`, `_2076`) and need
  `( with 5G)?` / `(_with_5G)?`; step 05 self-tests every regex, and which SKU takes which tree, against both SKUs.
- DTB loader: stubble's `x1e80100-microsoft-denali.json` (Fedora's `kernel-uki-dtbloader` hardware-ID table) matches
  this SKU only by its EDID-based `ext1` ID, `ca2ff828-b404-5253-9e0e-579c93bfb059` in `systemd-analyze chid`, which
  the SP11 build's `.hwids` section maps to `microsoft,denali-oled`. Whether the stub gets the panel's EDID at boot
  is not verified, so the DTB is loaded explicitly (`GRUB_DEVICETREE`).
- Windows identity queries (step 05): the built-in panel is the `WmiMonitorID` instance whose
  `WmiMonitorConnectionParams.VideoOutputTechnology` is 2147483648; the controller address is
  `DEVPKEY_Bluetooth_RadioAddress` of the Bluetooth-class device `QCA_SHB\UART_H4_HMT\...`, formatted `{0:X12}`;
  radios under `USB\` are skipped.

## Firmware

- The ADSP, CDSP and GPU blobs come from Windows' DriverStore (`surfacepro_ext_adsp8380*`,
  `qcnspmcdm_ext_cdsp8380*`, `qcdx8380*`); Fedora's `qcom-firmware` has no Denali directory. The Denali tree
  requests `qcadsp8380.mbn`, `adsp_dtb.mbn`, `qccdsp8380.mbn`, `cdsp_dtb.mbn`, the zap shader `qcdxkmsuc8380.mbn`
  and, from 7.2.11 revision 6, the video codec's `qcvss8380.mbn` (in `qcdx8380*`, shipped since support 3.8);
  Windows' `adsp_dtbs.elf` and `cdsp_dtbs.elf` get the DT names.
- Not shipped since support 2.3: the `*_dtbs.elf` copies; `*.jsn` (the in-kernel pd-mapper,
  `CONFIG_QCOM_PD_MAPPER=m`, needs none); `qcdxkmsucpurwa.mbn` (the X1P zap shader); `qcvss8380_pa.mbn` (the X1P
  video firmware).

## Audio

- ooaklee's `sp11-audio-v19c` topology and UCM, with the `x1e80100.conf` matcher patched for the 5G variant
  (`UCM_SP11_REGEX`) and the microphone gain v19c leaves at 0 dB inserted into the UCM Mic device (`UCM_MIC_GAIN`,
  +16 dB). The support RPM replaces `alsa-ucm`'s `conf.d/x1e80100/x1e80100.conf` symlink and re-applies on an
  `alsa-ucm` trigger.
- The UCM sets `WSA_RX0/RX1 Digital Volume` 81 (-3 dB, also the machine driver's cap) while the path is idle.
  Since 7.2.11 `lpass-wsa-macro.c` writes the interpolator's digital volume again once its clock runs (upstream
  `b2047b8cadad`), so the value applies at playback start; on the device both read 81 and the speakers' level and
  balance passed.

## Wi-Fi

- WCN7850, PCI 17cb:1107, `qmi-board-id=255`; `disable-rfkill` is in the Denali DTS. Fedora's `board-2.bin` has
  no exact entry, so the 17cb:3378 entry is extracted with `ath12k-bdencoder` as `board.bin`.
- After a boot or a wake (every deep sleep restarts the firmware) the firmware starts in world roaming, and
  NetworkManager's first scan takes 16 s, because the firmware's own country scan (802.11d) sets `DE` about 7 s
  into it. With the country known a full scan of the 102 channels (none limited to passive scanning) takes 8.5 s,
  association 0.3 s and DHCP 3 s: online 21 s after a wake, 27 s after the kernel's start (7.2.11 revision 8,
  2026-10-29). A country from user space (`iw reg set`) reaches ath12k only with
  `ATH_REG_DYNAMIC_USER_REG_HINTS`, which needs `CFG80211_CERTIFICATION_ONUS`; Fedora sets neither.
- PCIe L1.2 (7.2.11 revision 5, 2026-10-28): the Wi-Fi (`0004:01:00.0`) and NVMe (`0006:01:00.0`) functions
  report snoop and no-snoop latencies of 0 ns (nothing programs them on Qualcomm hosts), below the links'
  `LTR1.2_Threshold` (76800 ns Wi-Fi, 136192 ns NVMe), so the links enter L1.1 and almost never L1.2
  (`/sys/kernel/debug/pci@1c08000/link_transition_count`: 42408 against 49 entries since boot). Clearing `LTR_EN`
  on the Wi-Fi function (a proposed quirk) or setting the threshold to 0 on both ends (as Windows does) turned every
  L1.1 entry into L1.2 (about 11000 per 2 minutes; the NVMe link 3 to 6) with no warning and no lost connection,
  but the draw with the screen on stayed within 15 mW (6.95 to 6.97 W per 2-minute window). Neither is carried.

## Bluetooth address

- The controller enumerates without an address; `sp11-bt-set-addr.c` (OE commit 69f40d5) sets it over raw HCI
  management before `bluetooth.service` (udev-triggered). Upstream's `parse_mac` fills the little-endian `bdaddr_t`
  in printed order, so step 30 patches `out[i]` to `out[5 - i]`; `sp11-bt-apply` only maps the unit instance
  `hciN` to `N`.

## Pen

- Unmodified upstream iptsd 3.1.0 (`a83bc1232f7096f8b33b50fdbda249cd640de670`); the build needs cmake for meson to
  find Microsoft.GSL. It runs on the HIDRAW bridge of `mshw0485_touch` (patch 0050), `hidraw` parent
  `001C:045E:0C83.*`, as `sp11-iptsd@dev-hidrawN.service` started by udev; the kernel's "Microsoft Surface G6 Pen"
  input device is silent by design.

## Power supplies and battery

- Supplies (`sp11-diag`): `ADP1` (Mains, the Surface Aggregator's `surface_charger`), `qcom-battmgr-ac`, `-bat`,
  `-usb` and `-wls` (pmic_glink's battery manager) and per USB-C connector `ucsi-source-psy-pmic_glink.ucsi.0N`
  (USB); `surface_battery` loads but patch 0055 keeps it from binding.
- Since 7.2.11 revision 2 (patches 0075 to 0077) the battery has `capacity` and UPower takes its percentage from
  it; a full battery on external power reads `Full`; unplugging or plugging in a USB-C charger sends a `change`
  uevent for `qcom-battmgr-usb`, and UPower's `on-battery` follows at once.
- Before revision 2: UPower computed the percentage, 100 % on the charger read `Not charging` (shown as
  `fully-charged`), and the Surface charger (`qcom-battmgr-ac` online, the `ucsi` supplies offline) sent no uevent
  of its own on unplugging, so UPower kept `on-battery: no` until the next resume. The Surface charger and a full
  battery were not checked again on revision 2.

## Video codec

- Iris (7.2.11 revision 7, patch 0089): `qcom-iris-decoder` and `qcom-iris-encoder` appear as V4L2 devices, and
  GStreamer 1.28.7 registers `v4l2vp9dec`, `v4l2h264dec`, `v4l2h265dec`, `v4l2av1dec`, `v4l2h264enc` and
  `v4l2h265enc`. A 720p VP9 clip (profile 0) decoded in hardware to the same 120 frames as libvpx in 0.44 s; a
  VP9 clip without an explicit format comes out as 12-bit 4:4:4 (profile 3).
- Clips made by the hardware H.264 and H.265 encoders carry colorimetry `2:4:5:4` (the H.264 one also level 1 at
  720p), which is not in the list GStreamer probes for the decoder, so `v4l2h264dec` and `v4l2h265dec` refuse them
  (`not-negotiated`). Relabelled `bt601` (`capssetter`), the H.264 clip decoded to 120 frames in 0.43 s, among
  them all 60 that Cisco's `openh264dec` put out, and the H.265 clip to 120 distinct frames in 0.44 s.

## USB-C data

- Plugged one way (`normal` in `/sys/class/typec/portN/orientation`) a USB 3 stick (SanDisk 3.2Gen1) runs at
  5000 Mb/s on both ports; turned over (`reverse`) no USB device appears within 10 s on either port, while the
  Type-C class sees the partner and its orientation. Windows finds the stick both ways (7.2.11 revisions 5 to 7).
- Port 0 is `a600000.usb` behind the PS8830 retimer on `i2c@b8c000`, port 1 `a800000.usb` behind the one on
  `i2c@b9c000` (both at address 0x08). A kprobe trace shows the reversed orientation reaching the retimer and the
  QMP PHY, and the PHY rewriting its tables for it, so the switch lookup (patch 0083) is not the cause. The
  trace's timestamps run 13 to 29 ms ahead of the journal's: order events within one source.
- Reversed on revision 7: the retimer's register 0x00 reads 0x23 (connected, reversed, USB 3), the USB 3 root port
  sits in `Polling` (receivers detected, link training failing; `U0` the usual way) and the USB 2 port is
  unconnected. A port power cycle ends in `Polling` again; with the retimer's orientation bit cleared the port
  falls back to `RxDetect`. So the retimer needs its reversed setting, and the link between the PHY, set to
  reversed by the same orientation, and the retimer does not train: the PHY's lane setup for the reversed plug is
  the lead.

## TPM

- None under Linux (the kernel arguments carry `systemd.tpm2_wait=0`). Windows reports Microsoft Pluton
  (`tpmtool getdeviceinformation`: manufacturer `MSFT`, vendor `Pluton.TPM.Q`) behind the ACPI `TPM2` table's start
  method 14 (OEM `QCOM`), which Linux's `include/acpi/actbl3.h` does not define (13 is Pluton's CRB). TrustZone
  runs no `qcom.tz.tpm`, the application the X1E QSEE TPM driver uses (`qcom_scm_qseecom_app_get_id()` finds only
  `qcom.tz.uefisecapp`).

## Live-only DSP blacklist

- An ADSP restart resets USB-C while rooted on USB, so the live media boots with
  `modprobe.blacklist=qcom_q6v5_pas rd.driver.blacklist=qcom_q6v5_pas` (no audio or battery live). The installed
  system drops both through the kernel-install plugin and `sp11-first-boot.service`; the plugin also removes
  Anaconda's `/etc/modprobe.d/anaconda-denylist.conf`, made from the first argument, before the initramfs rebuild
  (`module_blacklist=` would avoid the file but spams `pr_err`).

## Windows in GRUB

- `/etc/grub.d/29_sp11_windows` with `/usr/libexec/sp11/sp11-grub-modules`, which copies `chain.mod` and its
  dependency closure from `moddep.lst` into `/boot/grub2/arm64-efi` on every grub2-mkconfig and on an RPM trigger
  on `grub2-efi-aa64-modules`.

## Bluetooth pairings shared with Windows

- Windows' LE bonds: `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys\<adapter>\<device>` holds
  `LTK` (16 B), `KeyLength`, `ERand` (QWORD, little-endian; BlueZ `Rand` in decimal), `EDIV`, `IRK`, `AddressType`
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
