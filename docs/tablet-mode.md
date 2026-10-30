# Tablet mode and auto-rotation
The Surface Pro 11's tablet-mode switch, the accelerometer's orientation, what the desktops need for auto-rotation,
and the posture probe. The sensor stack itself: `docs/sensors.md`.

## What auto-rotation needs

- In Fedora 45's gnome-shell and mutter (51~beta) the auto-rotate quick toggle is visible iff mutter's
  `panel-orientation-managed` (`meta-monitor-manager.c`) = touch mode && has accelerometer (iio-sensor-proxy) &&
  built-in monitor. Touch mode needs a touchscreen (`Microsoft Surface G6 Touch`); then a tablet-mode switch
  decides when one exists, and without a switch it is on only while no pointer device exists.
- The Flex Keyboard's touchpad is a pointer attached (Surface Aggregator HID `045E:0C8B/0C8E/0C8D`) and detached
  (Bluetooth LE, which stays connected), so everything depends on the switch.
- KDE Plasma: KWin reads orientation and light from iio-sensor-proxy over D-Bus itself (`net.hadess.SensorProxy`)
  and holds the claims (`KWin::OrientationSensor` in tablet mode, `KWin::LightSensor` for automatic brightness);
  PowerDevil unbinds the power button's shortcut in tablet mode (`docs/sleep.md`).

## The tablet-mode switch

- `surface_aggregator_registry.c` matches `microsoft,denali` to `ssam_node_group_sp11`, which upstream gives the
  KIP cover switch (`ssam:01:0e:01:00:01`). On this firmware "Microsoft Surface KIP Tablet Mode Switch" exists but
  stays at laptop: the driver reads the KIP cover state (0x0e/0x1d) once at probe and then waits for KIP event
  cid 0x1d, which never comes.
- The aggregator reports every keyboard change as a POS event: tc 0x26, tid 0x01, cid 0x03, iid 0, 12-byte
  payload (source 0, the type cover; previous and new posture as le32). The postures: 03 laptop (attached), 01
  disconnected, 05 folded back, 04 folded canvas, and 00, outside the driver's enum, for about 3 s while the
  keyboard is being attached (logged once as `unknown device posture for type-cover: 0`, reported as tablet).
- The fix, patch 0057 of the SP11 patch set, puts `&ssam_node_pos_tablet_switch` (`ssam:01:26:01:00:01`) in place
  of the KIP node, not beside it: libinput 1.31 pairs every tablet-mode switch with the internal keyboard and
  touchpad, and a static KIP switch left in tablet state would keep the attached touchpad suspended. Result:
  "Microsoft Surface POS Tablet Mode Switch" reports SW_TABLET_MODE 1 detached or folded back and 0 attached, GNOME
  offers the auto-rotate button, and libinput switches the keyboard and touchpad off while folded back.

## Orientation

- The Sensor Core reports the Android convention, the reaction force in the display frame with x right, y up and
  z out of the screen; libssc's matrix is identity, while iio-sensor-proxy's `test-orientation.c` wants y<0 for
  normal, x>0 for left-up and z>0 for face-up.
- Hence `ACCEL_MOUNT_MATRIX="-1,0,0;0,-1,0;0,0,1"` on the node, set by `sp11-sensors`' udev rule: the proxy
  reports `normal` upright (`bottom-up` without the matrix), and on the desktop the picture follows the device to
  each side and upside down.

## The posture probe

- `payload/sensors/sp11-sam-posture` (python3, not packaged) sends the drivers' own read-only queries through
  `/dev/surface/aggregator` (`CONFIG_SURFACE_AGGREGATOR_CDEV=m`), reads the kernel switch with `EVIOCGSW` and
  prints every KIP/POS event with `--watch N`.

## History

- 2026-09-21: the KIP switch found static; the POS switch (kernel revision 2 of v23.2) gives GNOME auto-rotation.
- 2026-09-30: tablet mode, auto-rotation and automatic brightness confirmed on KDE Plasma.
