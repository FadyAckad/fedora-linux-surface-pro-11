# Display

The built-in panel and HDR: what the panel announces, when a gamma table costs a mode set, what GNOME needs
before it offers HDR, the kernel and the library side, what the device has shown, known issues, the display
probe. The kernel commits are in `docs/kernel-patches.md` (7.3.3 revisions 3 and 4), the library's build step in
`docs/pipeline.md`, the unit's identity in `docs/hardware.md`, the device results by date in `docs/verified.md`.

## The panel

- Samsung `ATNA30DW01-1` (EDID vendor `SDC`, product 0x4195): 2880x1920 at 120 Hz and at 60 Hz, both with a
  712.091 MHz pixel clock, 10 bits per colour.
- Its EDID is a 1.4 base block without a timing plus one DisplayID 2.0 extension. The extension holds the modes,
  the luminance (600 cd/m2 full screen, 900 cd/m2 on a tenth of it, 0.0005 cd/m2 minimum), BT.2020 with SMPTE
  ST 2084 as a colour space and EOTF combination, and a CTA-861 data block with the colorimetry `BT2020RGB` and
  the HDR static metadata (type 1, traditional SDR and PQ, 911 cd/m2 maximum, 604 cd/m2 frame average).
- Nothing about HDR is in a CTA-861 extension block, where EDID readers looked for it before DisplayID 2.0.
- The link (DPCD, 2026-11-12): four lanes at 8.1 Gbit/s with 30 bits per pixel, on 7.3.3 revision 2 already; the
  rate table lists 1.62, 2.7, 5.4 and 8.1 Gbit/s. 10 bits per colour at 2880x1920 and 120 Hz need 21.4 Gbit/s,
  and four lanes at 5.4 Gbit/s carry 17.3.
- DPCD 0x2210 reads 0x08: the panel takes the VSC packet with colorimetry. It has no DSC; it supports PSR, which
  the driver leaves off unless the kernel is booted with `msm.psr_enabled=1`.
- Every full mode set powers the panel off and on (`panel-samsung-atna33xc20.c`: 150 ms after the enable line
  drops, 500 ms powered off, 400 ms after power-on before the enable line rises): at least 1.05 s of black. A
  switch between SDR and HDR is one.

## Gamma tables and mode sets

- A gamma table or a colour matrix (CTM) is programmed into the DSPPs of the CRTC's mixers (their GC and PCC
  blocks). X1E80100 has six mixers, four of them with a DSPP; the panel takes two mixers, as every mode wider
  than 1080 pixels does.
- Up to 7.3.3 revision 3 a CRTC got its DSPPs only in a mode set that already carried a gamma table or a CTM,
  and patch 0017 forced a full mode set whenever either came or went.
- Two programs set the table in turn. Plymouth sets a linear one once, with its first picture. mutter's first
  commit carries none, because its own waits for the colour device, and colord starts on demand half a second
  after the login screen's gnome-shell; its table, an identity ramp of 1024 entries without a CTM, follows in a
  commit that allows no mode set.
- Revision 3, recorded on 2026-11-13 at 50 samples a second: the DSPPs reserved under Plymouth's picture; at
  mutter's first commit the DSPPs released and the backlight off for 1047 ms; the login screen's first picture
  for 0.18 s; the DSPPs reserved again and the backlight off for 1065 ms. From the first black to the steady
  login screen 2.3 s; no mode set at the login.
- From revision 4 every mode set reserves the DSPPs of the CRTC's mixers while mixers with a free DSPP are left
  (0114), and only a CRTC without them needs a mode set for a gamma table or a CTM (0113). Recorded the same
  day: the DSPPs reserved from Plymouth's picture on, no mode set at the login screen's start, at the login or
  while Night Light came and went; no flashing picture at boot or logout (owner).
- What stays a mode set, with the backlight off for about 1.06 s: a switch between SDR and HDR and a login into
  an HDR session (the DisplayPort driver asks for one when `max bpc`, `Colorspace` or the HDR metadata changes,
  revision 3), another resolution or refresh rate. A blanked screen and a suspend disable the CRTC and power the
  panel off; its DSPPs are reserved again when it comes back.
- The backlight device is `dp_aux_backlight` (raw, 0 to 4095, DPCD brightness control). systemd-backlight
  restores the level saved at the last shutdown over a second before gdm starts, and the login screen then sets
  its own: from a restored 1795 it went to 2470 with its first picture and on to 2641 and 2546, and the session
  back to 1795 (2026-11-13).

## HDR under GNOME

GNOME Settings 51 shows "HDR (High Dynamic Range)" under Displays when mutter lists the colour mode BT.2100 for
the monitor (`supported-color-modes` in `gdctl show --verbose`). mutter 51 lists it when the kernel and the EDID
agree on both halves (`src/backends/native/meta-output-kms.c`, `src/backends/meta-monitor.c`):

| mutter wants | from the kernel | from the EDID, through libdisplay-info |
|---|---|---|
| colour space BT.2020 | connector property `Colorspace` with the value `BT2020_RGB` | signal colorimetry `bt2020_rgb` |
| EOTF PQ | connector property `HDR_OUTPUT_METADATA` | HDR static metadata with type 1 and `pq` |

