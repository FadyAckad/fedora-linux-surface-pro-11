# Sensors (Snapdragon Sensor Core)
The Snapdragon Sensor Core stack, tablet mode and auto-rotation; the dated device history is at the end.

## Hardware and the Windows path

- **No sensor is on a bus Linux can see.** Windows' `Sensor` class holds two ACPI stubs, `MSHW048A` (display) and
  `MSHW048B` (keyboard, "Qualcomm All-Ways Aware Sensor Platform Device", `qcSensors.dll`: a QMI/protobuf client,
  `sns_client.pb`, `sns_suid.pb`, `sns_surface_imu.pb`). The chips, from the registry JSONs: ST LSM6DSV accel+gyro
  on the SSC's I3C buses 2 (display) and 1 (keyboard), AKM AK0991x magnetometer on I2C 4/3, AMS TCS3430 ALS/colour
  on I2C 4, TMD2755 ALS/prox, LPS22DF barometer on I2C 7, all on QUP instances the ADSP's sensor framework (SSC,
  protection domain `sensor_pd` inside `qcadsp8380.mbn`, `adsps.jsn`) owns. The Denali DTS has no sensor nodes
  (`&i2c0`/`&i2c4` carry "Something @…" comments only); the T14s bit-banged LIS2DW12 is a different board.

## Kernel

- Kernel: nothing to change for the sensors themselves (auto-rotation needs the tablet-mode switch patch, see
  below). `CONFIG_QCOM_FASTRPC=m` with the ADSP `fastrpc` node (`hamoa.dtsi:4372`, `qcom,non-secure-domain`, hence
  `/dev/fastrpc-adsp`), `FASTRPC_IOCTL_INIT_ATTACH_SNS`, `QRTR`/`QRTR_SMD=m`, `qcom_pd_mapper` advertising
  `msm/adsp/sensor_pd` for x1e80100. Installed system only: the live session blacklists the ADSP.

## Stack

- Stack (denisix/ubuntu-surface-pro-11 `SENSORS.md` reports 13 sensors working on an SP11 this way):
  `hexagonrpcd -s` attaches to the sensors PD and serves the DSP a virtual tree from `-R DIR`:
  `/vendor/etc/sensors/config` ← `DIR/sensors/config/`, `/vendor/etc/sensors/sns_reg_config` ←
  `DIR/sensors/sns_reg.conf`, `/persist/sensors/registry/registry` ← `DIR/sensors/registry/`, `/sys/devices/soc0/*`
  ← `DIR/socinfo/*` (`rpcd_builder.c`; the fork serves `/persist/sensors/registry` as a whole from
  `DIR/sensors/persist` instead when that tree has a `registry` directory, see Packaging); without `-R` it guesses
  `/usr/share/qcom/<qcom,SOC>/<first word of model>/<device>` from the DT, `x1e80100/Microsoft/denali-oled` here.
  `libssc` finds `QMI_SERVICE_SSC` (0x190 = 400) on QRTR. Upstream iio-sensor-proxy 3.9 has
  `drv-ssc-{accel,light,compass,proximity}.c` behind `-Dssc-support`; Fedora builds it `disabled` (no libssc
  package), its udev rule enables `ssc-light ssc-compass` on `fastrpc-adsp*`, `ssc-accel` is the opt-in, its unit
  already allows `AF_QIPCRTR`. Fedora's `iiosensorproxy_t` has no `qipcrtr_socket` rule, so `sp11-sensors` loads a
  CIL module; under enforcing no AVC for the stack's domains has been seen.

## Inputs from Windows

