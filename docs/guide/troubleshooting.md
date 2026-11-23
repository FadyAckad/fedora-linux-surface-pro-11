# Troubleshooting

The diagnostic tools, the known limitations, what earlier releases of the RPMs fixed, and the power button setting
under KDE Plasma. The device results by date are in [`docs/verified.md`](../verified.md).

## Diagnostics

`sudo /usr/libexec/sp11/sp11-diag` writes `sp11-diag-<date>-<time>.txt` to the current directory, or to the path
given as its argument, and changes nothing. It records the kernel, security, input, Bluetooth, audio, sensors and
camera state, a section that diffs cleanly between two kernels, the power-domain and interconnect providers still
holding their boot-time votes, and the boot's kernel warnings and journal errors. The file names the Bluetooth
controller and every device BlueZ knows by address.

`sudo /usr/libexec/sp11/sp11-sensors-check`, run from a terminal in the desktop, covers the sensors stack and
tablet mode ([`docs/guide/sensors.md`](sensors.md)). Both list SELinux denials since support RPM 3.7 and
`sp11-sensors` 1.14; earlier versions searched only the kernel's messages and showed none.

## Known limitations

- Once in a boot, a few minutes after it, the compute DSP's firmware can report a `sleep_stats` fatal error.
  remoteproc restarts that DSP by itself, and nothing on Linux uses it.
- From kernel 7.3.5 revision 2 the start takes about 3 s longer: the TPM's first self test keeps the firmware busy,
  and the start waits for it to read the EFI variables ([`docs/hardware.md`](../hardware.md), TPM).
- Once, after a sleep, the TPM refused systemd's measurements until the next start (2026-11-23): the measurement
  of a login failed (`systemctl --failed` lists `systemd-pcrlogin@<uid>.service`), and a restart cleared it
  ([`docs/hardware.md`](../hardware.md), TPM).
- HDR switches itself off when the tablet is rotated (GNOME 51.1): mutter loses the colour mode in the
  configuration it applies for a rotation. Fixed upstream for mutter 51.2; until Fedora ships it, switch HDR on
  again in Settings, Displays ([`docs/display.md`](../display.md), Known issues).
- The HDR switch is gone after a system update: a newer Fedora build of `libdisplay-info` has replaced the
  rebuild (`rpm -q libdisplay-info` shows no `sp11` in the release). Build the RPM again on that Fedora build
  and install it ([`docs/guide/build-rpms.md`](build-rpms.md), [`docs/guide/update.md`](update.md)); from
  libdisplay-info 0.4.0 on the rebuild is not needed.
- Switching HDR on or off, like every change of the display mode, blanks the screen for about a second: the
  panel is powered off and on. Logging in to a session that has HDR on is such a switch.
- The login screen is at full brightness after a session with HDR on: the session leaves the backlight at its
  maximum, and the login screen starts from the level of the last shutdown
  ([`docs/display.md`](../display.md), Known issues).
- GPS (5G SKU) needs a view of the sky: near a window the first position came within about a minute, away from
  windows none in two minutes. Until then, and wherever GPS is weaker, GeoClue gives the Wi-Fi location
  ([`docs/gnss.md`](../gnss.md)).
