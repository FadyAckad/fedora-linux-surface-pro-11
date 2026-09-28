# sp11-camera-update: hand-off templates

A device round for a libcamera build: the three RPMs (`libcamera`, `libcamera-ipa`, `libcamera-tools`) with a
`.sha256` each (`sha256sum <file> > <file>.sha256`), `sp11-camera-<topic>-steps.md`, `README.txt`, and the probe
with its `.sha256` when the round measures the sensors. `<new>` and `<old>` are releases such as `0.7.2-3.sp11.5`
and `0.7.2-3.sp11.4`. The steps address the maintainer ("you"), one command per block, each with what to expect.

## README.txt

```text
Surface Pro 11: libcamera <new>, <topic>, <date>

libcamera <new> (libcamera, libcamera-ipa, libcamera-tools) replaces <old>: <what changed, one or two sentences>.
Kernel revision <n> stays.

Run sp11-camera-<topic>-steps.md on the device.
```

## Steps file

````markdown
# Surface Pro 11: libcamera <new>, <topic> (<date>)

<What changed and why, in the maintainer's terms; what it should look like on the device.>

Verified off-hardware: the packages build in a Fedora <release> buildroot without compiler warnings, install over
the live root's build with PipeWire's camera plugin linked and valid module signatures, and both tuning files parse;
<the model or harness results that apply: agc-model.py, debayer-model.sh, probe-fake.sh>. Installing <new> replaces
any tuning file you edited with the packaged one. Unverified: all of it on the device. The way back: step 8.

## Part A: install

1. In this folder on Fedora:

   ```bash
   sha256sum -c *.sha256
   ```

   Expected: every file `OK`.

2. The new build, then PipeWire restarted so that desktop applications load it (as your user):

   ```bash
   sudo dnf install ./libcamera-<new>.fc45.aarch64.rpm ./libcamera-ipa-<new>.fc45.aarch64.rpm ./libcamera-tools-<new>.fc45.aarch64.rpm
   ```

   ```bash
   systemctl --user restart wireplumber pipewire
   ```

   Expected: three packages upgraded from `<old>.fc45` to `<new>.fc45`; the restart prints nothing.

3. <A check of what the build changed, e.g. the tuning values:>

   ```bash
   grep -H exposureTarget: /usr/share/libcamera/ipa/simple/imx681.yaml /usr/share/libcamera/ipa/simple/ov13858.yaml
   ```

   Expected: <two lines ending in `exposureTarget: 1.4`>.

## Part B: the exposure control in a dim room

Take the Surface to a dim spot, like a lamp-lit room in the evening. Run steps 4 to 6 in one terminal.

4. The cameras' numbers:

   ```bash
   F=$(cam -l 2>/dev/null | sed -n 's/^\([0-9]*\): .*camera@1a)$/\1/p'); R=$(cam -l 2>/dev/null | sed -n 's/^\([0-9]*\): .*camera@10)$/\1/p'); echo "front=$F rear=$R"
   ```

   Expected: `front=1 rear=2` (or other numbers, but neither empty).

5. The front camera for 5 seconds, with the exposure control's log:

   ```bash
   LIBCAMERA_LOG_LEVELS=IPASoft:INFO,IPASoftExposure:DEBUG cam -c "$F" -C150 2>&1 | grep -E 'Exposure target|Exposure [0-9]+-[0-9]+, gain|exposureMSV' | tee front-dim.txt | tail -40
   ```

   Expected: `Exposure target <value> by the tuning file`, `Exposure 8-3546, gain 1-16 (0.15)`, then
   `exposureMSV ...` lines with the factor of each step; the lines stop within a few seconds once the picture is
   right, or go on at `exp 3546 again 16 dgain 4` if the room is darker than even that allows.

6. The rear camera the same way:

   ```bash
   LIBCAMERA_LOG_LEVELS=IPASoft:INFO,IPASoftExposure:DEBUG cam -c "$R" -C150 2>&1 | grep -E 'Exposure target|Analogue gain limited|Exposure [0-9]+-[0-9]+, gain|exposureMSV' | tee rear-dim.txt | tail -40
   ```

   Expected: `Analogue gain limited to 15.5 by the tuning file`, `Exposure 4-3206, gain 0-15.5 (0.155)`, then
   `exposureMSV ...` lines as for the front camera, ending at `again 15.5 dgain 4` at most.

## Part C: by hand

7. In GNOME Snapshot, in daylight and in the dim spot, with each camera: <what to look for: brightness of a face,
   no squares, settling time, no pumping>. Keep a photo of each.

## The way back (only if needed)

8. Only if <new> misbehaves: in the folder `<previous folder>`, <old> back:

   ```bash
   sudo dnf downgrade ./libcamera-<old>.fc45.aarch64.rpm ./libcamera-ipa-<old>.fc45.aarch64.rpm ./libcamera-tools-<old>.fc45.aarch64.rpm
   ```

   ```bash
   systemctl --user restart wireplumber pipewire
   ```

   Expected: the three packages back at `<old>.fc45`.

Send back: the terminal output of the steps, `front-dim.txt`, `rear-dim.txt`, the photos of step 7, and a line on
what you saw in step 7.
````

## Optional part: the raw sensor output

When the round has to tell the sensor from libcamera (`payload/camera/sp11-camera-probe`, copied into the folder;
every camera application closed):

```bash
sudo python3 sp11-camera-probe front | tee probe-front.txt
```

Expected: a table of levels per exposure and gain, the frame rate, and ratios of about 4 and 16 for 4x and 16x and
0.5 for half the exposure; `--dark` with the lens covered, `--frame-length` and `--gain-range` as the question needs
(what each prints: the probe's docstring).

## What the logs mean

- `signature is valid` / `not valid`: the rebuild's IPA runs in process / Fedora's build runs it isolated.
- `Using tuning file .../imx681.yaml` / `uncalibrated.yaml`: the IMX681 support is there / missing.
- `exposureMSV 1.0x ... exp 3546 again 16 dgain 4`: every limit reached; the scene is too dark for 30 fps.
- `i2c-qcom-cci ... queue 0 timeout` once when switching to the rear camera: recovered by the OV13858 retry (0069).
