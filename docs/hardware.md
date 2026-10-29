# Hardware
The tested unit, its peripherals and userspace, sleep and its wake sources, and the Bluetooth pairings shared with
Windows.

## Target hardware (tested unit)

- Product `Microsoft Surface Pro with 5G, 11th Edition`, SKU `Surface_Pro_with_5G_11th_Edition_2077`, X1E80100,
  Samsung (SDC) OLED 2880x1920. The Bluetooth and Wi-Fi addresses are per unit: `05-detect-hardware.sh` writes the
  Bluetooth address to `build/hardware.env`, the support RPM to `/etc/sp11/bluetooth-address`.
- Device tree `qcom/x1e80100-microsoft-denali-oled.dtb`; from 7.2.11 revision 3 the 5G SKU boots
  `qcom/x1e80100-microsoft-denali-oled-5g.dtb`, the same tree plus its modem (`docs/modem.md`). The build picks the
  tree by the unit's SKU (`SP11_SKU_5G_REGEX`, `dtb_for_sku` in `scripts/lib.sh`), so the SKUs without a modem keep
  the OLED tree. The X1P LCD variant (`x1p64100-microsoft-denali.dtb`) is a different machine. Upstream regexes
  match only the non-5G SKU (`Microsoft Surface Pro, 11th Edition`, `_2076`) and need `( with 5G)?` /
  `(_with_5G)?`; `05-detect-hardware.sh` self-tests every regex, and which SKU takes which tree, against both SKUs.
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
  requests `qcadsp8380.mbn`, `adsp_dtb.mbn`, `qccdsp8380.mbn`, `cdsp_dtb.mbn`, the zap shader
  `qcdxkmsuc8380.mbn` and, from 7.2.11 revision 6 on, the video codec's `qcvss8380.mbn` (in `qcdx8380*`, shipped
  since support 3.8); Windows' `adsp_dtbs.elf`/`cdsp_dtbs.elf` get the DT names.
- Not shipped since support 2.3: the `*_dtbs.elf` copies; `*.jsn` (the in-kernel pd-mapper,
  `CONFIG_QCOM_PD_MAPPER=m`, needs none); `qcdxkmsucpurwa.mbn` (the X1P zap shader); `qcvss8380_pa.mbn` (the X1P
  video firmware).
- Audio: ooaklee's `sp11-audio-v19c` topology and UCM, with its `x1e80100.conf` matcher patched for the 5G variant
  (`UCM_SP11_REGEX`) and the microphone gain v19c leaves at 0 dB inserted into the UCM Mic device (`UCM_MIC_GAIN`,
  +16 dB). The support RPM replaces `alsa-ucm`'s `conf.d/x1e80100/x1e80100.conf` symlink and re-applies on an
  `alsa-ucm` trigger.
- Wi-Fi: WCN7850, PCI 17cb:1107, `qmi-board-id=255`; `disable-rfkill` is in the Denali DTS. Fedora's `board-2.bin`
  has no exact entry, so the 17cb:3378 entry is extracted with `ath12k-bdencoder` as `board.bin`.
- Wi-Fi after a boot or a wake (7.2.11 revision 8, 2026-10-29; nl80211 events): the firmware starts in world
  roaming, and NetworkManager's first scan takes 16 s, because the firmware's own country scan (802.11d) sets `DE`
  about 7 s into it; with the country known a full scan of the 102 channels (none limited to passive scanning)
  takes 8.5 s. Association then takes 0.3 s and DHCP 3 s: online 21 s after a wake, 27 s after the kernel's start.
  Every deep sleep restarts the firmware. A country from user space (`iw reg set`) reaches ath12k only with
  `ATH_REG_DYNAMIC_USER_REG_HINTS`, which needs `CFG80211_CERTIFICATION_ONUS`; Fedora sets neither.
