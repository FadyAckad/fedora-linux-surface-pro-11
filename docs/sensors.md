# Sensors (Snapdragon Sensor Core)
The Snapdragon Sensor Core stack: the hardware, the kernel side, the daemons and their packaging, the inputs from
Windows, the runtime design, the stack in the ISO, the check tool, the compass, known issues and the upstream state;
the dated history is at the end. Tablet mode and auto-rotation: `docs/tablet-mode.md`.

## Hardware and the Windows path

- No sensor is on a bus Linux can see. All sit on QUP instances owned by the ADSP's sensor framework (SSC:
  protection domain `sensor_pd` inside `qcadsp8380.mbn`, `adsps.jsn`); the Denali DTS has no sensor nodes.
- Windows drives them through two ACPI stubs, `MSHW048A` (display) and `MSHW048B` (keyboard), with
  `qcSensors.dll`, a QMI/protobuf client.
- The chips, from the registry JSONs: ST LSM6DSV accel+gyro on the SSC's I3C buses 2 (display) and 1 (keyboard),
  AKM AK0991x magnetometer on I2C 4/3, AMS TCS3430 ALS/colour on I2C 4, TMD2755 ALS/prox, LPS22DF barometer on
  I2C 7.

## Kernel

- Nothing to change for the sensors themselves; the stack uses `CONFIG_QCOM_FASTRPC=m` with the ADSP `fastrpc`
  node (`hamoa.dtsi:4372`, `qcom,non-secure-domain`, hence `/dev/fastrpc-adsp`), `FASTRPC_IOCTL_INIT_ATTACH_SNS`,
  `QRTR`/`QRTR_SMD=m` and `qcom_pd_mapper` advertising `msm/adsp/sensor_pd` for x1e80100. Auto-rotation needs the
  tablet-mode switch patch (`docs/tablet-mode.md`).
- Installed system only: the live session blacklists the ADSP (`docs/hardware.md`).

## Stack

- `hexagonrpcd -s` attaches to the sensors PD and serves the DSP a virtual tree from `-R DIR` (`rpcd_builder.c`):
  `/vendor/etc/sensors/config` from `DIR/sensors/config/`, `/vendor/etc/sensors/sns_reg_config` from
  `DIR/sensors/sns_reg.conf`, `/sys/devices/soc0/*` from `DIR/socinfo/*` and, in the fork, the whole
  `/persist/sensors/registry` from `DIR/sensors/persist`.
- `libssc` finds the framework's QMI service `QMI_SERVICE_SSC` (0x190 = 400) on QRTR; iio-sensor-proxy 3.9's
  `drv-ssc-{accel,light,compass,proximity}.c` (`-Dssc-support`, `disabled` in Fedora) read the sensors through it.
  The proxy's udev rule enables `ssc-light ssc-compass` on `fastrpc-adsp*`, `ssc-accel` is the opt-in, and its
  unit allows `AF_QIPCRTR`.
- SELinux: Fedora's `iiosensorproxy_t` has no `qipcrtr_socket` rule, so `sp11-sensors` loads a CIL module, which
  also carries the logind rules of the sleep pause and, since 1.13, the D-Bus rules of GeoClue's compass source
  (Compass).
- GIO: up to 1.14 the proxy was refused, at every start, a read of `/etc/passwd` and twice `dac_read_search` and
  `dac_override` (five `AVC` lines; the sensors worked regardless). The chain (`strace -k`, 2026-10-24): libqmi's
  device property calls `g_file_new_for_uri`, GIO loads its modules, gvfs's client module asks for the user
  runtime directory, GLib looks root up in `/etc/passwd` and tries `/root/.cache`, behind the unit's
  `ProtectHome`. Since 1.15 a drop-in (`iio-sensor-proxy.service.d/10-sp11.conf`) sets
  `GIO_MODULE_DIR=/usr/share/empty`: no GIO module loads and GIO keeps its built-in local VFS (`GIO_USE_VFS=local`
  would still load the modules).
- `sp11-sensors-check` and `sp11-diag` search the whole journal for denials since sp11-sensors 1.14 and support
  3.7. Before, they searched only the kernel's messages (`journalctl -k`), where audit's denials never appear, so
  an earlier "no AVC" was not a finding.

## Inputs from Windows