- The kernel: up to 7.3.3 revision 2 the msm driver attaches neither property and sends a VSC packet only for
  YUV 4:2:0. Revision 3 carries the DisplayPort HDR series (0090–0111): `max bpc`, `Colorspace` and
  `HDR_OUTPUT_METADATA` on eDP-1, DP-1 and DP-2, the BT.2020 VSC packet and the HDR static metadata packet, HDR
  only at 10 bits per colour, HDR streams kept out of PSR.
- The library: Fedora's libdisplay-info 0.3.0 searches CTA-861 extension blocks only and reads just the header
  of a DisplayID 2.0 block, so mutter gets no HDR metadata and no BT.2020 from this panel. Step 47 rebuilds
  Fedora's source RPM with the eleven upstream commits of 0.4.0 that read the data blocks of a DisplayID 2.0
  extension and the CTA-861 blocks inside them (`payload/display/libdisplay-info/`, each patch file with its
  upstream commit; four are positioned for 0.3.0, their changed lines are upstream's).
- The rebuild keeps the soname `libdisplay-info.so.3` and exports Fedora's 86 symbols plus three, so mutter and
  Mesa's Vulkan drivers keep linking against it; its release is Fedora's plus a suffix (`0.3.0-2.sp11.1`).
  0.4.0 itself has the soname `.so.4`: Fedora would have to rebuild every user with it and carries it in no
  release (2026-11-12).
- With both in place (2026-11-12, mutter 51.1): mutter lists `default, sdr-native, bt2100` where revision 2 gave
  `default, sdr-native`. HDR on gives `Colorspace = BT2020_RGB`, a metadata blob with EOTF 2 (PQ), the BT.2020
  primaries and D65 without luminance values, an XR30 plane and no kernel message.
- Brightness in HDR: mutter sets the backlight device to its maximum (4095 of 4095) and dims through its
  reference white; `gdctl`'s backlight preference then reads 10 to 210.
- Repeated on 2026-11-12: nine switches between SDR and HDR, seven suspends with HDR on, three lock-screen
  blankings and five boots, without a DisplayPort, DPU or panel error in the kernel log and with the session
  back in HDR each time. The brightness keys and slider, colours, a screenshot and Night Light behave in HDR
  (owner).

## Known issues

- Rotating the tablet switches HDR off (mutter 51.0 and 51.1): `meta_monitor_config_copy()` copies a monitor
  configuration without its colour mode and RGB range, and every rotation applies such a copy. Fixed upstream
  on 2026-10-15 (merge request 5389, commit `ea9a191ace63`, on the `gnome-51` branch), three days after 51.1; no
  patched mutter is built, Fedora's 51.2 brings it.
- A Fedora update of libdisplay-info replaces the rebuild, and its soname decides what follows: a later 0.3.0
  build leaves the HDR switch missing until step 47 is run on that source RPM (a new pin, the template
  refreshed); 0.4.0 reads the panel's data itself and ends the rebuild.
- The HDR series is not merged (second version of 2026-10-09, changes asked for): the next rebase takes
  upstream's current version instead of these commits.
- Not exercised on this unit: 0036's link-rate quirk under the series (the 5G SKU's panel reports its rates
  itself), PSR with HDR (`msm.psr_enabled=1`; 0107 keeps the peripheral flush for a stream outside PSR), HDR on
  an external display.
- The login screen at full brightness after an HDR session: the session leaves the backlight at 4095, that
  level is restored at the next boot, and the login screen kept it (2026-11-13, revision 4).
- A GPU hang at login that recovers by itself, in one of five boots on 2026-11-12 (7.3.3 revision 3, HDR off):
  25 s after the boot the GMU's bandwidth vote times out (`HFI_H2F_MSG_GX_BW_PERF_VOTE`), `hangcheck recover`
  follows 3 s later with gnome-shell as the offending task, and the session goes on.

## The display probe

- `payload/display/sp11-display-probe` (`sudo python3`, unpackaged) writes a report and changes nothing: the
  connectors' KMS properties read without probing a connector, the atomic state and the DP driver's debug files
  from debugfs, the eDP panel's DPCD through the AUX device of its controller, the backlight devices, the
  installed versions of mutter and libdisplay-info, and the kernel log's display lines with a warning or an
  error.
- `--root DIR` reads a copy of `/sys`, `/dev` and `/proc` instead, without root and without an ioctl.
- What to read in it: `Colorspace`, `HDR_OUTPUT_METADATA` and `max bpc` under `eDP-1`; `supported link rates`
  and `link now`; `VSC SDP extension for colorimetry`; `bpp` in the DP driver's debug file.

## History

- 2026-11-12: the missing HDR switch traced to the driver's properties and the library's EDID reading; 7.3.3
  revision 3 and libdisplay-info `0.3.0-2.sp11.1` built; HDR on, off and across a suspend on the device; the
  round with repeated switches, suspends and an 8-hour sleep passed.
- 2026-11-12: the login screen's second of black traced to the mode sets around mutter's gamma table; 7.3.3
  revision 4 built with the DSPPs reserved in every mode set.
- 2026-11-13: the starts of revision 3 and 4 recorded: two mode sets before the login screen settles on
  revision 3, none on revision 4; its round passed.