- PCIe L1.2 (7.2.11 revision 5, 2026-10-28): the Wi-Fi (`0004:01:00.0`) and NVMe (`0006:01:00.0`) functions report
  maximum snoop and no-snoop latencies of 0 ns (nothing programs them on Qualcomm hosts), which is below the
  links' `LTR1.2_Threshold` (76800 ns Wi-Fi, 136192 ns NVMe), so they never enter L1.2: since boot the Wi-Fi link
  had entered L1.1 42408 times and L1.2 49 times (`/sys/kernel/debug/pci@1c08000/link_transition_count`). At
  runtime, clearing `LTR_EN` on the Wi-Fi function (a proposed quirk) or setting the threshold to 0 on both ends
  (as Windows does) turned every L1.1 entry of the Wi-Fi link into an L1.2 entry (about 11000 per 2 minutes); the
  threshold of 0 also brought the NVMe link into L1.2 (3 to 6 entries per 2 minutes, its L1 entries being rare).
  The battery's draw with the screen on stayed within 15 mW (6.95 to 6.97 W per 2-minute window), so neither is
  carried. No kernel warning, the Wi-Fi stayed connected.
- Bluetooth address: the controller enumerates without one; `sp11-bt-set-addr.c` (OE commit 69f40d5) sets it over
  raw HCI management before `bluetooth.service` (udev-triggered). Upstream's `parse_mac` fills the little-endian
  `bdaddr_t` in printed order, so `30-build-support-rpm.sh` patches `out[i]` to `out[5 - i]`; `sp11-bt-apply` only
  maps the unit instance `hciN` to `N`.
- Pen: unmodified upstream iptsd 3.1.0 (`a83bc1232f7096f8b33b50fdbda249cd640de670`); the build needs cmake for
  meson to find Microsoft.GSL. It runs on the HIDRAW bridge of `mshw0485_touch` (patch 0050), `hidraw` parent
  `001C:045E:0C83.*`, as `sp11-iptsd@dev-hidrawN.service` started by udev; the kernel's "Microsoft Surface G6 Pen"
  input device is silent by design.
