# Sleep
Deep sleep on the tested unit: the sleep state and the wake sources, what sleeps and the drain measured, the wakes
that name no interrupt, the power key under KDE Plasma, and what a wake costs until the panel is lit. The modem's
own behaviour across a sleep is in `docs/modem.md`, the sensor streams' in `docs/sensors.md` (Known issues).

## Sleep state and wake sources

- The kernel sleeps in `deep` (`/sys/power/mem_sleep`: `s2idle [deep]`): the non-boot CPUs go offline, then PSCI
  SYSTEM_SUSPEND. CPU idle has only `WFI` and `cpu-sleep-0`: patch 0049 empties the Denali cluster domains'
  `domain-idle-states` for s2idle resume reliability.
- Wake-armed (`power/wakeup` enabled): the power key (`pmic@0:pon@1300:pwrkey`); `gpio-keys`, with the lid on
  TLMM GPIO 2 (`wakeup-event-action = EV_ACT_DEASSERTED`: opening wakes, closing does not) and the volume keys on
  PM8550 GPIO 6 and 8; both USB controllers (`a600000.usb`, `a800000.usb`); the four tsens thermal sensors; the
  ADSP and CDSP remoteprocs. Not armed: `smp2p-adsp` and `smp2p-cdsp` (upstream default), the Surface Aggregator.
- The TLMM's GPIO wake interrupts stay on its summary interrupt, not on the PDC (patch 0087): 7.3 routes them
  through the PDC again (it reverted 7.2's X1E80100 bypass with its PDC rework), and on 7.3.3 revision 1 a suspend
  started with the lid open ended after 2 s, woken by the lid's interrupt (2026-11-08); with the bypass it held
  (2026-11-09). Since 7.3.3 every suspend logs `qcom-pcie 1c08000.pcie: Timeout waiting for L2 entry! LTSSM: 0x11`
  for the Wi-Fi link; the suspend goes on and Wi-Fi is back after the wake.
- Opening the cover wakes a deep sleep: on 7.3.5 revision 1 a sleep entered by closing the cover ended 24 s later on
  opening it, `pm_wakeup_irq` naming `gpio_keys` and the journal no key press (2026-11-19). On 7.3.3 revisions 2 and
  3 it did not, where 7.2 with the same bypass did, and the power key ended their deep sleeps; a sleep that had
  fallen back to `s2idle` ended on opening the cover (2026-11-12). Since support 3.11 the cover wakes a deep sleep
  again (seen from 7.3.3 revision 5 on).
- What brought the wake back is not shown. The kernel's PDC and pin-controller code is the same from 7.3.3 revision
  2 to 7.3.5 revision 1, and `msm_gpio_irq_set_wake()` arms the summary interrupt for the cover's line, a wake its
  comment limits to a powered TLMM. Support 3.11 holds the LPASS pin controller awake and with it two LPASS clock
  votes through a sleep, as the 7.2 kernels did (`docs/hardware.md`, Audio); a sleep with that rule switched off has
  not been tried.
- Any ADSP message ends a deep sleep: IPCC's summary interrupt is `IRQF_NO_SUSPEND` and its child chip lacks
  `IRQCHIP_MASK_ON_SUSPEND`, `glink-smem` is `IRQF_NO_SUSPEND`, and PSCI's suspend has no `suspend_again`. Open
  sensor streams and the battery manager's notices wake the tablet this way.
- `cat /sys/power/pm_wakeup_irq` names the wake-armed interrupt of the last wake; after an ADSP wake it answers
  `No data available`. With `pm_debug_messages` on, a wake by the cover logs `gpio_keys`, one by the power key
  `pmic_pwrkey`.
- Without `pm_debug_messages` the journal still tells a key wake: logind logs `Power key pressed short.` at
  the resume. A cover moved during the sleep is reported at the next resume (`Lid closed.` or `Lid opened.`),
  whatever woke the tablet.
- BlueZ logs `Controller resume with wake event 0x1` after every resume; it is not a wake cause (the Bluetooth
  UART is not wake-armed). The Surface Aggregator's `rtl: dropping unexpected command message` and the
  keyboard's Bluetooth reconnect follow every resume as well.

## What sleeps

`/sys/kernel/debug/qcom_stats` counts the SoC's low-power modes: `apss` the CPU subsystem's suspends, `aosd`,
`cxsd` and `ddr` the always-on subsystem's, CX's and the memory's; `ddr_stats` the memory's time in them.

- Until 7.2.11 revision 4 only `apss` counted: `aosd`, `cxsd` and `ddr` stayed at 0 across every suspend, and a
  night in deep sleep drew 0.83 to 0.86 W (four nights, 2026-10-24 to 27, the Performance profile, on battery;
  `sp11-power-snapshot.sh` in the evening and the morning). The battery reports its energy in steps of 1 % (0.52
  Wh), so differences below about 0.06 W over a night do not show.
- What kept the memory awake (7.2.11 revision 3, 2026-10-27, an `icc_set_bw` trace and the interconnect and
  power-domain summaries): at suspend `ebi` still carried the crypto engine's 394 MB/s (`qcrypto` voted at probe and
  never dropped it) and 1 kB/s from each PCIe controller. A PCIe controller takes its link down in a sleep only if
  every device below it, the root port included, is in D3hot (`dw_pcie_suspend_noirq()`), and 7.2 kept native
  hot-plug root ports in D0 (`pci_bridge_d3_possible()`). With the links down, the last votes were the GENI UARTs'
  (the Surface Aggregator's `b88000.serial` and Bluetooth's `a98000.serial`: QUP core 25 MB/s, CX performance state
  64). The CPU bandwidth monitors' 800 MB/s peak (`icc_bwmon`) is active-only, so RPMh leaves it out of the sleep
  set. The NVMe drive is shut down in every sleep (`broken_l1ss_resume`).
