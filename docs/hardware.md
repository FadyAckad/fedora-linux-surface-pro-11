# Hardware
The tested unit and how the build identifies it, its firmware, audio, Wi-Fi, Bluetooth, pen, power supplies, video
codec and USB-C, the DSP on the live media, the Windows GRUB entry, and the Bluetooth pairings shared with
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
- After the last sound (the sources of 7.3.3 revision 4, not timed on the device): WirePlumber closes the
  playback device after 5 s, its default, and 3 s later the two WSA8845 amplifiers and their SoundWire controller
  `6b10000.soundwire` suspend at run time, which stops the bus clock. The next device open starts it again. The
  SP11 profile of `wsa884x.c` programs an amplifier once per boot and expects it to report detached and attached
  around a clock stop: it switches the register cache to cache-only at the detach and syncs it at the attach
  (`wsa884x_update_status()`).
- The amplifier's resume and a detach, reported from the controller's interrupt thread, are not ordered (the
  7.2.15 and 7.3.3 trees compared on 2026-11-14). A detach reported before the resume leaves the register map
  in direct mode while the amplifier is off the bus, the state caught on 2026-11-15 (below). One reported between
  the resume's `regcache_cache_only(false)` and its `regcache_sync()` fails the resume since 7.3 (the sync
  refuses a cache-only map with `-EINVAL`) and with it the device open; no boot has shown that. The controller's
  driver gets no status back for a register write (`qcom_swrm_cmd_fifo_wr_cmd()`).
- 7.3.3 against 7.2.15, the WSA macro's clocks: on upstream's PM-clock code since 7.3.3 revision 1
  (`docs/kernel.md`, Rebase) the macro releases all four of its clocks 100 ms after the controller's suspend. The
  7.2 kernels held its two LPASS core votes (`macro`, `dcodec`) from the probe on, sleeps included, and suspended
  `mclk` and `fsgen` after 3 s.
- Since 7.3.3 the kernel log holds lines of the bus's restarts that no log of 7.2 has. In the journal's 38 boots
  of 2026-11-10 to 2026-11-14 (revisions 2 to 4, 39 playbacks): `SWR bus clsh detected` once in 7 boots,
  `Parity error detected` for both amplifiers in 3, the controller's failed enumeration
  (`SWR unknown interrupt value: 2048`) in 2.
- A patch posted upstream on 2026-10-07 and unmerged on 2026-11-14, "soundwire: qcom: wait for the interrupt
  thread before gating the clock", names these lines: the controller's suspend gates the bus clock while its
  interrupt thread still runs, and the next restart ends in a clash, parity errors or a failed enumeration that
  leaves an amplifier off the bus until a reboot. The controller's suspend, resume and interrupt handler are the
  same in 7.2.15 and 7.3.3.
