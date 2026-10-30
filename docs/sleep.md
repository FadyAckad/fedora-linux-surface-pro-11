# Sleep
Deep sleep on the tested unit: the sleep state and the wake sources, what kept the memory awake until 7.2.11
revision 4, the drain measured, the wakes that name no interrupt, and the power key under KDE Plasma. The modem's
own behaviour across a sleep is in `docs/modem.md`, the sensor streams' in `docs/sensors.md` (Known issues).

## Sleep state and wake sources

- The kernel sleeps in `deep` (`/sys/power/mem_sleep`: `s2idle [deep]`): the non-boot CPUs go offline, then PSCI
  SYSTEM_SUSPEND. CPU idle has only `WFI` and `cpu-sleep-0`: patch 0056 empties the Denali cluster domains'
  `domain-idle-states` for s2idle resume reliability.
- Wake-armed (`power/wakeup` enabled): the power key (`pmic@0:pon@1300:pwrkey`); `gpio-keys`, with the lid on
  TLMM GPIO 2 (`wakeup-event-action = EV_ACT_DEASSERTED`: opening wakes, closing does not) and the volume keys on
  PM8550 GPIO 6 and 8; both USB controllers (`a600000.usb`, `a800000.usb`); the four tsens thermal sensors; the
  ADSP and CDSP remoteprocs. Not armed: `smp2p-adsp` and `smp2p-cdsp` (upstream default), the Surface Aggregator.
- Any ADSP message ends a deep sleep: IPCC's summary interrupt is `IRQF_NO_SUSPEND` and its child chip lacks
  `IRQCHIP_MASK_ON_SUSPEND`, `glink-smem` is `IRQF_NO_SUSPEND`, and PSCI's suspend has no `suspend_again`. Open
  sensor streams and the battery manager's notices wake the tablet this way.
- `cat /sys/power/pm_wakeup_irq` names the wake-armed interrupt of the last wake; after an ADSP wake it answers
  `No data available`. With `pm_debug_messages` on, a wake by the cover logs `gpio_keys`, one by the power key
  `pmic_pwrkey`.
- BlueZ logs `Controller resume with wake event 0x1` after every resume; it is not a wake cause (the Bluetooth
  UART is not wake-armed).

## What sleeps

`/sys/kernel/debug/qcom_stats` counts the SoC's low-power modes: `apss` the CPU subsystem's suspends, `aosd`,
`cxsd` and `ddr` the always-on subsystem's, CX's and the memory's; `ddr_stats` the memory's time in them.

- Up to 7.2.11 revision 3 only `apss` counted: `aosd`, `cxsd` and `ddr` stayed at 0 across every suspend, and a
  night in deep sleep drew 0.83 to 0.86 W (four nights, 2026-10-24 to 27, the Performance profile, on battery;
  `sp11-power-snapshot.sh` in the evening and the morning). The battery reports its energy in steps of 1 %
  (0.52 Wh), so differences below about 0.06 W over a night do not show.
- What kept the memory awake (revision 3, 2026-10-27, `icc_set_bw` trace and the interconnect and power-domain
  summaries): at suspend `ebi` still carried the crypto engine's 394 MB/s (`qcrypto` votes at probe and never
  drops it), the CPU bandwidth monitors' 800 MB/s peak (`icc_bwmon`; tagged active-only, so RPMh leaves it out of
  the sleep set) and 1 kB/s from each PCIe controller. A PCIe controller takes its link down in a sleep only if
  every device below it, the root port included, is in D3hot (`dw_pcie_suspend_noirq()`), and 7.2 keeps native
  hot-plug root ports in D0 (`pci_bridge_d3_possible()`). With the links down, the last votes were the GENI
  UARTs' (the Surface Aggregator's `b88000.serial` and Bluetooth's `a98000.serial`: QUP core 25 MB/s, CX
  performance state 64), which `qcom_geni_serial` on 7.2 keeps through a sleep. The NVMe drive is shut down in
  every sleep (`broken_l1ss_resume`).