- 7.2.11 revision 4 carried the three mainline fixes, in 7.3 since (D3 for native hot-plug root ports on non-x86,
  GENI serial force-suspended in system sleep, the crypto engine's vote only while busy): `ddr` 591 of 630 s in a
  10-minute sleep. With a PCIe link kept up (`d3cold_allowed` 0) `ddr` stays 0: `qcom_pcie_suspend_noirq()` votes 1
  kB/s on the memory path for a link that stays up (ad9b9b6e36c9); tagging that vote active-only (`icc_set_tag()`)
  compiled but was not tested.
- A suspend that `mhi-pci-generic` refuses (`failed to suspend device: -16`; the MHI core refuses while ModemManager
  probes a restarted modem) makes systemd fall back to `s2idle`: revision 4's night, woken by an ADSP notice and
  suspended again 26 s later, drew 1.40 W (2026-10-28). Patch 0071 powers a busy modem down for the suspend instead
  (`device busy, powering it down for system suspend`).
- The Surface Aggregator's hub can refuse a suspend as well: on 2026-11-12 (7.3.3 revision 3) a suspend started
  20 s after a wake waited 9 s for the EC's answer to its display-off notice (`ssam_serial_hub_pm_prepare`
  returns -110), and systemd fell back to `s2idle` for that sleep. The nine other suspends of the day, up to 8
  hours long, were deep; seen this once.

The nights on battery, with the modem powered from 7.2.11 revision 9 on:

| Kernel | Date | Asleep | Draw | `ddr` | Notes |
|---|---|---|---|---|---|
| 7.2.11 revision 5 | 2026-10-28 | 8 h | 0.33 W | 27335 of 28988 s | the modem off in the sleep, 47 s awake |
| 7.2.11 revision 9 | 2026-10-31 | 8 h | 0.32 W | 27148 of 28885 s | ModemManager kept the modem registered |
| 7.2.14 revision 2 | 2026-11-03 | 8 h | 0.32 W | 27253 of 28957 s | the PCIe controllers suspended in parallel, mobile data on |
| 7.3.3 revision 2 | 2026-11-09 | 8 h | 0.25 W | 27112 of 28883 s | the crypto engine's node disabled |
| 7.3.3 revision 3 | 2026-11-12 | 8 h | 0.31 W | 27167 of 28951 s | HDR on |
| 7.3.3 revision 4 | 2026-11-13 | 8.9 h | 0.28 W | 29565 of 31978 s | HDR on; a wake 35 minutes in (Wakes without a wake interrupt) |
| 7.3.3 revision 4, support 3.11 | 2026-11-16 | 11.8 h | 0.26 W | 39777 of 42336 s | two LPASS clock votes held (`docs/hardware.md`, Audio) |