- The DriverStore package (unelevated), `DriverStore/FileRepository/surfacepro_snscfgcrd8380.inf_*`: 65 JSON
  files, `json.lst`, `sns_reg_config` and the calibration and platform files; `json.lst` lists
  `8380_crd_tcs3430_0.json` twice and omits `sns_cal.json`, so step 45 ships every JSON of the package and leaves
  the list as Windows wrote it.
- Every text file in the package is CRLF. `sns_reg_config`, `json.lst` and the platform files are shipped as LF
  (step 45 strips the CR, step 46 refuses one): with the Windows bytes the DSP asked for
  `.../registry\r/sns_secure_database.bin` and never found its registry. The JSONs and the registry files stay
  CRLF (whitespace inside JSON).
- The per-unit files, exported by step 75 from under a SYSTEM/Administrators ACL that denies WSL and unelevated
  PowerShell: the registry the framework wrote under Windows,
  `C:\Windows\System32\drivers\DriverData\Qualcomm\fastRPC\persist\sensors\registry\registry\`, and the 6
  calibration overrides in `...\fastRPC\vendor\etc\sensors\config\`, which replace the package's copies.
- Two files of the registry's parent directory, `sns_reg_version` (9 bytes, `version=1`, no line ending) and
  `parsed_file_list.csv` (CRLF, written by the DSP, kept byte for byte), go to the payload's
  `sensors/registry-parent/` (step 45): served among the entries, the DSP deleted them as stale.
- Export-script pitfalls (steps 70 and 75): a cancelled UAC prompt leaves `Start-Process -Verb RunAs` without a
  process object (`exit $p.ExitCode` is 0), so both steps treat that as failure, catching the status on the
  pipeline itself (`$PIPESTATUS` is unreachable after a failed pipeline under errexit). The Windows temp directory
  comes from `$env:USERNAME`, which stops naming the profile directory after an account rename.

## What the framework does on attach

- The framework parses the JSONs itself (`oemconfig.so` is refused and not needed) and keeps its registry only
  when every configuration file's modification time equals the stamp its `sns_reg_config` entry recorded;
  otherwise it removes the secure database and every entry and re-parses. Hence the payload keeps Windows' mtimes:
  the stamps match 62 of the 65 DriverStore JSONs and the two Surface calibration overrides.
- Then, within a second, the writes Windows sees on every boot: in place, the `DIR` marker (a write test must not
  use that name) and `sns_secure_database.bin`; through a temporary `fstempfile` in the registry's parent, renamed
  into place, `parsed_file_list.csv` and two entries. They need input buffers above the 256 bytes the listener
  inlines and a writable registry tree with its parent. The registry work repeats on the next attach until one
  attempt completes; re-attaches after a resume make no file request.
- A refused registry write aborts the whole ADSP: upstream's daemon refuses `fopen(.../registry/registry/DIR, w)`
  and quits on method 24 (`apps_std_fremove`), which gave `crash detected in adsp` and a crash-and-restart loop
  every 5 s (the CDSP falls with it, the battery indicator flaps); stopped with `systemctl mask --now`, removing
  the package, `dracut -f` and a reboot.
- The ADSP boots in the initramfs, but `/dev/fastrpc-adsp` appears only with the root's udev, 16 to 25 s into the
  boot; the attach follows the node by about 0.6 s and does the registry work. An initramfs attach (sp11-sensors
  1.1 and 1.2) is refused until the sensors PD is up and is not needed.
- QMI service 400 is registered as soon as the framework starts, registry or not, so readiness is a reading:
  `ssccli --sensor light` under `timeout` (its own `--timeout` does not cover the registry lookup); without a
  working file server every request ends in "'registry' sensor timed out after 30s, is hexagonrpcd running?". A
  healthy log has no `Unsupported`, `Refusing` or `Large` line; ENOENT refusals of `sns_tppe.so` and
  `c:/Data/test/cam_registry_dump.txt` are normal.

## Packaging

### hexagonrpc

- `hexagonrpc` 0.5.0 from the project's fork `HEXAGONRPC_REPO` (github.com/FadyAckad/hexagonrpc), branch
  `sp11-sensors` = upstream 598b591 plus five commits, pinned by `HEXAGONRPC_COMMIT`, which must sit on the pushed
  branch (nothing keeps a commit no branch contains). Release `<n>.git<hash>.sp11` (`HEXAGONRPC_RPM_RELEASE`): the
  number must rise with every change, rpm compares `git<hash>` as a string.
- The fork adds write support for mapped directories (`apps_std` `fopen` in write modes, `fwrite`, `fsync`,
  `fremove`, `ftrunc`, `frename`), answers unsupported requests with `AEE_EUNSUPPORTED` instead of quitting,
  fetches input buffers over 256 bytes with `adsp_listener_get_in_bufs2`, and maps the persist tree (Stack).
- The spec builds with `-Dhexagonrpcd_verbose=true`, runs upstream's unit tests, moves the units meson puts under
  `/usr/lib64`, and adds the `fastrpc` sysusers entry and a `GROUP=fastrpc, MODE=0660` rule for `fastrpc-*`.

### libssc

- `libssc` 0.4.4+ provides `libssc.so.2`, pinned by `LIBSSC_COMMIT` (Codeberg serves a shallow fetch only by the
  full hash). The QMI mock server is built unconditionally (hence `python3-devel`, `protobuf-compiler` and
  `protobuf-c-compiler` as build dependencies) and deleted by the spec.
- Release 3 adds the three patches of `payload/sensors/libssc/` (Known issues): step 45 copies them into the source
  RPM and the spec applies them with `%autosetup -p1`. `LIBSSC_RPM_RELEASE` rises for a change to the spec or the
  patches; upstream main is still at the pinned commit.

### iio-sensor-proxy

- Fedora's SRPM of the target release rebuilt with `-Dssc-support=enabled` and the project's patch, release
  `<fedora>.sp11.<n>` (`IIO_SENSOR_PROXY_RPM_SUFFIX`, `sp11.2` since the patch); the SRPM is pinned by URL and
  checksum (`IIO_SENSOR_PROXY_SRPM`, Koji's unsigned copy; `docs/pipeline.md`).
- The patch, `payload/sensors/iio-sensor-proxy/0001-Pause-sensor-polling-across-system-sleep.patch` (Runtime
  design), adds `test_system_sleep` to upstream's `tests/integration-test.py` (umockdev, python-dbusmock's logind
  template); run upstream's suite when the patch is rebased, it needs no SSC hardware. Step 45 copies the patch
  into the source RPM, the spec applies it with `%autosetup -p1`, and step 45 refuses a proxy binary without
  `PrepareForSleep`. The suffix rises for a change to the template or the patch.
- Step 45 refuses an SRPM with patches, and one whose spec differs from the copy the template was made from
  (`IIO_SENSOR_PROXY_BASE_SPEC_SHA256`): refresh the template, then the pin.

### sp11-sensors

- The payload lives under `/usr/share/qcom/x1e80100/Microsoft/denali-oled`, the path the daemon derives from the
  DT without `-R` (`/usr/share/qcom/<qcom,SOC>/<first word of model>/<device>`): the DriverStore package with its
  control files converted to LF, the unit's registry of 343 entries, the two parent-directory files and the 6
  calibration overrides (Inputs from Windows).
- The files keep Windows' modification times (`install -p`, `source_date_epoch_from_changelog 0` and
  `clamp_mtime_to_source_date_epoch 0` in the spec; the JSONs 1747743181 to 1747743185, the Surface overrides
  1789827151); step 46 compares two of them.

## Runtime design

- udev `SYSTEMD_WANTS` on the `fastrpc-adsp` misc device starts `hexagonrpcd-adsp-sensorspd.service` and
  `sp11-sensors-online.service` (the stock `[Install]` is unused); the same rule adds `ssc-accel` to
  `IIO_SENSOR_PROXY_TYPE` and sets `ACCEL_MOUNT_MATRIX` (`docs/tablet-mode.md`). The daemon's drop-in:
  `-R /var/lib/sp11/hexagonrpc`, `stdbuf -oL` (stdout is fully buffered on the journal socket),
  `ExecCondition=+sp11-sensors-guard`, `Restart=on-failure`, `RestartSec=5`, `StartLimitBurst=4` per 5 min.
- `sp11-sensors-guard` refuses an attach with exit 3 once `crash detected in adsp` is in the boot's kernel log, and
  after 12 attaches per boot (counted in `/run/sp11-sensors/attaches`). It must be a condition:
  `RestartPreventExitStatus=` covers the main process only and an `ExecStartPre` exit 3 is restarted until the
  start limit, while an `ExecCondition` exit 1-254 skips the unit without a failure. Step 46 asserts the drop-in
  has neither setting.
- Since 1.12 the re-attach after a wake does not count: `sp11-sensors-resume.service` leaves
  `/run/sp11-sensors/resume`, and the guard removes it and counts that start in `resume-attaches` instead. Such a
  start is still refused after an ADSP crash or once the cap is exceeded; a daemon that fails after a wake is
  still stopped by the start limit, and its restarts count.
- The daemon serves `/var/lib/sp11/hexagonrpc` (tmpfiles): links to the package's `sensors/config`,
  `sensors/sns_reg.conf` and `socinfo`, and a `fastrpc`-owned `sensors/persist/` (the DSP's
  `/persist/sensors/registry`) with a `C`-copy (mtimes kept) of the registry in `persist/registry/` and of the two
  parent-directory files beside it. `sp11-sensors-reset` rebuilds the copy, effective at the next boot: the
  framework reads its registry once per ADSP boot.
- The tmpfiles run is in `%posttrans`, not `%post`: on an upgrade `%post` runs while the previous release's payload
  is still in place, and the copy took stale files along (step 46 catches this). `%posttrans` also removes the
  1.3/1.4 copy at `sensors/registry`, and a `%triggerpostun -- sp11-sensors < 1.3` regenerates the running kernel's
  initramfs when a 1.1/1.2 package is upgraded away (hence `Requires: dracut`).
- `sp11-sensors-resume.service` restarts the daemon `After=suspend.target`: the stock unit's
  `Conflicts=suspend.target` stops it, nothing restarts a conflict-stopped unit, and `sleep.target` is active
  before the suspend. Since 1.12 it runs `systemctl reset-failed` on the daemon first, which also resets its start
  limit: a wake is not a restart loop, and five wakes in five minutes had hit the limit.
- `sp11-sensors-wait` (the online unit, `TimeoutStartSec=5min`) waits for a light reading, then hands
  iio-sensor-proxy what its own probe missed, without restarting it (Compass).
- The sleep pause: iio-sensor-proxy stops every sensor when logind sends `PrepareForSleep(true)` and starts the
  claimed ones on `PrepareForSleep(false)`, logging `Pausing sensor polling for system sleep` and
  `Resuming sensor polling after system sleep`. A first claim made during the sleep is answered with the first
  reading after the wake. While awake the proxy holds a `sleep` `delay` inhibitor lock (`systemd-inhibit --list`)
  and releases it once the sensors are stopped, so logind waits for that, at most `InhibitDelayMaxSec` (5 s);
  without a lock, `PrepareForSleep` alone does not delay the sleep. The CIL module allows the proxy's D-Bus
  messages with logind and the lock's FIFO (`systemd_logind_inhibit_var_run_t`): the rules Fedora's policy gives
  fprintd for its own sleep lock.
- One function, `reconcile_polling()`, starts and stops the drivers for claims, releases, hotplug and sleep. A
  claim, release or sleep notice served inside libssc's synchronous calls only makes it go round again, so libssc's
  open and close never nest. The proxy is never stopped or restarted around a sleep: the CDSP asserts around its
  exits (Known issues), while the pause ran 35 sleeps without an assert.
- `91-sp11-sensors.conf` excludes `iio-sensor-proxy` in dnf's main configuration (the support RPM's kernel
  exclusion is a repository override, `docs/pipeline.md`; step 46 checks both). The exclusion also filters a local
  RPM of the package: the four RPMs go in one transaction, and a later SP11 build of the proxy needs
  `--setopt=disable_excludes='*'`.

## In the ISO

- Step 50 installs the four RPMs into the live root with `--noscripts` and applies the scriptlet effects itself in
  the chroot: `systemd-sysusers hexagonrpc.conf`, `semodule -i sp11-sensors.cil` and
  `systemd-tmpfiles --create sp11-sensors.conf`. It asserts the user, the module, the fastrpc-owned registry copy
  and a live initramfs without the stack, puts the RPMs under `/sp11/rpms` and installs missing runtime
  dependencies from `build/cache/rpm-deps` (`protobuf3-c` provides `protobuf-c`).
- The live session never starts hexagonrpcd or the online unit (the ADSP is blacklisted); Anaconda's rsync carries
  the policy store, `/etc/passwd` with `fastrpc` and the registry copy, so the installed system runs the stack from
  its first boot. Step 46 installs the RPMs with `--replacepkgs` and the previous release with `--oldpackage`;
  step 60 checks them in the ISO.

## ADSP safety

- Nothing in the stack writes `/sys/class/remoteproc/*/state` (step 45 greps the stage for it; `sp11-sensors-check`
  only reads it): stopping the ADSP through remoteproc resets the SoC.
- hexagonrpcd only attaches to the existing sensors PD (`INIT_ATTACH_SNS`), never creates a PD (`-c`) nor supplies
  DSP libraries, and its exit leaves the sensors running on the DSP.

## sp11-sensors-check

- `sp11-sensors-check` (also run by `sp11-diag`) reports the stack from boot to desktop: the daemon, the guard's
  two counters, the DSP's file requests measured against `/run/sp11-sensors/attaches` (the last counted attach; a
  re-attach after a wake leaves it alone since 1.12), one `ssccli` reading per sensor, iio-sensor-proxy, sleep,
  SELinux and tablet mode.
- Its sleep section lists the inhibitor locks, the proxy's pause and resume lines, and one line per sleep of the
  boot with its length and the `Handover signaled` lines logged during it (0 for a sleep without a stream open).
- `PanelOrientationManaged` is asked on the logged-in user's session bus with `runuser`/`gdbus`, so run the check
  with `sudo` from a terminal in the desktop; under KDE Plasma that query fails with a D-Bus error and the rest
  applies. `libinput-utils` is optional.
- The boot clock runs two hours behind until NTP corrects it, so systemd's "since … ago", early file times and
  `find -newer` are off; the check measures the DSP's writes against `/run/sp11-sensors/attaches`, which the same
  clock stamped.

## Compass

- libssc builds the compass from the DSP's `rotv` fusion sensor, which the framework publishes a few seconds after
  the physical sensors, while the proxy probes the SSC sensors once, on the udev "add" of the node, 0.6 to 0.7 s
  after the attach: the compass was missing from that probe on three of six boots. A proxy restart brings it back
  but drops every client's claim and once made the CDSP assert.
- Since 1.9 the online helper sends the proxy a synthetic uevent instead,
  `udevadm trigger --action=add --settle /sys/class/misc/fastrpc-adsp`, until the proxy reports `HasAccelerometer`,
  `HasAmbientLight` and `HasCompass`: it polls for 3 s after each event and waits 2, 4, 8, then 16 s between them,
  within 120 s. The proxy answers an `add` by probing only the sensor types it lacks and leaves existing sensors
  and their clients alone. A synthetic `add` starts the node's `SYSTEMD_WANTS` units again, and an event from
  inside the online oneshot merges with its own job, so the helper sends it only while hexagonrpcd and the proxy
  are active, and starts a stopped proxy instead of restarting one; step 46 asserts that it restarts or stops no
  unit. Not yet exercised on the device.
- GeoClue's compass source (heading for every location source) asks the proxy over D-Bus. Fedora 45's policy lets
  neither `geoclue_t` send D-Bus messages to `iiosensorproxy_t` nor the reverse (two `USER_AVC ... denied
  { send_msg }` lines at every GeoClue start), and behind that `ClaimCompass` needs polkit's
  `net.hadess.SensorProxy.claim-sensor`, granted to active sessions only, while GeoClue runs as user `geoclue`
  without one. 1.13 allows both D-Bus directions in the CIL module and adds `80-sp11-sensors-geoclue.rules`,
  which grants the claim to user `geoclue` (still refused for another system user). On the device: 229 of 230
  GeoClue locations in 60 s carried a heading, changing as the tablet turned; no denial, no CDSP crash.

## Known issues

### The CDSP asserts around stream changes (open)

- The CDSP firmware asserts (`sleep_statsi.c:537`, recovered by remoteproc in 0.1 to 0.2 s) around sensor streams
  starting or stopping on the ADSP: after an ADSP crash, at a proxy restart or stop with a stream open, once
  between two `ssccli` readings; never at a client's last release (about 200 in the same boots) and never in 35
  sleeps with the pause. Nothing on Linux uses the CDSP (`/dev/fastrpc-cdsp` has no client). Tracked, not fixed.

### hexagonrpcd's memory

- systemd reports 622 to 638 MiB for hexagonrpcd after each boot's first attach: page cache (RSS 1.4 MiB) pulled in
  by the guard's `journalctl -k -b -g`, which runs in the unit's cgroup. Reclaimable, so left as it is: a changed
  guard could not be re-verified without an ADSP crash.

### Fixed

- The sensor stall (libssc 0.4.4-3, 2026-10-07): under KDE Plasma the orientation sometimes stopped after a wake
  until the proxy was restarted; the proxy had spun at a full core and crashed in libssc. KWin's claim churn
  nested two synchronous opens on one sensor, whose shared report handler the first completion unhooked. The three
  patches of `payload/sensors/libssc/` make the wait block and give each request its own handler context.
- The sensor streams woke the system from deep sleep (iio-sensor-proxy 3.9-3.sp11.2 with sp11-sensors 1.11,
  2026-10-08): an open stream makes the ADSP raise an SMP2P interrupt about once a second (the `Handover signaled`
  lines), which ends a deep sleep, and KWin does not release the light sensor before a sleep. The proxy's sleep
  pause (Runtime design) closes every stream for the sleep: 20 sleeps in one boot without an ADSP signal.
- hexagonrpcd stayed down after many wakes (sp11-sensors 1.12, 2026-10-08): every wake's re-attach counted
  against the guard's cap of 12 and the unit's start limit. 1.12 counts them apart and resets the limit (Runtime
  design): 15 wakes in seven minutes with the daemon running. A test of the limit needs a unit that stays loaded,
  as systemd forgets the limit of a unit it unloads.
- The proxy's stop timed out (3.9-3.sp11.1): a release served inside a pending synchronous open ran a nested
  close, after which the open never completed and SIGTERM could not end the main loop; at the upgrade to
  3.9-3.sp11.2 systemd aborted the stop after 45 s with a core dump. 3.9-3.sp11.2 calls no driver nested and
  stops in under 0.1 s. Not changed: the proxy keeps a sensor marked as polling after a failed open and retries
  only at the next sleep and wake; not seen on the device.

## Upstream state

- No pull request or fork at linux-msm/hexagonrpc carries these changes (checked 2026-09-19; main has not moved
  past 598b591). PR #21 (draft, for issue #19, the same `.../registry/registry/DIR` refusal) stubs the writes and
  conflicts with main (PR #13). Maintainer guidance (lumag): real writes belong in a writable directory under
  `/var` and attempts to modify `/usr/share/qcom` should fail loudly, which the fork does.
- The fork's `sp11-sensors` branch (head 40e5041) carries five signed commits by the owner; fork only for now, no
  pull request.
- iio-sensor-proxy: master is still the 3.9 tag (2026-03-02) and has no sleep handling; no merge request proposes
  one (checked 2026-10-08). The sleep patch is generic, covers every sensor type and carries its test.

## History

- 2026-09-19: 1.0 attached safely; CRLF hid the registry; a refused write (1.2) looped the ADSP; 1.4 gave data.
- 2026-09-20: hexagonrpc 0.5.0-3 and 1.6: registry accepted, every write served, no crash, all five sensors.
- 2026-09-21: 0.5.0-6 held over three resumes; kernel revision 2 (POS switch) and 1.9 (compass): auto-rotation.
- 2026-09-24: hexagonrpc 0.5.0-7 (a sysusers comment), live root only.
- 2026-09-29: 0.5.0-8 re-pins the same source at the branch head 40e5041, byte-identical; live root only.
- 2026-09-30: 0.5.0-8 and 1.10 on KDE Plasma: tablet mode, auto-rotation and automatic brightness confirmed.
- 2026-10-03: kernel revision 10 on KDE Plasma: auto-rotation stopping after some wakes, traced to libssc.
- 2026-10-07: libssc release 3 on the device: no spin or crash over twenty claim cycles, a reboot and a sleep.
- 2026-10-08: open sensor streams found to end the deep sleep under Plasma; iio-sensor-proxy 3.9-3.sp11.2 (the
  sleep pause) and sp11-sensors 1.11 on the device: 20 sleeps in one boot without an ADSP signal; 1.12 the same
  evening: the daemon ran through 15 quick wakes. The old proxy's 45 s stop traced to a pending open.
- 2026-10-23: GeoClue's compass source refused by SELinux and, behind it, by polkit; 1.13 allows both.
- 2026-10-24: the proxy's five denials at every start traced to gvfs's GIO module; 1.15 loads no GIO module.
