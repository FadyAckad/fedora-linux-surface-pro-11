---
name: sp11-camera-update
description: Maintain the Surface Pro 11 cameras. Rebuild Fedora's libcamera with the patches of payload/camera/ for a new Fedora libcamera release, change a patch or the cameras' tuning (exposure target, digital gain, a colour matrix), check the result on the host (steps 47 and 48, the exposure-control and shader models, the raw-capture probe against simulated sensors), hand it over for a device round and record the results. Camera changes in the kernel go through a new SP11 kernel revision.
when_to_use: The maintainer reports a camera problem or asks for a camera change ("the face is white in daylight", "set the exposure target to 1.6", "add a colour matrix", "the picture pumps"), Fedora ships a new libcamera ("step 47 refuses the source RPM", "the front camera is dark again after an update"), or asks to measure the sensors on the device.
argument-hint: "[the change to make, or the new libcamera version]"
---

# Maintain the SP11 cameras

Request: $ARGUMENTS

The camera stack has two halves. The kernel side is part of the SP11 patch set (0059–0074 of the fork branch: CAMSS
C-PHY, the IMX681, OV13858 and VD55G0 drivers, the Denali camera nodes, the front camera's light, the IMX681's frame
length). libcamera is Fedora's source RPM rebuilt by step 47 with `payload/camera/`: turbineBMW's IMX681 support
(0001–0003), Robert Bozik's faster exposure control with digital gain (0004, backported), and this project's
analogue-gain bound (0005), tuning files (0006), whole-quad GPU downscaling (0007), exposure target from the tuning
file (0008) and nearest analogue gain code (0009). Step 50 installs the rebuild into the ISO in place of Fedora's
build. How it works and why: `docs/camera.md` (the source of truth); device history: `docs/verified.md`. Every
command below with its expected output: [reference.md](reference.md). Device-round template:
[handoff.md](handoff.md). Host tools: [agc-model.py](agc-model.py), [debayer-model.sh](debayer-model.sh) with
[debayer-model.py](debayer-model.py), [probe-fake.sh](probe-fake.sh) with [probe-fake.py](probe-fake.py).

## Rules

- Never commit, push or create a branch; the libcamera scratch clone stays local, and nothing goes upstream unless
  the maintainer asks. Commits prepared for the maintainer carry no `Co-Authored-By` trailer.
- This project's patches carry no `From:` or `Date:` lines (`payload/` names no one); a third-party patch keeps its
  author and date and gets an `[sp11: ...]` note naming its source and what changed.
- Every change to `rpm/libcamera.spec.in` or to a patch in `payload/camera/` needs the next
  `LIBCAMERA_RPM_SUFFIX`: step 47 refuses a changed input at the same release, because dnf ignores a same-release
  rebuild. The probe (`sp11-camera-probe`) is not packaged and needs none.
- A change reaches `README.md` and the guides only after a device round. A new fact goes into `docs/camera.md`
  first; `docs/verified.md` gets the round's results.
- The ISO is rebuilt only on request. Tracked files carry no per-unit identifiers or local paths (`CLAUDE.md`,
  Rules); the hand-off location is in `CLAUDE.local.md`.

## 1. Find the layer

| Symptom | Where | First check |
|---|---|---|
| Dark and grainy in a dim room | the room: at the limits (33 ms, 16x or 15.5x, 4x digital) nothing more is possible at 30 fps | the exposure log shows `exp 3546 again 16 dgain 4` and an MSV near 1; `agc-model.py` shows the same for 1 lux |
| Too bright or too dark in normal light | `exposureTarget` in the tuning files (0008), 1.4 on both cameras | try values on the device by editing the installed tuning file (reference.md) |
| Slow to settle, or brightness pumping | the control law (0004, 0008) | `agc-model.py` before and after the change |
| Coloured squares or patterns when downscaled | the GPU debayering (0007) | `debayer-model.sh`; compare with `LIBCAMERA_SOFTISP_MODE=cpu` on the device |
| Muted colours | no colour-correction matrix | needs a colour-chart measurement (reference.md) |
| Levels or controls in doubt (a gain that does nothing, a frame rate that does not change) | the sensor or its driver | `sp11-camera-probe` on the device: levels, `--dark`, `--frame-length`, `--gain-range` |
| Front camera dark and slow after a Fedora update | Fedora's libcamera replaced the rebuild | `rpm -q libcamera` lacks `.sp11.`: rebuild for the new version (section 2) |

A kernel change (a driver fix, a device-tree change) is a new commit on the fork branch and a new
`KERNEL_SP11_REV` (`docs/kernel.md`); a new Fedora kernel goes through the `sp11-kernel-update` skill, whose
rebase carries the camera commits with the rest.

## 2. A new Fedora libcamera

1. The source RPM is pinned in `sp11.conf` (`LIBCAMERA_SRPM`, `LIBCAMERA_SRPM_URL`, `LIBCAMERA_SRPM_SHA256`:
   Koji's copy, unsigned, checked against Fedora's signed one when pinned; reference.md, section 2). Pin the new
   build; step 10 downloads it, and step 47 stops if Fedora's spec changed and prints the new
   `LIBCAMERA_BASE_SPEC_SHA256`.
2. Diff Fedora's old and new `libcamera.spec` and carry Fedora's changes into `rpm/libcamera.spec.in`. The template
   differs from Fedora's spec in: the `Patch02`–`Patch10` lines after Fedora's own, `Release: @BASEREL@.@SUFFIX@`,
   the IPA re-sign path (`libcamera/ipa/ipa_*.so`; Fedora's spec re-signs a path the modules are not in, so its
   signatures belong to the unstripped modules), the `Inputs:` line in the main package's description, the header
   comment and a changelog entry.