- Power supplies (`sp11-diag` of 2026-10-19): `ADP1` (Mains, the Surface Aggregator's `surface_charger`),
  `qcom-battmgr-ac`, `-bat`, `-usb` and `-wls` (pmic_glink's battery manager) and per USB-C connector
  `ucsi-source-psy-pmic_glink.ucsi.0N` (USB); `surface_battery` loads but patch 0055 keeps it from binding.
- Charger and battery on 7.2.11 revision 1 (2026-10-22): the mains charger shows as `qcom-battmgr-ac` online (the
  `ucsi` supplies stay offline). Unplugging or plugging it in sends a `change` uevent for `ADP1` and three for
  `qcom-battmgr-bat`, none for `qcom-battmgr-ac`, so UPower keeps that supply online from its last read and reports
  `on-battery: no` after unplugging until the next resume rereads every supply; plugging in is right through
  `ADP1`. The battery has no `capacity` (UPower computes the percentage) and at 100 % on the charger reads
  `Not charging`, which UPower shows as `fully-charged`. On revision 2 (patches 0075 to 0077) the battery has
  `capacity` and UPower takes its percentage from it; with a USB-C charger unplugging and plugging in each sent a
  `change` uevent for `qcom-battmgr-usb`, and UPower's `on-battery` followed at once (2026-10-22).
- Video codec (Iris, 7.2.11 revision 7, 2026-10-29): `qcom-iris-decoder` and `qcom-iris-encoder` appear as V4L2
  devices, and GStreamer 1.28.7 registers `v4l2vp9dec`, `v4l2h264dec`, `v4l2h265dec`, `v4l2av1dec`, `v4l2h264enc`
  and `v4l2h265enc`. A 720p VP9 clip (profile 0) decoded in hardware gave the same 120 frames as libvpx's decoder,
  in 0.44 s. Clips made by the hardware H.264 and H.265 encoders are signalled with colorimetry `2:4:5:4` (the
  H.264 one also with level 1 at 720p), which is not in the colorimetry list GStreamer probes for the decoder, so
  `v4l2h264dec`/`v4l2h265dec` refuse them before decoding ("not-negotiated"). Relabelled `bt601` (`capssetter`),
  the H.264 clip decoded to 120 frames in 0.43 s, among them all 60 that Cisco's `openh264dec` put out for the same
  clip, and the H.265 clip to 120 distinct frames in 0.44 s. A VP9 clip without an explicit format comes out as
  12-bit 4:4:4 (profile 3).
- USB-C data on 7.2.11 revision 5 (2026-10-28, a USB 3 stick, SanDisk 3.2Gen1): plugged one way (`normal` in
  `/sys/class/typec/portN/orientation`) it ran at 5000 Mb/s on both ports; turned over (`reverse`) no USB device
  appeared within 10 s on either port, while the Type-C class saw the partner and its orientation. Windows finds
  the stick both ways. Port 0 is `a600000.usb` behind the PS8830 on `i2c@b8c000`, port 1 `a800000.usb` behind the
  one on `i2c@b9c000` (both at address 0x08). Revision 6 behaves the same. A kprobe trace
  on both revisions shows the reversed orientation reaching the PS8830 retimer and the QMP PHY, and the PHY
  rewriting its tables for it, so the switch lookup (patch 0083) is not the cause; the lane setup for the reversed
  plug is the lead (the trace's timestamps run 13–29 ms ahead of the journal's: order events within one source).
  Reversed on revision 7 (2026-10-29): the retimer's register 0x00 reads 0x23 (connected, reversed, USB 3) and the
  USB 3 root port sits in `Polling` (the device's receivers detected, link training failing; `U0` with the plug
  the usual way), the USB 2 port unconnected. A port power cycle (the port switches its power) ended in `Polling`
  again; with the retimer's orientation bit cleared the port fell back to `RxDetect`, with and without a power
  cycle. The retimer thus needs its reversed setting, and the link between the PHY, set to reversed by the same
  orientation, and the retimer does not train.
- TPM: none under Linux (the kernel arguments carry `systemd.tpm2_wait=0`). Windows reports Microsoft Pluton
  (`tpmtool getdeviceinformation`: manufacturer `MSFT`, vendor `Pluton.TPM.Q`) behind the ACPI `TPM2` table's start
  method 14 (OEM `QCOM`), which Linux's `include/acpi/actbl3.h` does not define (13 is Pluton's CRB) (2026-10-22).
  TrustZone runs no `qcom.tz.tpm`, the application the X1E QSEE TPM driver uses (a lookup through
  `qcom_scm_qseecom_app_get_id()`, which finds `qcom.tz.uefisecapp`, 2026-10-22).
- Live-only DSP blacklist: an ADSP restart resets USB-C while rooted on USB, so the live media boots with
  `modprobe.blacklist=qcom_q6v5_pas rd.driver.blacklist=qcom_q6v5_pas` (no audio or battery live). The installed
  system drops both via the kernel-install plugin and `sp11-first-boot.service`; the plugin also removes Anaconda's
  `/etc/modprobe.d/anaconda-denylist.conf`, made from the first argument, before the initramfs rebuild
  (`module_blacklist=` would avoid the file but spams `pr_err`).
- Windows dual-boot: `/etc/grub.d/29_sp11_windows` with `/usr/libexec/sp11/sp11-grub-modules`, which copies
  `chain.mod` and its dependency closure from `moddep.lst` into `/boot/grub2/arm64-efi` on every grub2-mkconfig and
  on an RPM trigger on `grub2-efi-aa64-modules`.

## Sleep

- The kernel sleeps in `deep` (`/sys/power/mem_sleep`: `s2idle [deep]`): the non-boot CPUs go offline, then PSCI
  SYSTEM_SUSPEND. CPU idle has only `WFI` and `cpu-sleep-0`: patch 0056 empties the Denali cluster domains'
  `domain-idle-states` for s2idle resume reliability.
- Wake-armed (`power/wakeup` enabled): the power key (`pmic@0:pon@1300:pwrkey`); `gpio-keys`, with the lid on TLMM
  GPIO 2 (`wakeup-event-action = EV_ACT_DEASSERTED`: opening wakes, closing does not) and the volume keys on PM8550
  GPIO 6 and 8; both USB controllers (`a600000.usb`, `a800000.usb`); the four tsens thermal sensors; the ADSP and
  CDSP remoteprocs. Not armed: `smp2p-adsp` and `smp2p-cdsp` (upstream default), the Surface Aggregator.
- Any ADSP message ends a deep sleep: IPCC's summary interrupt is `IRQF_NO_SUSPEND` and its child chip lacks
  `IRQCHIP_MASK_ON_SUSPEND`, `glink-smem` is `IRQF_NO_SUSPEND`, and PSCI's suspend has no `suspend_again`. Open
  sensor streams (`docs/sensors.md`, Known issues) and charger or battery notices wake the tablet this way.
- `cat /sys/power/pm_wakeup_irq` names the wake-armed interrupt of the last wake; after an ADSP wake it answers
  `No data available`.
- What sleeps (`/sys/kernel/debug/qcom_stats`, 7.2.11 revision 1, 2026-10-22): the CPU subsystem collapses once per
  deep sleep (`apss` counts the suspends), but over 5 hours with 2 hours suspended `aosd`, `cxsd` and `ddr` stayed
  at 0 and `ddr_stats` counted no low-power mode. The ADSP enters its sleep about 100 times a second, awake or
  suspended alike (101/s across the suspends). It offers `APPS_ADSP_PWR_LMTS_GLINK_PORT`, the channel on which
  Windows' PEP (`qcpep8380.sys`) announces Modern Standby so that the ADSP stops its power-limits timer; on a
  ThinkPad T14s that brought its wakes in sleep from 100 to 160 a second down to 2 or 3 (justririll/x1e-sleep).
- With that message sent (justririll's `qcom_adsp_pwr_lmts`, loaded by hand on 7.2.11 revision 2, 2026-10-23) the
  ADSP entered its sleep 0.24 times a second while suspended instead of 103 (10-minute sleeps, power-key wakes);
  one `state 1` before each sleep and one `state 0` after, no reply on the channel, the ADSP answered afterwards;
  going to sleep and waking took no longer, and sound, the battery percentage and rotation worked afterwards.
  `cxsd`, `ddr` and `aosd` still stayed at 0, so something else keeps the SoC out of its deepest states.
- The drain through a night in deep sleep (7.2.11 revision 3, support 3.7, sensors 1.15, the Performance profile,
  on battery, 2026-10-24 to 2026-10-27; `sp11-power-snapshot.sh` in the evening and the morning): 0.86 W in the
  normal boot (11 h), 0.85 W with the message above sent (9 h; the ADSP's entries while suspended about 0), 0.84 W
  in a boot with the OLED tree, without the modem's PCIe link (8 h), 0.83 W with the modem's radio in `low-power`
  (10 h; `docs/modem.md`). The battery reports its energy in steps of 1 % (0.52 Wh), so differences below about
  0.06 W over a night do not show: none of the four changes the drain. `aosd`, `cxsd` and `ddr` stayed at 0 every
  night; `apss` counted the one sleep.
- What keeps the memory awake (7.2.11 revision 3, 2026-10-27; `icc_set_bw` trace and interconnect and power-domain
  summaries around 10- to 20-minute sleeps): at suspend `ebi` kept the crypto engine's 394 MB/s (`qcrypto` votes at
  probe and never drops it), the CPU bandwidth monitors' 800 MB/s peak (`icc_bwmon`; tagged active-only, so RPMh
  leaves it out of the sleep set) and 1 kB/s from each PCIe controller. A PCIe controller takes its link down in a
  sleep only if every device below it, its root port included, is in D3hot (`dw_pcie_suspend_noirq()`). The qcom
  driver advertises the root ports' hot-plug again since Linux 7.1 (33a76fc3c3e6; pciehp drives them), and 7.2 keeps
  native hot-plug ports in D0 (`pci_bridge_d3_possible()`; 7.3 allows D3 for them on non-x86, d4c79b63d82d) unless
  the kernel boots with `pcie_port_pm=force`. The NVMe drive is shut down in every sleep, ASPM or not
  (`broken_l1ss_resume`).
- With `qcrypto` and `icc_bwmon` unloaded, Wi-Fi (`ath12k`), Bluetooth (`hci_uart`) and the modem's driver taken
  away and ASPM L1 off, the links stayed up and `ddr` stayed 0. In a boot with `pcie_port_pm=force` and the same
  removals the three root ports and the NVMe drive went to D3hot, no memory vote was left, and `ddr` counted 1083 of
  1153 s suspended (559 of 602 s also without the sound card and the rx, tx and wsa macros). The drive came back
  from both sleeps; the Wi-Fi controller (`1c08000.pci`, its driver unloaded) logged
  `Timeout waiting for L2 entry` in each. `cxsd` and `aosd` stayed 0: the one vote left at suspend was the Surface
  Aggregator UART's (`b88000.serial`: QUP0 core 25 MB/s, configuration 4 MB/s, CX performance state 64), as
  `qcom_geni_serial` keeps an open port's clocks and votes through a sleep on 7.2 (7.3 suspends it, d0cd9c8d0fd5).
  The ADSP entered its sleep 12 to 17 times a second over those intervals, against about 100 before.
- In normal use (2026-10-27; `pcie_port_pm=force`, only `qcrypto` and `icc_bwmon` unloaded, Wi-Fi, Bluetooth, the
  modem and sound loaded) the Wi-Fi and the modem went to D3hot with their drivers too, all three links went down,
  and `ddr` counted 650 of 694 s of a 10-minute sleep. Over 8 hours on battery after it (sleeps of 6 h 26 min and
  1 h 21 min, 15 minutes awake between) the battery gave 0.45 W, the awake time included, against 0.83 to 0.86 W
  in the four nights above; `ddr` counted 26388 of 28052 s suspended, the ADSP entered its sleep 10 times a second
  while suspended, `cxsd` and `aosd` stayed 0. At suspend only the two UARTs still voted: the Surface Aggregator's
  and Bluetooth's (`a98000.serial`), 25 MB/s on their QUP cores each. The tablet woke once unintended (18:21; no
  power-key or lid event logged, the wake interrupt not recorded; a bump on the cover is the likely cause, as the
  morning's wake by closing and opening the cover came from the lid's interrupt) and slept again after GNOME's
  15 idle minutes.
  Wi-Fi, Bluetooth and sound worked after the wakes. The modem does not resume from a sleep with its link down:
  `mhi-pci-generic` logs `Resuming from non M3 state (RESET)` and `failed to resume device: -22`, then recovers it
  (its WWAN ports return about 1.5 s later and ModemManager probes it again).