- The LPASS pin controller (`6e80000.pinctrl`; its gpio12 is the amplifiers' shutdown line) takes the same two
  votes, on both series only around its register accesses: its run-time callbacks are `pm_clk_suspend` and
  `pm_clk_resume` over its clocks `core` and `audio` (`pinctrl-sm8550-lpass-lpi.c`). `on` in its `power/control`
  holds the two votes without a kernel change.

### Speakers silent after a quiet period (support 3.11)

- Reported on 2026-11-14 for 7.3.3, on the device since 2026-11-08, and not seen on 7.2: after a time without
  sound the speakers are silent, and a reboot brings them back.
- Caught on 2026-11-15 (revision 4). A restart of the stopped bus logged `SWR bus clsh detected`, and both
  amplifiers stayed off the bus (`status` UNATTACHED) while awake, for the two minutes the stream ran. The stream
  itself ran: PipeWire sent it to the built-in sink and the DSP took its data. The next restart failed the same
  way; the one after it logged the two parity lines and brought the amplifiers back, without a reboot.
- An amplifier that is off the bus answers every read with `0x21`, and the controller reports no failed write.
  The driver had the register map in direct mode, wrote into nothing and read the power stage's status as a
  fault: `PA fault: sta0=0x21 sta1=0x21 err0=0x21 err1=0x21` and `PA recovery failed ... amplifier left disabled`
  mark an amplifier that does not answer. One more of the 38 boots has them (2026-11-12, revision 3, no clash
  line).
- While it sleeps on the stopped bus an amplifier reads `Attached`. Reading its bus registers in debugfs restarts
  the bus as a playback does: on 2026-11-14 both amplifiers were off the bus 1.6 s after such a read, with no
  kernel line.
- The restart test of 2026-11-15 (revision 4) restarted the stopped bus 112 times with the kernel's clock
  handling and 112 times with the pin controller held awake, by turns, watching both amplifiers every 2 ms. With
  the kernel's handling the amplifiers left the bus for 2 to 4 ms at 7 restarts, one of them with the clash line
  and one with the parity lines; with the votes held at none, and without a line. No restart stayed failed.
- Support 3.11 holds the two votes: `78-sp11-speakers.rules` sets the pin controller's `power/control` to `on`
  when the device appears. On the device since 2026-11-15: `on` and `active` after a boot; the six boots after
  it (63 playbacks, 80 device opens, four sleeps) without one of the lines; a night at 0.26 W, within the 7.3.3
  nights (`docs/sleep.md`); no silence in two days of use (owner). Without the rule the fault came once more,
  minutes after the restart test.
- The check kits: `build/handoff/sp11-speakers-2026-11-14` (the journal of every boot, the state while the sound
  is missing) and `build/handoff/sp11-speakers-2026-11-15` (the restart test).

### A crackle at the first sound after a night's sleep (open)

- 2026-11-16, revision 4 with support 3.11: the first stream after 11.8 hours asleep, 15 s after the wake,
  restarted 44 times within 5 s while PipeWire recovered from underruns
  (`snd_pcm_avail after recover: Broken pipe`), heard as a low crackle; then it played, and so did every later
  stream. Not after the three short sleeps of the same days.
- Not new with support 3.11: the owner recalls the same crackle after wakes before it. No earlier log holds a
  sound within seconds of a night's wake. The history of the speaker check kit lists such a burst as `pw-xrun`.

## Wi-Fi

- WCN7850, PCI 17cb:1107, `qmi-board-id=255`; `disable-rfkill` is in the Denali DTS. Fedora's `board-2.bin` has
  no exact entry, so the 17cb:3378 entry is extracted with `ath12k-bdencoder` as `board.bin`.
- After a boot or a wake (every deep sleep restarts the firmware) the firmware starts in world roaming, and
  NetworkManager's first scan takes 16 s, because the firmware's own country scan (802.11d) sets `DE` about 7 s
  into it. With the country known a full scan of the 102 channels (none limited to passive scanning) takes 8.5 s,
  association 0.3 s and DHCP 3 s: online 21 s after a wake, 27 s after the kernel's start (7.2.11 revision 8,
  2026-10-29). A country from user space (`iw reg set`) reaches ath12k only with
  `ATH_REG_DYNAMIC_USER_REG_HINTS`, which needs `CFG80211_CERTIFICATION_ONUS`; Fedora sets neither. The driver
  keeps the country its 11d scan found (`ar->alpha2`) across the firmware's restart but re-sent it only after a
  crash recovery. 7.2.11 revision 9 (patch 0081) sent it when the radio started, and the first scan after a wake
  still ran over the world list (15 s, `DE` by the chip's own scan 7 s in; 2026-10-31): `ath12k_regd_update` applies
  one answer per `regd_updated` cycle, and the interfaces added right after the start re-apply the rules last
  received, so the firmware's answer loses the race unless it is in first (the night's wake: an 8.4 s scan, online
  after 13.1 s). Revision 10 waited for any regulatory event and lost the same race once in two wakes (the
  firmware's own first event completes the wait); revision 11 waited for the answer that carries the country and
  still saw the world rules at both wakes. Revision 12's log found the cause at the sleep, not the wake: the
  scan NetworkManager starts as it disconnects is aborted by the link going down, the chip's 11d scan stops and
  reports no country (`00`), and the driver takes that over as the known country and sends it to the firmware,
  so nothing is left to restore. Revision 13 keeps a known country when the 11d scan reports none and restores
  it as the radio starts: sent, answered by the firmware within a few milliseconds, applied before the interfaces
  exist; the first scan after a wake then takes 8.5 s and the station is online after 13.2 to 13.5 s, with `DE`
  and the 160 MHz link (2026-11-01, both wakes of the round). A boot has no country to restore: 27 s as before.
- Wi-Fi at boot: up to 7.2.12 the WCN7850's power sequencer kept the Wi-Fi enable line (TLMM 117) as the firmware
  left it, high at its probe, so the chip was never reset before the link trained. One boot in twelve on 7.2.11
  revision 1 (a reboot, 2026-10-20) lost Wi-Fi: the link came up and the chip answered its first read, then
  `link down error during global reset` and `failed to power up :-34`; the next reboot had Wi-Fi. 7.2.13 drives
  the line low at the probe, and the PCIe host's pwrctrl powers the chip up right before link training (upstream
  `dbd674ccf30f`, from a Surface Pro 11 whose boots never enumerated the chip); in the SP11 kernel from 7.2.14
  revision 1 on (its round's two boots, one a reboot, had Wi-Fi; 2026-11-02).
- PCIe L1.2 (7.2.11 revision 5, 2026-10-28): the Wi-Fi (`0004:01:00.0`) and NVMe (`0006:01:00.0`) functions
  report snoop and no-snoop latencies of 0 ns (nothing programs them on Qualcomm hosts), below the links'
  `LTR1.2_Threshold` (76800 ns Wi-Fi, 136192 ns NVMe), so the links enter L1.1 and almost never L1.2
  (`/sys/kernel/debug/pci@1c08000/link_transition_count`, `pcie@1c08000` since 7.3: 42408 against 49 entries since
  boot). Clearing `LTR_EN` on the Wi-Fi function (a proposed quirk) or setting the threshold to 0 on both ends (as
  Windows does) turned every L1.1 entry into L1.2 (about 11000 per 2 minutes; the NVMe link 3 to 6) with no warning
  and no lost connection,
  but the draw with the screen on stayed within 15 mW (6.95 to 6.97 W per 2-minute window). Neither is carried.

## Bluetooth address

- The controller enumerates without an address; `sp11-bt-set-addr.c` (OE commit 69f40d5) sets it over raw HCI
  management before `bluetooth.service` (udev-triggered). Upstream's `parse_mac` fills the little-endian `bdaddr_t`
  in printed order, so step 30 patches `out[i]` to `out[5 - i]`; `sp11-bt-apply` only maps the unit instance
  `hciN` to `N`.
- `sp11-bluetooth-address@hci0.service` logs at a boot: `short write 0/12` twice, `hci0 ready at T+1s`,
  `set-public-address  status 0x00 (success)`, `Success: public address set` (2026-11-10, alike from the helper
  compiled on Fedora 44 and on Fedora 45). `bluetoothctl show` then names the controller with the address of
  `/etc/sp11/bluetooth-address`.

## Pen

- Unmodified upstream iptsd 3.1.0 (`a83bc1232f7096f8b33b50fdbda249cd640de670`); the build needs cmake for meson to
  find Microsoft.GSL. It runs on the HIDRAW bridge of `mshw0485_touch` (patch 0043), `hidraw` parent
  `001C:045E:0C83.*`, as `sp11-iptsd@dev-hidrawN.service` started by udev; the kernel's "Microsoft Surface G6 Pen"
  input device is silent by design.
- The sleep hook (`payload/iptsd/sp11-iptsd-sleep`, from 3.1.0-4) stops the running instances before a sleep;
  after the wake the hidraw add event starts the daemon again. ooaklee's hook, used up to 3.1.0-3, also restarted
  it after the wake and waited, which held every wake for 1.2 to 1.5 s (`docs/sleep.md`, Wake).
- Known issue, recovering by itself: about 10 s into a boot the touch driver can log `invalid HID-SPI
  header=09 00 00 05 ready=1` and `host HID-SPI fault #1 ret=-71; scheduling cold recovery`. Those four bytes are
  the acknowledgement of the driver's own `SET_FEATURE` 0x05, which its initialization had read 0.4 ms earlier:
  the first interrupt read met it again, with the interrupt line still asserted after the driver's settle of 100
  to 200 µs. The driver resets the controller, and the HIDRAW bridge is ready 1.0 s later than in other boots.
  Seen on 2026-11-03 (7.2.15 revision 1) and 2026-11-16 (7.3.3 revision 5); touch and pen worked after it.

## Power supplies and battery

- Supplies (`sp11-diag`): `ADP1` (Mains, the Surface Aggregator's `surface_charger`), `qcom-battmgr-ac`, `-bat`,
  `-usb` and `-wls` (pmic_glink's battery manager) and per USB-C connector `ucsi-source-psy-pmic_glink.ucsi.0N`
  (USB); `surface_battery` loads but patch 0048 keeps it from binding.
- Since 7.2.11 revision 2 (patches 0068 and 0069; the third fix is upstream's own from 7.3.4 on) the battery has
  `capacity` and UPower takes its percentage from it; a full battery on external power reads `Full`; unplugging
  or plugging in a USB-C charger sends a `change` uevent for `qcom-battmgr-usb`, and UPower's `on-battery`
  follows at once.
- Before revision 2: UPower computed the percentage, 100 % on the charger read `Not charging` (shown as
  `fully-charged`), and the Surface charger (`qcom-battmgr-ac` online, the `ucsi` supplies offline) sent no uevent
  of its own on unplugging, so UPower kept `on-battery: no` until the next resume. The Surface charger and a full
  battery were not checked again on revision 2.

## Video codec

- Iris (7.2.11 revision 7, patch 0078): `qcom-iris-decoder` and `qcom-iris-encoder` appear as V4L2 devices, and
  GStreamer 1.28.7 registers `v4l2vp9dec`, `v4l2h264dec`, `v4l2h265dec`, `v4l2av1dec`, `v4l2h264enc` and
  `v4l2h265enc`. A 720p VP9 clip (profile 0) decoded in hardware to the same 120 frames as libvpx in 0.44 s; a
  VP9 clip without an explicit format comes out as 12-bit 4:4:4 (profile 3).
- Clips made by the hardware H.264 and H.265 encoders carry colorimetry `2:4:5:4` (the H.264 one also level 1 at
  720p), which is not in the list GStreamer probes for the decoder, so `v4l2h264dec` and `v4l2h265dec` refuse them
  (`not-negotiated`). Relabelled `bt601` (`capssetter`), the H.264 clip decoded to 120 frames in 0.43 s, among
  them all 60 that Cisco's `openh264dec` put out, and the H.265 clip to 120 distinct frames in 0.44 s.

## USB-C data

- Plugged one way (`normal` in `/sys/class/typec/portN/orientation`) a USB 3 stick (SanDisk 3.2Gen1) runs at
  5000 Mb/s on both ports. Turned over (`reverse`) the stick was found on neither port up to 7.2.14 revision 2,
  while the Type-C class saw the partner and its orientation and Windows ran it at USB 3 both ways: the PS8830
  retimer must be told of the connection before its mode (below; patch 0084 from 7.2.15 revision 1).
- Port 0 is `a600000.usb` behind the PS8830 retimer on `i2c@b8c000`, port 1 `a800000.usb` behind the one on
  `i2c@b9c000` (both at address 0x08). Reversed, the orientation reaches the retimer (its register 0x00 reads
  0x23: connected, reversed, USB 3) and the QMP PHY (port select 3, its tables rewritten); the USB 3 root port
  then sits in `Polling` and the USB 2 port stays unconnected: both ends present termination and nothing crosses
  the retimer's second lane, so the link never trains.
- Ruled out on the device (2026-11-03, one boot with `iomem=relaxed` and a tool writing the PHY, the controller
  and the retimer through `/dev/mem` and I2C; `docs/verified.md`): the PHY left on its normal lane (the stick
  falls back to USB 2), the PHY's port select written after the retimer as Windows does, Windows' PHY receiver and
  transmitter values, a full PHY restart after the retimer, forcing USB 3 Gen 1, Windows' controller settings; with
  its orientation bit cleared the retimer finds no pair (`RxDetect`), so it binds its lanes by that bit alone.
- The cause: the kernel wrote the retimer's final configuration (0x23) as its first word after the reset, while
  Windows writes 0x01 (connection present) first and the mode 30 ms later. Replaying the two writes on the live
  retimer of a stuck port brought the link to `U0` and the stick to 5000 Mb/s within a second, on both ports, with
  the PHY and the port untouched; the usual plug afterwards ran at 5000 Mb/s as before. Patch 0084 makes `ps883x`
  write the two steps whenever the retimer comes out of reset (`docs/kernel-patches.md`). On 7.2.15 revision 1
  the stick runs at 5000 Mb/s turned over and the usual way on both ports, after a wake and in a second boot
  (2026-11-03).
- On 7.3.5 revision 3 USB-C carries no data until the ADSP driver runs (2026-11-23): started with
  `module_blacklist=qcom_q6v5_pas`, both xHCI controllers came up but the stick enumerated on neither port, either
  way round, not even at USB 2; in the usual start it ran at 5000 Mb/s. The live media of 7.2.15 revision 1 had
  booted from USB with the ADSP blacklisted (2026-11-03) on the same UEFI version, so the dependency came with a
  kernel change between the two; its cause is not found. The retimer driver holds the retimer in reset from its
  probe until a Type-C notification, which comes from `pmic_glink` on the ADSP, in both kernels.

## TPM

- Microsoft Pluton (`tpmtool getdeviceinformation` under Windows: manufacturer `MSFT`, vendor `Pluton.TPM.Q`), a
  TPM 2.0 with PCRs in the SHA-256 bank only. Linux reaches it through the TrustZone application
  `qcom.tz.mssecapp`. From kernel 7.3.5 revision 2 a driver for that path, `tpm_qcom_mssecapp` (patches 0115 and
  0116, `docs/kernel-patches.md`), gives Fedora `/dev/tpm0` and `/dev/tpmrm0` (the device, 2026-11-22).
- Up to 7.3.5 revision 1 Linux has no TPM, and every Linux start ends without the TPM's orderly shutdown; from
  revision 2 the TPM core sends `TPM2_Shutdown` at every restart and poweroff, which this TPM refuses (Under
  Linux, below). The kernel arguments still carry `systemd.tpm2_wait=0`.
- The ACPI `TPM2` table (OEM `QCOM`) names start method 14 and a CRB control area at `0x81f10000`, without
  parameters, and the DSDT has no TPM device. The TCG ACPI specification 1.5 lists 14 as "Reserved for future
  Memory Mapped I/O Interface"; Linux's `include/acpi/actbl3.h` defines 13 (Pluton's CRB on other PCs) and 15
  (Arm FF-A), not 14.

### The path through TrustZone

- Windows' `tpm.sys` maps start method 14 to a command response buffer (CRB, TCG PC Client Platform TPM Profile)
  whose start signal is a request to `qcom.tz.mssecapp` until Windows' secure-processor driver is up, and goes over
  that driver's channel afterwards. Qualcomm's `QcTrEE.sys` sends the request as the TrustZone call that
  `qcom_scm_qseecom_app_send()` makes (function 48/0/1). Read from Windows' drivers on 2026-11-22.
- `qcom.tz.mssecapp` is loaded while Linux runs, as are `qcom.tz.winsecapp` and `qcom.tz.mfgmodemgmt`.
  Qualcomm's own `qcom.tz.tpm` is not, and has no device under Windows (name lookups from a kernel module,
  2026-11-21): the Linux driver for `qcom.tz.tpm` that was in review upstream in 2026-11 does not fit this unit.
- Each request is one 32-bit command ID, answered at offset 8 of the same buffer. `0x4007`: the interface version
  (status, the ID echoed, `0x00010000` for 1.0). `0x4004`: the CRB (the ID echoed, size, 64-bit physical address,
  status). `0x4003`: run the command in the CRB (the ID echoed, status).
- `0x4005` unloads the application; Windows sends it once its own channel is up. The CRB's cmdReady and goIdle
  never reach TrustZone: `QcTrEE.sys` clears them itself.
- A command: Windows copies it into the CRB, requires the status register to be 0, writes 1 to the start register,
  sends `0x4003`, waits for the start register to clear and reads the response. It also registers the CRB with
  TrustZone as shared memory; the Surface's kernel runs TrustZone memory in the generic mode, without that.

### On the device

- 2026-11-22, 7.3.5 revision 1 with Secure Boot off, a read-only probe module: version 1.0; the CRB at the ACPI
  table's `0x81f10000`, size `0x3000`, outside System RAM; the 48-byte control area, the command buffer right after
  it and the response buffer after that, `0x1000` each.
- Up to 7.2.15 the device tree reserved 64 KiB there (`tpm-control@81f10000`, `no-map`); 7.3's `hamoa.dtsi` has
  no such node. The range is outside System RAM all the same on 7.3.5, which the probe and the driver check before
  they map it.
- The first command took 41 ms, the next ones 7 to 9 ms, and the start register was already clear when `0x4003`
  returned: the request returns when the command is done.
- TPM2_GetCapability and TPM2_PCR_Read answered with response code 0 and as under Windows: the manufacturer and
  vendor, PCRs in the SHA-256 bank only, the four persistent handles Windows sees, PCR 0 as in Windows' log.
- `qcom_tzmem_alloc()` rounds every request up to a page. One buffer per request, the command ID at 0 and the
  answer at 8, from a pool set up like the `qcom.tz.uefisecapp` driver's, works; two buffers from a pool of one
  page failed with -12 before any call reached TrustZone.

### Under Linux

- On the device on 2026-11-22, Secure Boot on: `systemd-analyze has-tpm2` answers `yes`; PCRs 0, 7 and 9 read
  through the driver (`/sys/class/tpm/tpm0/pcr-sha256/`) equal the replay of the kernel's event log
  (`binary_bios_measurements`, 22936 bytes), PCR 0 as in Windows' logs. PCR 0 read the same after a deep sleep and
  after a restart; neither the driver nor the TPM core logged a line.
- The TPM kept the four persistent keys Windows keeps and no other, and Windows afterwards found it ready, not
  locked out, with Windows Hello as before.
- The driver binds while the SCM device probes, from the deferred probes that `deferred_probe_initcall` waits
  for, and its probe registers the TPM there: the kernel's start is 3.0 s slower than with revision 1 (`Run
  /init` at 3.72 s, the qseecom clients at 0.54 s).
- Traced at boot (function_graph, 2026-11-23): the probe takes 3.09 s, of which 2.87 s are the first
  `TPM2_SelfTest` after the firmware; the other commands 8 to 40 ms each, the null-hierarchy key of Fedora's
  `CONFIG_TCG_TPM2_HMAC=y` 0.15 s with its context save and flush. At runtime the self test takes 0.03 s.
- Windows sends no `TPM2_SelfTest`: `tpm.sys` holds no such command, and `TpmTransport::DispatchCommand` waits and
  sends a command again when the TPM answers `TPM_RC_TESTING`, so Pluton tests an algorithm when a command first
  needs it (read from `tpm.sys`, 2026-11-23). Linux's TPM core sends `TPM2_SelfTest` at every registration
  (`tpm2_auto_startup()`).
- From revision 3 the probe queues the registration on a work item and returns: the kernel runs init at 0.63 s
  and the TPM arrives at about 4.3 s, in the initramfs (2026-11-23). The initramfs's PCR 11 measurement still ran
  with the TPM: PCR 11 is the stub's value extended with `enter-initrd`, `leave-initrd`, `sysinit` and `ready`.
- The hardware still comes up about 3 s late with revision 3 (the touch controller's SPI at 4.36 s, 1.44 s with
  revision 1). `qcom_scm` runs every QSEECOM call under one mutex (`qcom_scm_qseecom_call_lock`), the self test
  is one such call, and the EFI variables go through QSEECOM too (`qcom.tz.uefisecapp`): systemd's first EFI
  variable reads after init wait for the self test, and the initramfs's journald started at 3.88 s (0.97 s with
  revision 1).
- This TPM answers `TPM2_Shutdown` with `TPM_RC_FAILURE` (0x101) and refuses every command after it until a
  reset (a software TPM goes on, as the specification has it). The kernel sends it at every restart and poweroff
  and when the driver is unbound: harmless before a reset, but an unbound driver cannot bind again (2026-11-22).
- One SELinux denial per boot: `systemd-tpm2-setup` (`init_t`) may not write `/run/log/systemd/tpm2-measure.log`
  (`syslogd_var_run_t`), 2026-11-22. Fedora's dracut 111 puts no `systemd-tpm2-setup-early.service` into the
  initramfs, so the unit runs in the root under SELinux and opens the log before it finds it may not create
  NvPCRs; the refused write recorded nothing (systemd 262.1's source). From support 3.17 a drop-in
  (`ConditionPathExists=/etc/initrd-release`) keeps the unit to the initramfs; nothing in systemd 262.1 reads the
  SRK copies in `/run` that only it writes. On the device with 3.17 the unit is skipped and no denial is logged
  (2026-11-23).

### Measured boot and the disk

- Windows keeps every boot's event log in `C:\Windows\Logs\MeasuredBoot`. PCRs 0 to 3, 5 and 6 of a Fedora start
  equal those of Windows' starts before and after it (2026-11-22). PCR 7 follows the Secure Boot state; switching
  Secure Boot off and on again restored its value.
- PCR 8 stays empty: Fedora's GRUB measures nothing on this unit. PCR 9 holds the kernel EFI stub's command line
  and initramfs events. With Secure Boot off (Fedora's own entry) PCRs 11 to 13 stay empty; with Secure Boot on
  the signed image's stub measures into PCRs 11 and 12, and systemd extends PCR 11 after it (2026-11-22).
- The kernel finds the firmware's event log at every start (`efi: ... TPMEventLog=...`).
- IMA starts before `qcom_qseecom` sets up its clients: `ima: No TPM chip found, activating TPM-bypass!` 0.3 ms
  before `setting up client for qcom.tz.uefisecapp`, in every boot with a kernel log on record.
- systemd 262 runs its TPM units (`systemd-tpm2-setup`, the `systemd-pcr*` measurements) only when systemd-stub
  measured the kernel into PCR 11 (`ConditionSecurity=measured-os`). `systemd-tpm2-setup` then takes the storage
  key at `0x81000001` and the endorsement key at `0x81010001`, which Windows keeps, and creates either only for an
  empty handle; it allocates no NvPCRs from an image without a PCR public key (systemd 262.1's source). On the
  Secure Boot route the units ran on 2026-11-22: `SRK already stored in the TPM.`, `Skipped 4 NvPCR(s)`.
- The TPM is shared with Windows: a sealed LUKS key lives in the LUKS header under Windows' storage key, and wrong
  PINs would count against the lockout counter Windows Hello uses.
- Since 2026-11-23 the tested installation's root is btrfs in LUKS2 (`aes-xts-plain64`, 512-bit key), opened in
  the initramfs about 2 s after the passphrase. Its second key slot holds a key sealed in the TPM and bound to
  PCR 7 (`systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7`, enrolled in a start through the signed entry):
  with `tpm2-device=auto` in `crypttab` the next start opened the root in 1.3 s without a prompt, and
  `systemd-tpm2-setup` found the TPM's storage root key unchanged (2026-11-23).
- systemd 262 tries the TPM token only when `crypttab` names `tpm2-device=`. A TPM that is not there yet is
  waited for, up to `token-timeout` (30 s), only when the firmware or the boot loader reports one: the signed
  image's stub sets `LoaderTpm2ActivePcrBanks`, while the device-tree start has no ACPI `TPM2` table. A policy that
  does not match (`TPM policy does not match current system state`) and a timeout both lead to the passphrase
  prompt. `systemd.tpm2_wait=0` stops only `tpm2.target` from being a synchronisation point (systemd 262.1's
  source; the refusal and the wipe run against a software TPM).
- The kernel's object interface to TrustZone (`qcomtee`) is up under Linux and reports its QTEE version at every
  start.

## The DSP on the live media

- An ADSP restart resets USB-C, and the live system runs from a USB-C stick. Since 2026-11-23 the live initramfs
  starts the ADSP as the installed one does, before the root is looked for: Fedora 45's dracut module `qcom-adsp`
  modprobes `qcom_q6v5_pas` from a pre-udev hook, and the support RPM's dracut drop-in installs the Denali firmware.
  On 7.3.5 the stick is not found otherwise (USB-C data, above): the live initramfs of 2026-11-23 waited for
  `/dev/disk/by-label/Fedora-WS-Live-45` until the emergency shell. With the ADSP started the ADSP was up 5.8 s
  into the live start, the stick enumerated at 5000 Mb/s at 6.9 s and the live root was mounted at 10.9 s; sound
  and the battery level worked live (2026-11-23).
- Media up to then booted with `modprobe.blacklist=qcom_q6v5_pas rd.driver.blacklist=qcom_q6v5_pas` (no audio or
  battery live). Anaconda makes `/etc/modprobe.d/anaconda-denylist.conf` from the first argument; the kernel-install
  plugin and `sp11-first-boot.service` remove that file and the arguments (`module_blacklist=` would avoid the file
  but spams `pr_err`).

## Windows in GRUB

- `/etc/grub.d/29_sp11_windows` with `/usr/libexec/sp11/sp11-grub-modules`, which copies `chain.mod` and its
  dependency closure from `moddep.lst` into `/boot/grub2/arm64-efi` on every grub2-mkconfig and on an RPM trigger
  on `grub2-efi-aa64-modules`.
- The `chainloader` command is built into Fedora's GRUB image 2.12-81 and 2.12-83 (`docs/secure-boot.md`); the
  copied module serves an image without it and loads only with Secure Boot off.

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