3. Before rebasing, read upstream's changes since the old version: a patch that landed (turbineBMW's IMX681
   support, a debayering fix) drops out; upstream master moved `src/ipa/simple` to `src/ipa/softisp` and ports the
   AGC to a common algorithm, so a release with that needs 0004, 0005, 0008 and 0009 ported, not rebased (master
   sets the gain code in libipa's `agc.h`); changes to `swstats_cpu.cpp` (histogram, statistics period) or
   `debayer_egl.cpp` meet 0004 and 0007.
4. Rebase in the scratch clone (`build/camera-wip/libcamera-up`, blobless; never `/tmp`): detach at `v<new>`, apply
   0001–0009 in order, resolve, export (reference.md, section 3). Keep turbineBMW's and Bozik's authorship.
5. Pins: the source RPM's (step 1), `LIBCAMERA_BASE_SPEC_SHA256` as step 47 printed it, the next
   `LIBCAMERA_RPM_SUFFIX`, the suffix example in the comment above it; step 47's strings checks if a tuning key or
   the shader function was renamed.
6. Host checks (section 4), then a device round (section 5).

## 3. A change to the tuning or a patch

- Tuning values live in the patches: `imx681.yaml` is created by 0003 (turbineBMW's file) and changed by 0006 and
  0008, `ov13858.yaml` is created by 0006 and changed by 0008. Step 47 rebuilds both files from the patches and
  compares them with the packaged ones, so a value is changed in the patch that sets it and in every later patch
  that carries its line as context: 0008's hunks end with 0006's `maxDigitalGain: 4.0` and the two comment lines
  above it, so a change there goes into 0006 and 0008 alike (or amend 0006 in the scratch clone and export again).
- `exposureTarget` is clamped to 1.3 to 5 (0008). The MSV's floor is 1 (every sample in the darkest fifth), so a
  target near 1 leaves little room below it: 0008 scales the thresholds and the proportional gain with the target
  and squares the jump ratio when brightening; keep that when changing the control law.
- In a tuning file `Awb` comes before `Agc`: the digital gain multiplies the colour gains Awb sets each frame. A
  tuning file without `Awb` (or with it disabled) keeps `maxDigitalGain` at 1, or the colour gains grow every frame.
- The IPA sets the sensor's nearest gain code (0009): the helper's truncated code kept the IMX681 below 16x in some
  dim scenes, where one code is worth more than the AGC's smallest step. `agc-model.py --gain-codes truncate` shows
  the old behaviour.
- The OV13858 driver offers gain codes up to 64x, the sensor stops at 15.5x: `maxAnalogueGain: 15.5` in
  `ov13858.yaml`, or the exposure control raises the gain through codes that do nothing before its digital gain
  starts. The bound has to be a code's exact gain (code/128 on the OV13858, 1024/(1024 - code) on the IMX681): the
  IPA reads the set code's gain back, and while that stays below the bound the exposure control keeps asking for
  more analogue gain and never starts the digital gain.
- Code changes: amend the commit in the scratch clone, export again, and add a `PatchNN:` line for a new patch.

## 4. Build and verify on the host

1. `scripts/47-build-camera-rpms.sh`: about five minutes in its mock root; runs step 48 when a live root exists.
2. A control-law or target change: `agc-model.py` with the old and the new values. Today (target 1.4, 4x digital
   gain): a 1 lux spot never reaches the target (the device agrees), 10 lux within about 6 s, a room and daylight
   within about 1.5 s, the MSV's spread under 2 %.
3. A shader change: `debayer-model.sh <scratch clone> v<version>`; expected numbers in `debayer-model.py`.
4. A probe change: `probe-fake.sh` runs the standard scenarios against simulated sensors.
5. For an ISO (on request): step 50, then 35, 46, 48 and 60; step 48 then reinstalls over the ISO's build.

## 5. Device round

A hand-off folder as `CLAUDE.local.md` describes, from the template in [handoff.md](handoff.md): the three RPMs
(`libcamera`, `libcamera-ipa`, `libcamera-tools`) with a `.sha256` each, the steps file, `README.txt`, the probe
when a measurement is needed. Expected log lines come from the previous round, not from reading the code. Copy the
returned files into `build/handoff/<folder>-results/` before reading them.

## 6. Documents

- `docs/camera.md`: the change, why, and the host results; a history line.
- After the round: `docs/verified.md`, and `docs/guide/cameras.md` or `README.md` if what works changed.
- `docs/guide/credits.md` for a new third-party patch; `docs/guide/build.md` if step 47 or 48 changed; the spec's
  changelog. Lines of at most 116 columns with code spans whole; the MAC grep of `CLAUDE.md` before handing over.

## Pitfalls

- `/tmp` is wiped when the host restarts: the scratch clone and every work file belong under `build/camera-wip/`.
- Files on the Windows desktop can be unreadable from WSL by path (drvfs ACLs): read text with
  `cmd.exe /c type <path> | tr -d '\r'`, copy images through PowerShell and base64 (reference.md).
- `cam -c` takes a camera's number from `cam -l`: set the numbers and capture in the same terminal, or `cam` opens
  no camera and the captured log is empty.
- Editing an installed tuning file works until the next libcamera update, which replaces it.
- A tuning key that parses is not proof that the IPA reads it: step 47 checks the key names in `ipa_soft_simple.so`.
- Fedora's own build logs `signature is not valid` and runs the IPA isolated; the rebuild logs `signature is
  valid`. `uncalibrated.yaml` in the log for the front camera means the IMX681 support is missing.
- The IMX681's frame length is the 24-bit register `0x033d` (the standard `0x0340` is ignored), its line 9.378 us;
  on a kernel before revision 8 the exposure stops at 2660 lines.