- 7.2.11 revision 4 (2026-10-27, patches 0079 to 0081, nothing unloaded): the links went down without the boot
  argument and `ddr` counted 591 of 630 s of a 10-minute sleep with the crypto engine (`runtime_status`
  `suspended` when idle) and the bandwidth monitors loaded; GPS came back after the modem's restart; `cxsd` and
  `aosd` stayed 0. With only the modem's link kept up (its `d3cold_allowed` 0) the modem resumed without a reset,
  but `ddr` stayed 0 and the ADSP entered its sleep 102 times a second again. The night: a wake at 04:13 without a
  wake interrupt (an ADSP message), then a deep suspend 26 s later that `mhi-pci-generic` refused
  (`failed to suspend device`; the MHI core refuses while wake votes or packets are pending, as when ModemManager
  probes the restarted modem); systemd then suspended to `s2idle`, which lasted 3 h 23 min (entering took 20 s).
  The night averaged 1.40 W; its deep part (5 h 23 min) counted `ddr` 18266 of 19366 s. Wakes by the cover log
  `gpio_keys` (TLMM GPIO 2), by the power key `pmic_pwrkey`, once `pm_debug_messages` is on.
- With the modem's link kept up (revision 4, `icc_set_bw` trace up to the deepest point) the one vote left in the
  RPMh sleep set was PCIe 5's 1 kB/s on its memory path (`1c00000.pci`, `pcie-mem`): `qcom_pcie_suspend_noirq()`
  sets it for a link that stays up, to keep the data path working (ad9b9b6e36c9, 2023); the CPU-to-PCIe path is
  active-only and stays enabled for `deep` (S2RAM). Tagging the memory path active-only before that vote and back
  on resume (`icc_set_tag()`) compiled clean but was not tested: revision 5 powers the modem down instead.