- The ADSP enters its sleep about 10 times a second while the tablet is suspended (about 100 before 7.2.11 revision
  4). In the nights of 7.3.3 revisions 2 to 4 the memory slept 93.9, 93.8 and 92.5 % of the time and entered its
  sleep 10, 10 and 18 times a second (`Count` in `qcom_stats/ddr`). Neither that nor the differences in draw are
  explained.
- `cxsd` and `aosd` stayed 0 in every configuration: CX never collapses. Linux runs at EL1 under the firmware's
  hypervisor (Gunyah). Another Surface Pro 11 (X1E80100, OLED), booted at EL2 with slbounce, reaches `cxsd`,
  `aosd` and the DDR low-power modes for 99.9 % of a 73-minute s2idle suspend at about 0.26 W, against 1.06 W on
  the same unit at EL1 (ramonjesusmiranda-debug/sp11-el2, October 2026; at EL2 the firmware takes the wake time
  from the EL1 timers, which justririll/x1e-sleep's `x1e_el1tmr` fills in). EL1 may be the limit; not tried here.
- The ADSP's power-limits channel: the ADSP enters its sleep about 100 times a second, awake or suspended, and
  offers `APPS_ADSP_PWR_LMTS_GLINK_PORT`, on which Windows' PEP (`qcpep8380.sys`) announces Modern Standby so that
  the ADSP stops its power-limits timer. With that message sent (justririll's `qcom_adsp_pwr_lmts`, loaded by hand
  on 7.2.11 revision 2) the entries while suspended fell from 103 to 0.24 a second, but the night's drain stayed at
  0.85 W and `cxsd` and `ddr` at 0. Not carried.

## Wakes without a wake interrupt

- A wake that names no interrupt is a notice from the ADSP's battery manager: a GLINK trace across a night
  (`qcom_glink:qcom_glink_cmd_tx_data`, a kprobe on `pmic_glink_rpmsg_callback`) shows one message on
  `PMIC_RTR_ADSP_APPS` (owner 32778, type 2, opcode 7, notification 0x81, `NOTIF_BAT_INFO`), followed by the
  driver's battery-info request. One such wake came 5 to 6.5 hours into each low-drain night, none in the 0.85 W
  nights. With the cover closed GNOME suspends again about 26 s later, PowerDevil 10 s later.
- On 7.3.3 the nights of revisions 2 and 3 had no such wake; revision 4's had one after 35 minutes (2026-11-13),
  with no key press in the journal, the cover closed and armed for its opening only, the sensor streams paused; the
  message was not traced.
- Plugging the charger in while the tablet sleeps wakes it the same way, sometimes several times in the first
  minutes: three wakes in 25 minutes while it charged at 38 W, between 60 and 80 % of charge (2026-11-02). Left as
  is; a fix needs a kernel change.

## The power key under KDE Plasma

- `pm8941-pwrkey` reports the press that woke the system about 0.2 s before `System returned from sleep`, and
  synthesizes a press for a release without one. PowerDevil takes it as an ordinary press: with the button set to
  Sleep, each of 10 power-key wakes was followed by a new sleep 1 to 6 s later. Opening the cover wakes without
  that.
- The driver (`drivers/input/misc/pm8941-pwrkey.c`, bound to `qcom,pmk8350-pwrkey`, `pon_pwrkey` under
  `pmk8550_pon: pon@1300` in `hamoa-pmics.dtsi`; a module in Fedora's configuration): a threaded handler
  (`IRQF_ONESHOT`) reads `PON_RT_STS` and reports press and release; `.suspend` and `.resume` only arm and disarm
  the interrupt as a wake source. The IRQ thread is not frozen and can run before `.resume`. For modules
  `pm_wakeup_dev_event()` is exported, `pm_wakeup_irq()` is not.
- ACPI's button driver on x86 (`drivers/acpi/button.c`) suppresses that press: it sets `button->suspended` in
  `.suspend`, clears it in `.resume`, and meanwhile reports only `acpi_pm_wakeup_event()`, no key.
- PowerDevil 6.7's `PowerButtonAction` (`powerdevilrc`, `[<profile>][SuspendAndShutdown]`): 0 nothing, 1 sleep,
  16 logout screen (the default), 32 lock screen, 64 screen off, 128 screen toggle. Lock screen is the setting
  used (`docs/guide/troubleshooting.md`): the session is locked after a sleep already, and with it the tablet
  stayed awake after a power-key wake. With 0, `HandleButtonEvents::loadAction()` returns false and the action is
  not activated at all. In tablet mode PowerDevil unbinds the power button's shortcut.
- PowerDevil holds a logind `block` inhibitor on the power key, the sleep keys and the lid whatever the setting,
  so logind's own key handling never runs.
- PowerDevil sleeps again 10 s after a wake if the lid is closed, no external monitor counts and the lid action is
  Sleep (`checkWakeup`); after a wake by network, telephony or timer, after 30 s idle instead.

## Wake

What a wake costs from the power key to the lit panel, measured on 2026-11-02 with 7.2.14 revisions 1 and 2 and
`sp11-iptsd` 3.1.0-3 and 3.1.0-4 under GNOME 51 on Wayland: the kernel's own timestamps from the journal's JSON
form, the panel from the DRM connector's `dpms` read every 20 ms. The kernel's timestamps stop while the SoC sleeps,
so a kernel figure never includes the firmware's part; journald's wall clock does.

| Part | Revision 2 and 3.1.0-4 (thirteen wakes) | Revision 1 and 3.1.0-3 (four cycles) |
|---|---|---|
| firmware: the key press until the kernel runs again | not measured | not measured |
| the eleven secondary CPUs back | 0.03 s | 0.03 s |
| noirq phase: the three PCIe links | 0.36 s, side by side (`link up` at +0.35, +0.35, +0.39) | 1.02 s, one after the other |
| early phase: the Wi-Fi firmware | 0.52 s | 0.52 s |
| resume phase | 0.21 to 0.28 s (the Wi-Fi's restart wait) | 0.84 s (the touch callback) |
| the thaw to `PM: suspend exit` | 0.16 to 0.22 s | 0.16 to 0.19 s |
| kernel, first line to `PM: suspend exit` | 1.31 to 1.42 s | 2.54 to 2.58 s |
| systemd-sleep's post hooks | 0.015 s | 1.15 to 1.45 s |
| DRM connector on, after the suspend exit | 0.05 s | 1.27 to 1.33 s |
| `touch controller initialized`, after the suspend exit | 0.56 to 0.70 s | 0.82 to 0.85 s |
| the hidraw node, after the suspend exit | 0.91 to 1.04 s | 1.17 to 1.19 s |

- The PCIe links: each controller's link resume costs 0.31 to 0.36 s by construction (`qcom_pcie_perst_deassert()`'s
  100 ms, `dw_pcie_wait_for_link()`'s 90 ms polling steps, the 100 ms post-training wait). Platform devices lack
  `power.async_suspend` (`is_async()` in `drivers/base/power/main.c`), and without `CONFIG_PM_ADVANCED_DEBUG` (off
  in Fedora's configuration) there is no `power/async` attribute to switch at runtime. Patch 0083 calls
  `device_enable_async_suspend()` in `qcom_pcie_probe()`: the three controllers suspend and resume side by side,
  each still after its parent and suppliers and before its root port and endpoints, which were async already. The
  suspend side runs the same code to the same end state (the links down, the votes released).
- The Wi-Fi: `ath12k_pci_pm_resume_early()` waits in `mhi_sync_power_up()` for the firmware that every sleep powers
  down (upstream's design: QRTR's resume right after it needs MHI's mission mode), and `ath12k_core_resume()` waits
  0.2 to 0.3 s for its restart: 0.73 s of the kernel's remaining 1.35 s.
- The touch controller: `g6ts_resume()` (patch 0043) ran the 500 and 300 ms delays of `g6ts_power_on()` inside the
  PM callback and scheduled the recovery work, which 100 ms later powered the controller off and on again on its
  hardware path, so the callback's power-on was thrown away. Patch 0082 leaves the power-on to the recovery work,
  once.
- User space: logind sends `PrepareForSleep(false)`, on which mutter and gsd-power light the panel, only when
  systemd-sleep exits. ooaklee's pen hook (`sp11-iptsd-restart`, up to 3.1.0-3) polled for the hidraw node in its
  `post` phase, restarted `sp11-iptsd@<node>.service` and waited until the new process owned the node, which comes
  back about a second after the suspend exit (the suspend destroys the HID device, the resume rebuilds it in the
  driver's recovery work). The restart was redundant: `70-sp11-iptsd.rules` starts the unit on the hidraw add event
  (the journal showed that instance connected before the hook's restart killed it), and `BindsTo=%i.device` stops it
  when the node goes. `payload/iptsd/sp11-iptsd-sleep` only stops the running instances in its `pre` phase (0.17 s
  on the suspend side). The GNSS hook, `sp11-sensors-resume.service` and ModemManager's state sync are off the path.
- From the kernel's first line to the lit connector about 1.4 s (3.9 s before); the touch controller is initialized
  2.0 s after the kernel's first line (3.4 s before). The firmware's part is unmeasured: `qcom_stats`'s `apss` exit
  stamp (the system counter) against the kernel's first message would give it, but a `tar` of the debugfs counters
  stores empty files (tar trusts their zero size); `cat` each file, as `sp11-power-snapshot.sh` does.
- The memory's low-power share was unchanged by the parallel suspend: 617 of 675 s suspended on revision 2 (91 %),
  677 of 752 s on revision 1 the same evening, both on battery with 30 s cycles included; revision 2's night drew
  0.32 W (What sleeps). With the charger connected and the battery charging at 38 W the memory counted only 69 of
  682 s.
- Windows wakes at once because it never leaves S0 (Modern Standby): the devices stay in their runtime D3 states and
  the panel is lit before any device is touched. In `deep` every driver's resume callback runs before user space,
  and the PCIe links, the Wi-Fi firmware and the touch controller are rebuilt from power-off; `s2idle` would remove
  only the firmware's part, at 1.40 W a night (What sleeps).

## History

- 2026-10-22: `aosd`, `cxsd` and `ddr` found at 0 across every suspend (7.2.11 revision 1).
- 2026-10-23: the ADSP's power-limits message tested on revision 2: fewer ADSP sleep entries, the same drain.
- 2026-10-24 to 27: four nights at 0.83 to 0.86 W; the modem's link and radio state change nothing.
- 2026-10-27: the memory's votes traced to the crypto engine, the PCIe links and the UARTs; revision 4 built from
  the mainline fixes.
- 2026-10-28: revision 4's night at 1.40 W after the `s2idle` fallback; revision 5 at 0.33 W over 8 hours.
- 2026-11-02: the wake measured; 7.2.14 revision 2 and `sp11-iptsd` 3.1.0-4 cut the kernel's resume from 2.6 to 1.4
  s and light the panel 0.05 s after it.
- 2026-11-03: revision 2's night at 0.32 W over 8 hours, no wake in the night.
- 2026-11-08/09: 7.3.3 revision 1 woke a suspend started with the cover open after 2 s; revision 2 keeps the GPIO
  wakes off the PDC, and opening the cover no longer woke the tablet.
- 2026-11-12: 7.3.3 revision 3's night at 0.31 W with HDR on; one suspend of ten refused by the Surface Aggregator's
  hub.
- 2026-11-13: 7.3.3 revision 4's 8.9 hours at 0.28 W with HDR on, one wake 35 minutes in.
- 2026-11-16: 11.8 hours at 0.26 W with support 3.11 holding the two LPASS clock votes.
- 2026-11-19: 7.3.5 revision 1: a deep sleep entered by closing the cover ended on opening it.