- Mobile data (5G SKU, kernel revision 8 or later): Fedora's provider list offers no APN for some carriers (o2
  Germany: set `internet` in Settings > Mobile Network). Up to kernel revision 8 the modem restarts after every
  sleep, so a SIM with a PIN asks for it again and the connection returns about a minute after a wake; from
  revision 9 the modem keeps its power through a sleep and the connection is back within about 17 s, within
  2 s with support 3.9 (ModemManager's quick resume). Either way only if the profile connects automatically
  ([`docs/modem.md`](../modem.md), Across a sleep).
- Mobile data does not come back by itself after a wake, and GNOME's Mobile Data switch shows off: the profile's
  `connection.autoconnect` is `no`. Set it once, with the profile's name from
  `nmcli -g NAME,TYPE connection show | grep gsm`:

  ```bash
  nmcli connection modify "Default" connection.autoconnect yes
  ```

  NetworkManager then connects about 2 s after a wake and at boot. GNOME's switch is this same setting, so
  switching it off there clears it again ([`docs/modem.md`](../modem.md), Across a sleep).
- Plugging the charger in while the tablet sleeps wakes it, sometimes several times in the first minutes. Under
  KDE Plasma, with the cover closed, it goes back to sleep about 10 s after each wake.
- Under KDE Plasma, with the power button set to Sleep, waking the tablet with the power key puts it back to sleep
  a few seconds later. Set the power button to Lock screen (below).
- With Secure Boot on ([`docs/guide/secure-boot.md`](secure-boot.md)), Fedora's own boot entries start no kernel
  on this tablet: a kernel without a signed boot image needs Secure Boot off, and so does the installer. The
  kernel also refuses modules its build did not sign.
- With Secure Boot on, GRUB loads no font file from the disk. From support RPM 3.15 its menu is drawn from
  images and looks like the usual one; the text menu behind it, GRUB's editor and its command line are in small
  text. A menu in small text from the start means the images could not be drawn
  ([`docs/guide/secure-boot.md`](secure-boot.md), GRUB's menu while Secure Boot is on). Fedora starts by itself
  after ten seconds either way.
- Boot messages seen on the tested unit that mean nothing:
  - `qcom_pmic_glink … Failed to create device link` for the PD and USB nodes (probe deferral, retried);
  - `surface_hid … unexpected descriptor length` for one Surface Aggregator endpoint nothing depends on;
  - `unknown device posture for type-cover: 0`, once each time the keyboard is attached;
  - the ADSP's `Handover signaled, but it already happened` lines, about one per second while a sensor stream is
    open.

## Fixed in earlier releases

Systems running an older build of the RPMs can show these; the release named fixes each.

- Wi-Fi missing on some boots, Bluetooth working (the PCIe link failing to train, `LTSSM: PRE_DETECT_QUIET`, or
  the chip stopping after the link came up, `failed to power up :-34`), more often with Windows Fast Startup or
  hibernation on: fixed in kernel 7.2.14 revision 1 (2026-11-02), whose stable update resets the Wi-Fi chip before
  the link trains ([`docs/hardware.md`](../hardware.md), Wi-Fi). Until then a full shutdown, or a reboot, brought
  Wi-Fi back.
- Auto-rotation and the light sensor stopping until iio-sensor-proxy is restarted, under KDE Plasma: fixed in
  `libssc` 0.4.4-3 (2026-10-07). Until then `sudo systemctl restart iio-sensor-proxy` brings them back
  ([`docs/sensors.md`](../sensors.md), Known issues).
- The tablet waking within seconds of going to sleep under KDE Plasma, and sleeping and waking in a loop with the
  cover closed, while automatic brightness or auto-rotation kept a sensor stream open: fixed in `iio-sensor-proxy`
  3.9-3.sp11.2 with `sp11-sensors` 1.11 (2026-10-08). Until then, switching automatic brightness off (System
  Settings, Display & Monitor) avoids it.
- `hexagonrpcd-adsp-sensorspd.service` listed as failed (`start-limit-hit`) after many sleeps in one boot, the
  sensors still working: fixed in `sp11-sensors` 1.12 (2026-10-08).
- A boot that sat minutes in `dracut-initqueue` and came up without battery reading, Wi-Fi and sensors, and
  then would not shut down (three of twenty boots): fixed in kernel 7.2.15 revision 2 (2026-11-06), a lock-order
  deadlock in the QRTR driver's start-up ([`docs/kernel-patches.md`](../kernel-patches.md), 7.2.15 revision 2).
  Until then only a long press of the power button ended such a boot.
- GeoClue without a heading from the compass: `sp11-sensors` 1.13 (2026-10-23). Five SELinux denials logged by
  iio-sensor-proxy at every start, the sensors working regardless: `sp11-sensors` 1.15 (2026-10-24).
- Upgrading `iio-sensor-proxy` from 3.9-3.sp11.1 can pause `dnf` for about 45 s and leave an `iio-sensor-proxy`
  core dump: the old proxy does not stop in time and systemd aborts it. The reboot after the install brings up the
  new one.
- The GRUB menu and its editor showing no underscores and letters cut off at the bottom: fixed in support RPM
  3.10 (2026-11-10), whose smaller console font fits GRUB's character cell
  ([`docs/fedora-media.md`](../fedora-media.md), GRUB image, font and modules).
- The speakers silent after a pause in the sound, with kernel 7.3.3, while everything else shows the sound
  playing: support RPM 3.11 (2026-11-15) keeps two clock votes of the audio block held, without which a restart
  of the amplifiers' bus at times left them off it ([`docs/hardware.md`](../hardware.md), Audio). Until then,
  stopping every sound for ten seconds and playing again brings them back, sometimes at the second or third try.
- At every boot the screen going black for a second, the login screen flashing up, and another second of black
  before it stayed: fixed in kernel 7.3.3 revision 4 (2026-11-13), which no longer switches the display mode
  when a gamma table is set or dropped ([`docs/display.md`](../display.md), Gamma tables and mode sets).
- No mobile network after a boot (5G SKU, kernel 7.3.3 revision 4, about one boot in seven), the modem missing
  from the bus because its PCIe link was not up when the kernel looked for it: fixed in kernel 7.3.3 revision 5
  (2026-11-16), which looks again by itself once the modem signals that it is ready; mobile data then comes
  about 15 s later than in other boots ([`docs/modem.md`](../modem.md), The link at boot). Until then a reboot
  does not bring the modem back; shutting the tablet down, waiting ten seconds and starting it again does.
- Opening the cover not waking the tablet from sleep, the power key waking it, with kernel 7.3.3 revisions 2
  and 3: the cover wakes it again with support RPM 3.11 and kernel 7.3.3 revision 5 or later
  ([`docs/sleep.md`](../sleep.md), Sleep state and wake sources).
- No sound and no battery status in the live session: fixed in the ISO built with support RPM 3.18
  (2026-11-23), whose live initramfs starts the audio DSP ([`docs/hardware.md`](../hardware.md), The DSP on the
  live media).
- `Windows Boot Manager (on …)` twice in GRUB's menu, the second entry asking for the GRUB password, since
  Fedora's os-prober 1.81-13 (2026-11-22): fixed in support RPM 3.20 (2026-11-23), which switches os-prober off
  ([`docs/fedora-media.md`](../fedora-media.md), GRUB image, font and modules).
- A poweroff that restarted the tablet instead, with Secure Boot on, after the TPM had refused systemd's
  measurements: fixed in support RPM 3.22 (2026-11-24), which lets the poweroff go on when its two TPM
  measurements fail ([`docs/hardware.md`](../hardware.md), TPM).

## The power button under KDE Plasma

The press that wakes the tablet from the power key reaches KDE as an ordinary press of the power button. With the
button set to Sleep, KDE puts the tablet back to sleep 1 to 6 s after such a wake. Set it to Lock screen instead:
the waking press then locks the session, which is already locked after a sleep, and the button locks the screen
while the tablet is awake. Sleep with the cover or from the application launcher. "Do nothing" also ignores the
press, but KDE then does not load its button handling at all, so Lock screen is the setting used here. In tablet
mode KDE's power management does not handle the power button (it unbinds its shortcut), so the setting applies with
the keyboard attached.

In System Settings, Power Management, set "When power button pressed" to "Lock screen" on each of the tabs On AC
Power, On Battery and On Low Battery. The same from a terminal in the desktop:

```bash
for p in AC Battery LowBattery; do kwriteconfig6 --file powerdevilrc --group "$p" --group SuspendAndShutdown --key PowerButtonAction 32; done
```

```bash
busctl --user call org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement org.kde.Solid.PowerManagement reparseConfiguration
```

To check, sleep from the launcher with the cover open, wake with the power key and wait 15 s: the tablet stays on
the lock screen. With the cover closed it goes back to sleep 10 s after any wake, by design
([`docs/sleep.md`](../sleep.md)). A kernel change that drops the waking press is described in
[`docs/kernel-patches.md`](../kernel-patches.md).