- 7.2.11 revision 5 (2026-10-28, patch 0082): a sleep started within 15 s of a wake found the modem busy
  (`failed to suspend device: -16`), and `mhi-pci-generic` powered it down (`device busy, powering it down for
  system suspend`); every sleep stayed deep, and GPS answered afterwards. 8 hours on battery: 0.33 W with 47 s
  awake, `ddr` 27335 of 28988 s suspended, the ADSP 10 sleep entries a second; `cxsd` and `aosd` 0. The PM core
  logged `parent mhi0 should not be sleeping` once for each of the modem's channel devices, re-created by its
  restart while the next suspend was being prepared.
- The wake without a wake interrupt is a notice from the ADSP's battery manager: the GLINK trace across that night
  (`qcom_glink:qcom_glink_cmd_tx_data`, a kprobe on `pmic_glink_rpmsg_callback`) shows the first message after
  that sleep on `PMIC_RTR_ADSP_APPS`: owner 32778, type 2, opcode 7, notification 0x81 (`NOTIF_BAT_INFO`), followed
  by the driver's battery-info request; it was the only notice in 8 hours. Such wakes came 5 to 6.5 hours into
  each of the three low-drain nights, none in the four nights at 0.85 W. With the cover closed GNOME suspends again
  about 26 s later; with 0082 the modem's restart no longer turns that into `s2idle`.