- 7.2.11 revision 4 (patches 0079 to 0081, mainline 7.3: D3 for native hot-plug root ports on non-x86, GENI
  serial force-suspended in system sleep, the crypto engine's vote only while busy): `ddr` 591 of 630 s in a
  10-minute sleep. The modem loses its link and, with it, its power (`vreg_wwan` is PCIe 5's slot supply) and
  comes back through the MHI recovery on resume (`docs/modem.md`, Across a sleep). With the modem's link kept up
  (`d3cold_allowed` 0) `ddr` stays 0: `qcom_pcie_suspend_noirq()` votes 1 kB/s on the memory path for a link that
  stays up (ad9b9b6e36c9); tagging that vote active-only (`icc_set_tag()`) compiled but was not tested.
- Revision 4's night: a wake by an ADSP notice, then a suspend 26 s later that `mhi-pci-generic` refused
  (`failed to suspend device: -16`; the MHI core refuses while ModemManager probes the restarted modem), so systemd
  fell back to `s2idle` for 3 h 23 min: 1.40 W. Revision 5 (patch 0082) powers a busy modem down for the suspend
  instead (`device busy, powering it down for system suspend`); every sleep stays deep and GPS answers afterwards.
- Revision 5, 8 hours on battery: 0.33 W with 47 s awake, `ddr` 27335 of 28988 s suspended, the ADSP 10 sleep
  entries a second (about 100 before revision 4). The PM core logs `parent mhi0 should not be sleeping` once per
  channel device the modem's restart re-creates while the next suspend is prepared; harmless.
- `cxsd` and `aosd` stayed 0 in every configuration: CX never collapses. Linux runs at EL1 under the firmware's
  hypervisor (Gunyah). Another Surface Pro 11 (X1E80100, OLED), booted at EL2 with slbounce, reaches `cxsd`,
  `aosd` and the DDR low-power modes for 99.9 % of a 73-minute s2idle suspend at about 0.26 W, against 1.06 W on
  the same unit at EL1 (ramonjesusmiranda-debug/sp11-el2, October 2026; at EL2 the firmware takes the wake time
  from the EL1 timers, which justririll/x1e-sleep's `x1e_el1tmr` fills in). EL1 may be the limit; not tried here.
- The ADSP's power-limits channel: the ADSP enters its sleep about 100 times a second, awake or suspended, and
  offers `APPS_ADSP_PWR_LMTS_GLINK_PORT`, on which Windows' PEP (`qcpep8380.sys`) announces Modern Standby so that
  the ADSP stops its power-limits timer. With that message sent (justririll's `qcom_adsp_pwr_lmts`, loaded by hand
  on revision 2) the entries while suspended fell from 103 to 0.24 a second, but the night's drain stayed at
  0.85 W and `cxsd` and `ddr` at 0. Not carried.

## Wakes without a wake interrupt

- A wake that names no interrupt is a notice from the ADSP's battery manager: a GLINK trace across a night
  (`qcom_glink:qcom_glink_cmd_tx_data`, a kprobe on `pmic_glink_rpmsg_callback`) shows one message on
  `PMIC_RTR_ADSP_APPS` (owner 32778, type 2, opcode 7, notification 0x81, `NOTIF_BAT_INFO`), followed by the
  driver's battery-info request. One such wake came 5 to 6.5 hours into each low-drain night, none in the 0.85 W
  nights. With the cover closed GNOME suspends again about 26 s later, PowerDevil 10 s later.
- Plugging the charger in while the tablet sleeps wakes it the same way, sometimes several times in the first
  minutes. Left as is; a fix needs a kernel change.

## The power key under KDE Plasma

- `pm8941-pwrkey` reports the press that woke the system about 0.2 s before `System returned from sleep`, and
  synthesizes a press for a release without one; ACPI's button driver on x86 suppresses that press. PowerDevil
  takes it as an ordinary press: with the button set to Sleep, each of 10 power-key wakes was followed by a new
  sleep 1 to 6 s later. Opening the cover wakes without that. The kernel-side fix is planned in
  `docs/kernel-patches.md`.
- PowerDevil 6.7's `PowerButtonAction` (`powerdevilrc`, `[<profile>][SuspendAndShutdown]`): 0 nothing, 1 sleep,
  16 logout screen (the default), 32 lock screen, 64 screen off, 128 screen toggle. Lock screen is the setting
  used (`docs/guide/troubleshooting.md`): the session is locked after a sleep already, and with it the tablet
  stayed awake after a power-key wake. With 0, `HandleButtonEvents::loadAction()` returns false and the action is
  not activated at all. In tablet mode PowerDevil unbinds the power button's shortcut.
- PowerDevil holds a logind `block` inhibitor on the power key, the sleep keys and the lid whatever the setting,
  so logind's own key handling never runs.
- PowerDevil sleeps again 10 s after a wake if the lid is closed, no external monitor counts and the lid action is
  Sleep (`checkWakeup`); after a wake by network, telephony or timer, after 30 s idle instead.

## History

- 2026-10-22: `aosd`, `cxsd` and `ddr` found at 0 across every suspend (7.2.11 revision 1).
- 2026-10-23: the ADSP's power-limits message tested on revision 2: fewer ADSP sleep entries, the same drain.
- 2026-10-24 to 27: four nights at 0.83 to 0.86 W; the modem's link and radio state change nothing.
- 2026-10-27: the memory's votes traced to the crypto engine, the bandwidth monitors, the PCIe links and the
  UARTs; revision 4 built from the mainline fixes.
- 2026-10-28: revision 4's night at 1.40 W after the `s2idle` fallback; revision 5 at 0.33 W over 8 hours.