- Inputs. Unelevated: `DriverStore/FileRepository/surfacepro_snscfgcrd8380.inf_*` (65 JSON, `json.lst`,
  `sns_reg_config`, `golden_color_calibration.bin`, the platform files `hw_platform`=CRD, `soc_id`=615,
  `revision`=3.1, …). **Every text file there is CRLF.** `sns_reg_config`, `json.lst` and the platform files are
  shipped as LF (step 45 strips the CR, step 46 refuses one): with the Windows bytes the DSP kept the CR in the
  values it parsed and asked for `.../registry\r/sns_secure_database.bin`, so it never found its registry. The JSON
  configs (CRLF inside JSON is whitespace) and the registry files stay as Windows has them, as denisix ships them.
  Windows' `json.lst` is not exact: it names `8380_crd_tcs3430_0.json` twice and omits `sns_cal.json`, so step 45
  ships every JSON of the package and asserts the unique listed set exists (the list stays as Windows wrote it).
  Elevated only (SYSTEM/Administrators ACL, denied to WSL and unelevated PowerShell):
  `C:\Windows\System32\drivers\DriverData\Qualcomm\fastRPC\persist\sensors\registry\registry\` (the pre-parsed
  registry the framework wrote under Windows, per unit: platform data and calibration) and
  `...\fastRPC\vendor\etc\sensors\config\` (6 calibration overrides, among them `factory_color_calibration.bin`,
  `tdm_uid.bin`, `acs_multiplier.bin` and the Surface accel/gyro calibration JSONs, which replace the package's
  copies); step 75 exports both. Windows keeps two more files in the registry's **parent** directory,
  `sns_reg_version` (9 bytes, `version=1`, no line ending) and `parsed_file_list.csv` (CRLF, written by the DSP
  itself, kept byte for byte); step 75 exports them with the entries and step 45 moves them to the payload's
  `sensors/registry-parent/` (served among the entries, the DSP deleted them as stale and tried to create
  `sns_reg_version` again). `Start-Process -Verb RunAs` on a cancelled UAC prompt returns no process object, so
  `exit $p.ExitCode` is 0: steps 70 and 75 treat that as failure explicitly, with the status caught on the pipeline
  itself (`… | sed >&2 || rc=$?`): under errexit and pipefail a `$PIPESTATUS` check after a failed pipeline is never
  reached (75 exited without its message until 2026-09-22). Both derive the Windows temp directory from
  `$env:USERNAME`, which names the profile directory on this unit; a renamed account would not, and the die says so.

## What the framework does on attach

- What the framework does when the file server attaches (the daemon's request log, `-Dhexagonrpcd_verbose=true`, run
  under `stdbuf -oL`: the log is on stdout, which is fully buffered on the journal socket otherwise). It asks for
  `oemconfig.so` (refused; not needed: the framework parses the JSONs itself, contrary to denisix's note that the
  JSON path needs that Android-only library), reads `sns_reg_config`, stats and reads the whole
  `sns_secure_database.bin` (75 reads of 512 plus 121 bytes = 38521, the exported file's size) and lists the
  registry. With every configuration file's modification time equal to the stamp its `sns_reg_config` entry recorded
  (62 of the 65 DriverStore JSONs and the two Surface calibration overrides match their Windows file times to the
  second; the overrides are what the framework parsed, not the DriverStore copies) it keeps the registry; with none
  matching (the payload's build times) it removed the secure database and every entry (341 `remove(` lines) and
  re-parsed the configuration, hence the payload keeps Windows' mtimes. A partial mismatch has not been seen. Then,
  within a second, the writes Windows makes on every boot: the `DIR` marker (3 bytes, part of the Windows export; a
  write test must not use that name), `parsed_file_list.csv` (15817 → 15478 bytes) and the entries
  `sns_ccd.json.ccd_te0_sensor0` (815 bytes) and `qsh_camera.dbg_flags` (295 bytes) through a temporary `fstempfile`
  in the registry's parent renamed into place (in the Windows export those two carry the date of the last Windows
  boot, the other `sns_ccd`/`qsh_camera` entries 2026-06-02: Windows rewrites them on every boot too), and
  `sns_secure_database.bin` (38521 bytes in 512-byte writes, above the 256 bytes the listener inlines; once in round
  5, three times per boot since). The `DIR` marker and the secure database are written in place. A healthy log has
  no `Unsupported`, `Refusing` or `Large` line. Refused with ENOENT and passed over: `sns_tppe.so` (hexagonrpcd
  supplies no DSP libraries) and `c:/Data/test/cam_registry_dump.txt`. A refused registry write aborts the whole
  ADSP. Upstream's daemon quits on method 24 (`apps_std_fremove`, sc `0x18020000`: 2 in, 0 out) and refuses
  `fopen(.../registry/registry/DIR, w)` (`Tried to open ... for writing`); the refusal gave `fatal error received:`
  `err_qdi.c:1205:EF:sensor_process:0x4:sns_registry_4:0x67:sns_registry_sensor.c:279:SNS_RC_SUCCESS == rc`,
  `crash detected in adsp` and a recovery in 5 s that took the CDSP down as well; the node reappeared, udev started
  the unit again, and so on every 5 s, with the battery indicator flapping (battery status comes over pmic_glink
  from the ADSP). Stopped with `systemctl mask --now`, removing the package, `dracut -f` and a reboot. Upstream's
  listener also quits on the first input buffer over 256 bytes (`Large (>256B) input buffers aren't implemented`,
  exit 0, which `Restart=on-failure` does not restart; the sensors keep running on the DSP). The framework repeats
  its registry work on the next attach until one attempt completes; after that, re-attaches (after a resume, the
  ADSP stays up through suspend) make no file request. The ADSP itself boots in the initramfs (dracut's `qcom-adsp`
  pre-udev hook loads the PAS driver there, before the LUKS prompt; the driver shuts the UEFI-started "lite"
  firmware down and boots the Linux firmware — mainline does this in `qcom_pas_load`, the v23 kernel did it through
  ooaklee's attach series, logging "restarting adsp with new firmware"; the timings in this section were measured on
  v23), but `/dev/fastrpc-adsp` appears only with the root's udev (16–25 s into the boot), and the framework does
  its registry work on that first root-side attach (the attach follows the node by ~0.6 s, the writes come within a
  second). An initramfs attach (sp11-sensors 1.1 and 1.2) is refused with `Could not attach to FastRPC node` until
  the sensors PD is up (the first came 20 ms after "adsp is now up") and is not needed, so it has been dropped; one
  boot with it hung at a black screen before the LUKS prompt, never explained (a hung boot leaves no journal). The
  QMI service 400 is registered as soon as the framework starts, registry or not, so readiness is a reading
  (`ssccli --sensor light`; without a working file server every request ends in "'registry' sensor timed out after
  30s, is hexagonrpcd running?"); `ssccli` hangs in its synchronous registry lookup before its own `--timeout`
  applies, so it runs under `timeout`.

## Packaging

- Packaging: `hexagonrpc` 0.5.0 from the project's fork (`HEXAGONRPC_REPO` github.com/FadyAckad/hexagonrpc, branch
  `sp11-sensors` = upstream 598b591 plus five commits, pinned by `HEXAGONRPC_COMMIT`; `git_pin` fetches the commit
  by full hash, which GitHub serves for any reachable commit). The commits: hexagonfs
  create/write/truncate/unlink/rename for mapped directories; `apps_std` `fopen` 0, `fwrite` 5, `fsync` 23,
  `fremove` 24, `ftrunc` 32, `frename` 33 (ids from quic/fastrpc `inc/apps_std.h`; the extended ids above 30 travel
  in the first prim word), and `fopen_with_env` opening `w`/`a`/`+` modes read-write and accepting absolute names
  with unknown search variables; unsupported requests answered by `invoke_requested_procedure` with
  `AEE_EUNSUPPORTED` and empty output buffers instead of ending the session; input buffers longer than 256 bytes
  fetched with `adsp_listener_get_in_bufs2` (method 5 of the interface, quic/fastrpc `inc/adsp_listener.h`; the
  first 256 bytes arrive with `next2`, the rest from offset 256 as `listener_android.c` does); the builder mapping
  `/persist/sensors/registry` as a whole to `DIR/sensors/persist` when `DIR/sensors/persist/registry` exists
  (otherwise the upstream layout); and fixes found in review (`hexagonfs_close` destroying a descriptor while a
  second file number still referenced it, `fastrpc_apps_std_deinit` ascending from the root,
  `hexagonfs_mapped_or_empty_ops` pointing the write operations of an absent mapped directory at code that
  dereferences NULL instead of returning `-ENOENT`, zero-length output buffers padded in `outbufs_calculate_size`
  that `outbufs_encode` never writes, the method id of extended methods in `alloc_outbufs4`, `+` implying `O_CREAT`,
  `stat` claiming the write bit for read-only files, a short `write(2)` reported as an error). The spec builds with
  `-Dhexagonrpcd_verbose=true`, runs upstream's three unit tests in `%check` (two of them compile the changed files:
  `iobuffer.c`, and `hexagonfs.c` with `hexagonfs_mapped.c`), moves the units meson puts under libdir
  (`/usr/lib64`), and adds the `fastrpc` sysusers entry and a `GROUP=fastrpc, MODE=0660` rule for `fastrpc-*`
  (`sscregistrygen` is built but not installed upstream). Release `<n>.git<hash>.sp11`: the number must rise with
  every change, rpm compares `git<hash>` as a string. `libssc` 0.4.4+ (`libssc.so.2`; meson declares the QMI mock
  server unconditionally: `python3-devel`, `protobuf-compiler` for `protoc`, `protobuf-c-compiler` for
  `protoc-gen-c`; the spec deletes the installed mock server; Codeberg serves `git fetch --depth 1 origin <sha>`
  only with the full hash). `iio-sensor-proxy` = Fedora's SRPM of the target release with `-Dssc-support=enabled`,
  release `<fedora>.sp11.1` (step 45 refuses an SRPM with patches, and since 2026-09-22 one whose spec differs from
  the copy the template was made from, `IIO_SENSOR_PROXY_BASE_SPEC_SHA256`: refresh the template, then the pin).
  `sp11-sensors`: payload under `/usr/share/qcom/x1e80100/Microsoft/denali-oled` (the DriverStore package's 65 JSONs
  and `golden_color_calibration.bin`, its `json.lst`, `sns_reg_config` and platform files converted to LF, plus this
  unit's registry of 343 entries, its two parent-directory files and 6 calibration overrides from
  `vendor\etc\sensors\config`; `payload/sensors/` installs elsewhere) with Windows' modification times
  (`install -p`, `source_date_epoch_from_changelog 0` and `clamp_mtime_to_source_date_epoch 0` in the spec; the
  JSONs carry their own times, 1747743181 to 1747743185, the Surface calibration overrides 1789827151, the
  registry's stamps; step 46 compares two of them).

## Runtime design

- Runtime design: udev `SYSTEMD_WANTS` on the `fastrpc-adsp` misc device starts `hexagonrpcd-adsp-sensorspd.service`
  and `sp11-sensors-online.service` (the stock `[Install]` stays unused: the node exists only after the ADSP
  booted); the same rule adds `ssc-accel` to `IIO_SENSOR_PROXY_TYPE` and sets `ACCEL_MOUNT_MATRIX`. The daemon's
  drop-in: `-R /var/lib/sp11/hexagonrpc`, `stdbuf -oL`, `ExecCondition=+sp11-sensors-guard`, `Restart=on-failure`,
  `RestartSec=5`, `StartLimitBurst=4` per 5 min. The guard refuses an attach once `crash detected in adsp` is in the
  boot's kernel log and after 12 attaches per boot (count in `/run/sp11-sensors/attaches`; resume restarts count
  too, and after a refused one the sensors keep running on the DSP without the daemon), with exit 3; it must be a
  condition: `RestartPreventExitStatus=` covers the main process only, and on the host's systemd 259 an
  `ExecStartPre` exit 3 was restarted four times until the start limit, while an `ExecCondition` exit 1-254 skips
  the unit without a failure (`Skipped due to 'exec-condition'`); step 46 asserts the drop-in has neither setting.
  The daemon serves `/var/lib/sp11/hexagonrpc` (tmpfiles): links to the package's `sensors/config`,
  `sensors/sns_reg.conf` and `socinfo`, and `sensors/persist/` (`fastrpc`-owned, the DSP's
  `/persist/sensors/registry`) with a `C`-copy of the registry in `persist/registry/` and of the two
  parent-directory files beside it; `C` keeps the mtimes. `sp11-sensors-reset` rebuilds the copy, effective at the
  next boot (the framework reads its registry once per ADSP boot). The tmpfiles run is in `%posttrans`, not `%post`:
  on an upgrade `%post` runs while the previous release's payload is still in place and the copy took stale files
  along (caught by step 46's upgrade section); `%posttrans` also removes the 1.3/1.4 copy at `sensors/registry`. A
  `%triggerpostun -- sp11-sensors < 1.3` regenerates the running kernel's initramfs when a 1.1/1.2 package is
  upgraded away, which takes their hook (`95sp11-sensors`) out (hence the spec's `Requires: dracut`); 1.3 to 1.9 ran
  that dracut in `%posttrans` on every install. `sp11-sensors-resume.service` restarts the daemon
  `After=suspend.target` (the stock unit has
  `Conflicts=suspend.target`, and nothing restarts a conflict-stopped unit; `sleep.target` is the wrong anchor, it
  is active before the suspend). `sp11-sensors-wait` (the online unit, `TimeoutStartSec=5min`) waits for a light
  reading and then hands iio-sensor-proxy what its own probe missed without restarting it (see the compass bullet
  below). `91-sp11-sensors.conf` excludes `iio-sensor-proxy` in dnf's main configuration; the support RPM's kernel
  exclusion is a repository override since 3.0, so `dnf --dump-main-config` shows only the proxy and
  `dnf --dump-repo-config=fedora` the kernel list (step 46 checks both; libdnf5 appends `excludepkgs` across
  main-configuration drop-ins, as the 2.x kernel drop-in showed). The main-configuration exclusion also filters a
  local RPM of the package ("from @commandline is filtered out by exclude filtering"): the four RPMs go in one
  transaction, a later SP11 build of the proxy needs `--setopt=disable_excludes='*'`.

## In the ISO

- In the ISO since 2026-09-22: step 50 installs the four RPMs into the live root with `--noscripts` and applies the
  scriptlet effects itself (`systemd-sysusers hexagonrpc.conf`, `semodule -i sp11-sensors.cil`,
  `systemd-tmpfiles --create sp11-sensors.conf`, all in the chroot with `/dev`, `/proc` and `/sys` bound), asserts
  the user, the module, the fastrpc-owned registry copy and a live initramfs without the stack, and puts the RPMs
  under `/sp11/rpms`. The live session never starts hexagonrpcd or the online unit (no `fastrpc-adsp` node while the
  ADSP is blacklisted), and the SSC iio-sensor-proxy without sensors behaves as the stock build; Anaconda's rsync
  carries the policy store, `/etc/passwd` with `fastrpc` and the registry copy, so the installed system runs the
  stack from its first boot. Step 46 installs with `--replacepkgs` (a reinstall after step 50) and the previous
  release with `--oldpackage`; step 60 checks the packages, the user, the module, the copy's mtime and the
  initramfs. The 45 Beta Workstation root provides every runtime dependency (`protobuf3-c` for `protobuf-c`);
  step 50 tests them by capability and installs missing ones from `build/cache/rpm-deps`, as it does for iptsd's.

## ADSP safety

- ADSP safety: nothing in the stack writes `/sys/class/remoteproc/*/state` (step 45 greps the stage for it;
  `sp11-sensors-check` only reads it). hexagonrpcd only attaches to the existing sensors PD (`INIT_ATTACH_SNS`),
  never creates a PD (`-c`) nor supplies DSP libraries (`dsp/` absent → empty), and serves the files taken from
  Windows (the control files converted to LF) and the registry copy the DSP itself rewrites. Its exit leaves the
  sensors running on the DSP. Stopping the ADSP through remoteproc resets the SoC (denisix).

## sp11-sensors-check

- `sp11-sensors-check` (also run by `sp11-diag`): boot timeline, crashes per remote processor, the daemon's status
  and memory breakdown, a summary of the DSP's writes, removals, renames and refusals with the log's head and tail,
  the files the DSP wrote measured against `/run/sp11-sensors/attaches`, one `ssccli` reading per sensor,
  iio-sensor-proxy and `monitor-sensor`, SELinux, and a tablet-mode section (switch input devices, the aggregator's
  modules and kernel lines, libinput capabilities, `HasAccelerometer`, mutter's `PanelOrientationManaged` asked on
  the logged-in user's session bus with `runuser`/`gdbus`, so run it with `sudo` from a terminal in the desktop,
  connected Bluetooth devices; `libinput-utils` is optional).

## Orientation

- Orientation: the Sensor Core reports the Android convention (the reaction force in the display frame: x right, y
  up, z out of the screen; upright on the kickstand it read x=+0.77, y=+7.39, z=+6.35 m/s²; libssc's matrix from the
  SSC placement attribute is all zeros, so identity), while iio-sensor-proxy's `test-orientation.c` wants y<0 for
  normal, x>0 for left-up and `tilt_calc` z>0 for face-up. `ACCEL_MOUNT_MATRIX="-1,0,0;0,-1,0;0,0,1"` on the node:
  the proxy reports `normal` upright (`bottom-up` without the matrix), and on the desktop the picture follows the
  device to each side and upside down.

## Tablet mode and auto-rotation

- Auto-rotation needs tablet mode. From the sources Fedora 45 ships (gnome-shell 51~beta, mutter 51~beta, libinput
  1.31): the quick toggle (`js/ui/status/autoRotate.js`) is visible iff `SystemActions.can-lock-orientation`, which
  is mutter's `panel-orientation-managed` (`js/misc/systemActions.js`); mutter (`meta-monitor-manager.c`) sets it to
  `touch mode && has accelerometer && built-in monitor`; the accelerometer is iio-sensor-proxy's `HasAccelerometer`;
  touch mode (`meta-seat-impl.c`, `update_touch_mode`) needs a touchscreen, then a **tablet-mode switch** decides
  when one exists, and without a switch it is on only while **no pointer device** exists (keyboards do not count).
  The touchscreen is `Microsoft Surface G6 Touch`; the Flex Keyboard's touchpad is a pointer attached (Surface
  Aggregator HID `045E:0C8B/0C8E/0C8D`) and detached (Bluetooth LE `Surface Pro Flex Keyboard`, which stays
  connected), so everything depends on the switch. `surface_aggregator_registry.c` matches `microsoft,denali` to
  `ssam_node_group_sp11`, which upstream (mainline too, checked 2026-09-21) gives the **KIP** cover switch
  (`ssam_node_kip_tablet_switch`, `ssam:01:0e:01:00:01`, `surface_aggregator_tabletsw.ko`, cover states
  disconnected/closed/laptop/folded-canvas/folded-back/book, tablet for disconnected, folded and book). On this
  firmware that device exists ("Microsoft Surface KIP Tablet Mode Switch", `EV=21`, `SW=2`) but stays at laptop: the
  driver reads the KIP cover state (0x0e/0x1d) once at probe and then waits for KIP event cid 0x1d, which never
  comes (KIP events arrive only with cid 0x2c, 9-byte payloads of unknown meaning). The aggregator reports every
  keyboard change as a **POS** event (tc 0x26, tid 0x01, cid 0x03, iid 0, 12-byte payload: source, previous posture,
  new posture as le32; one source, id 0, the type cover): 03 laptop attached, 01 disconnected (with or without
  Bluetooth), 05 folded back, 04 folded canvas, and 00, not in the driver's enum, for about 3 s while the keyboard
  is being attached (logged once as `unknown device posture for type-cover: 0`, reported as tablet, the mode the
  device is already in). Found with `payload/sensors/sp11-sam-posture` (python3, not packaged): it talks to the
  aggregator through `/dev/surface/aggregator` (`surface_aggregator_cdev`, `CONFIG_SURFACE_AGGREGATOR_CDEV=m`; the
  module creates its own platform device on load and binds the controller; ioctl `SSAM_CDEV_REQUEST` = `0xc028a501`,
  a 40-byte packed request with the response through a user buffer; notifier register/unregister and event
  enable/disable with the SAM event registry `0x01/0x01/0x0b/0x0c`), sends the drivers' own read-only queries (KIP
  cover state, POS sources 0x26/0x01 and posture per source 0x26/0x02), reads the kernel switch with `EVIOCGSW` and
  prints every KIP/POS event with `--watch N`. The fix, SP11 kernel revision 2 of the v23 kernel (today patch 0057
  of the SP11 patch set, `docs/kernel-patches.md`), puts `&ssam_node_pos_tablet_switch` (`ssam:01:26:01:00:01`, the
  node the Surface Pro 12" group uses) in place of the KIP node, replacing rather than adding it: libinput pairs
  every tablet-mode switch with the internal keyboard and touchpad, so a second, static KIP switch left in tablet
  state from a detached boot would keep the attached touchpad suspended. Result on the device: "Microsoft Surface
  POS Tablet Mode Switch" reports SW_TABLET_MODE 1 detached or folded back and 0 attached, `PanelOrientationManaged`
  is true when folded, GNOME offers the auto-rotate button with the keyboard folded back or detached, and libinput
  switches the keyboard and touchpad off while the keyboard is folded back (the aggregator's devices sit on
  `BUS_HOST` and count as internal). `gpio-keys` also carries a lid switch (`SW=1`).

## Compass

- The compass in iio-sensor-proxy: libssc builds it from the DSP's `rotv` (rotation vector) fusion sensor, which the
  framework publishes a few seconds after the physical sensors, and the proxy probes the SSC sensors once, on the
  udev "add" of the node, 0.6–0.7 s after the attach. At that probe the compass was missing on three of six boots
  checked (rounds 7, 10 and 11; rounds 5, 8 and 12 had it) while `ssccli --sensor compass` streamed. Restarting the
  proxy (1.8) brought it back, but the CDSP asserted 58 ms into that restart; a restart also drops every client's
  claim, and a proxy whose probe finds nothing exits. Since 1.9 the helper sends the proxy a synthetic uevent
  instead, `udevadm trigger --action=add --settle /sys/class/misc/fastrpc-adsp`, until the proxy reports
  `HasAccelerometer`, `HasAmbientLight` and `HasCompass` (object `/net/hadess/SensorProxy/Compass`, interface
  `net.hadess.SensorProxy.Compass`), polling for 3 s after each event and waiting 2, 4, 8, then 16 s between them,
  within 120 s (the limit is checked before the back-off sleep, so one more event can follow it): iio-sensor-proxy
  3.9's `sensor_changes` answers an `add` by probing, for each sensor type it lacks,
  the first driver that matches the device (one type per event) and leaves existing sensors and their clients alone,
  and its SSC discovery only looks the sensor up (libssc `*_new_sync` plus `*_close_sync`, no stream enabled). On
  the host's systemd 259 a synthetic `add` for a device that is already there starts the device's `SYSTEMD_WANTS`
  units again (a oneshot ran once per event), while events sent from inside that oneshot merged with its own job
  (three tries, one run each, also with the trigger as its last command); so the helper sends the event only while
  hexagonrpcd and the proxy are active, and starts a proxy that is not running instead of restarting one. Exercised
  against stubs (eight scenarios) and step 46, which asserts that the helper sends the event and restarts or stops
  no unit (a check 1.8's helper fails). Not needed on the device yet: on the 1.9 boot the proxy's own probe had the
  compass.

## Known issues

- Known issues. The CDSP firmware asserts (`sleep_statsi.c:537`, recovered in 0.1–0.2 s, once in 5 s) around sensor
  streams starting or stopping on the ADSP: 5 s after the ADSP crash of round 3; 130 ms and 58 ms into the two
  boot-time proxy restarts (rounds 4 and 11), which close every stream at once; about a second after a check closed
  its magnetometer stream and opened the compass (round 7); during the checks and folding tests of rounds 8 and 10
  (595.9 s and 294.9 s). Boots without a proxy restart had none at boot. Nothing on Linux uses the CDSP
  (`/dev/fastrpc-cdsp` has no client) and no stream was interrupted; tracked, not fixed. systemd reports 622–638 MiB
  for hexagonrpcd after each boot's first attach (0.2 MiB after a resume's re-attach): `memory.stat` shows it as
  `file` (634 of 635 MiB; `anon` 144 KiB, the process's RSS 1.4 MiB, no `apps_mem` map request), page cache pulled
  in by the guard's `journalctl -k -b -g`, which runs in the unit's cgroup and reads every journal file. On the
  host, with the page cache dropped, that command in a transient unit was charged 889 MiB for a 936 MiB journal and
  took 1.3 s, as did `journalctl -k -b | grep` and `journalctl -b _TRANSPORT=kernel | grep` (1.2–1.7 s);
  `dmesg | grep` was charged 3.4 MiB and took 21 ms. Reclaimable, so left as it is: reading the ring buffer instead
  (256 KB, `LOG_BUF_SHIFT=18`) would change the crash-loop guard, whose refusal path the device cannot exercise
  without an ADSP crash. The boot clock runs two hours behind until NTP corrects it (the initramfs's kernel lines
  carry the right time, the root's are two hours behind): systemd's "since … ago", early file times and
  `find -newer` against files written later are off, so the check measures the DSP's writes against
  `/run/sp11-sensors/attaches`, which the same clock stamped.

## Upstream state

- Upstream state (checked 2026-09-19 against linux-msm/hexagonrpc): no pull request carries these changes. PR #21
  (z3ntu, draft since 2026-03-20, for issue #19 "Support opening files for writing", the same
  `.../registry/registry/DIR` refusal) stubs `fwrite` (accepts the `DIR` marker and a `version=` string, nothing
  reaches disk), mocks `fremove`, hard-codes `fopen_with_env_fd`, and adds an `sns_reg_version` mapping in the
  registry's parent; it conflicts with main since the interface rework (PR #13). psacal reports there (SC8280XP,
  Windows firmware) that the DSP creates `sns_reg_version` through method 5 when it is missing and that a
  JSON-format `sns_reg_config` makes it "generate oversized messages", i.e. the large input buffers. Maintainer
  guidance (lumag): real writes belong in a writable directory under `/var`, attempts to modify `/usr/share/qcom`
  should fail loudly; the fork does that (writes go into the `-R` tree, the package stays read-only). Nobody else
  implements the large-buffer fetch, the temporary file's directory or `ftrunc`/`frename`/`fsync`: none of
  upstream's 14 forks carries write support beyond PR #21's branch, and denisix only mentions a private patch
  ("method 24 stub", "write support"); main has not moved past 598b591. The fork was created on 2026-09-19 at
  598b591 and its `sp11-sensors` branch pushed on 2026-09-20; its commits carry the owner as author and committer
  and no other trailer. Owner's decision: fork only for now, no pull request yet.

## History

- Device history on the tested unit (Fedora 45 Beta install, SELinux enforcing throughout):
  - 2026-09-19, rounds 1–4: 1.0 attached safely (both remote processors up through two suspend/resume cycles, audio
    unaffected) but the registry never reached the DSP (the CRLF defect); a refused registry write ended in the ADSP
    crash loop (1.2); with write support (hexagonrpc 0.5.0-2, 1.4) the first sensor data, with the orientation
    inverted, a re-parse on every boot and the daemon quitting on the first large write.
  - 2026-09-20, rounds 5–6: hexagonrpc 0.5.0-3 and 1.6: the registry accepted without a re-parse, every write
    served, no ADSP or CDSP crash, orientation `normal`, all five sensors; round 6 rebuilt the same code from the
    fork (`.text` byte-identical to 0.5.0-3).
  - 2026-09-21, rounds 7–12: hexagonrpc 0.5.0-6's write-path fixes held, also through three suspend/resume cycles;
    the tablet-mode diagnosis (1.7's check in four keyboard states, `sp11-sam-posture`) and kernel revision 2 with
    the POS switch; 1.8 and 1.9 for the compass; auto-rotation confirmed on the desktop.
  - 2026-09-24: hexagonrpc 0.5.0-7 changes only a comment in its sysusers file (a Debian reference removed); built
    and checked in the live root (step 46), not yet on the device.