- Open: `cxsd` and `aosd` stayed 0 in every configuration above, so CX never collapses. Linux runs at EL1 here,
  under the firmware's hypervisor (Gunyah). Another Surface Pro 11 (X1E80100, OLED), booted at EL2 with slbounce,
  reaches `cxsd`, `aosd` and DDR low-power modes for 99.9 % of a 73-minute s2idle suspend at about 0.26 W, against
  1.06 W on the same unit at EL1 (ramonjesusmiranda-debug/sp11-el2, October 2026). At EL2 the firmware takes the
  wake time from the EL1 timers, which justririll/x1e-sleep's `x1e_el1tmr` module fills in. EL1 may be the limit;
  not tried on this unit.
- PowerDevil 6.7 sleeps again 10 s after a wake if the lid is closed, no external monitor counts and the lid action
  is Sleep (`checkWakeup`); after a wake by network, telephony or timer, after 30 s idle instead.
- The power key's driver (`pm8941-pwrkey`) reports the press that woke the system, about 0.2 s before
  `System returned from sleep`, and synthesizes a press for a release without one; ACPI's button driver on x86
  suppresses that press. Under KDE the waking press counts as a power-button press: each of 10 power-key wakes on
  2026-10-08 was followed by a new sleep 1 to 6 s later. Opening the cover wakes without that.
- PowerDevil 6.7 runs its `PowerButtonAction` (`powerdevilrc`, `[<profile>][SuspendAndShutdown]`: 0 nothing,
  1 sleep, 16 logout screen (the default), 32 lock screen, 64 screen off, 128 screen toggle) for that press. Lock
  screen is the setting used (`docs/guide/troubleshooting.md`): the session is locked after a sleep already, and
  screen off or toggle would blank the screen just woken. With it the tablet stayed awake after a power-key wake
  (`docs/verified.md`). With nothing, `HandleButtonEvents::loadAction()` returns
  false and the core does not activate the action. In tablet mode PowerDevil unbinds the power button's shortcut.
- PowerDevil holds a logind `block` inhibitor on the power key, the sleep keys and the lid whatever the setting, so
  logind's own key handling never runs. The kernel-side fix is planned in `docs/kernel-patches.md`.
- BlueZ logs `Controller resume with wake event 0x1` after every resume; it is not a wake cause (the Bluetooth UART
  is not wake-armed).

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
