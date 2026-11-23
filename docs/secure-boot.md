# Secure Boot
The installed system with Secure Boot on: why Fedora's own boot path starts no kernel on this firmware, the route
that does, the stub, the signed boot image and its package, what the support RPM's tool keeps on the device,
GRUB's behaviour under Secure Boot, what it protects, known issues. The build steps and their pins:
`docs/pipeline.md`; GRUB, its font and the boot entries: `docs/fedora-media.md`; the TPM and the Windows entry:
`docs/hardware.md`; the procedure for a user: `docs/guide/secure-boot.md`.

## The route

- With Secure Boot on the Surface starts Fedora through the firmware, Fedora's signed shim, Fedora's signed GRUB,
  GRUB's `chainloader` and one file per kernel signed with the owner's key (a stub, the kernel and the unit's
  device tree); the kernel runs in lockdown `integrity`. On the device with shim-aa64 16.1-7, grub2-efi-aa64
  2.12-83 and kernel 7.3.5 revision 1: a test image on 2026-11-20, the packages on 2026-11-21.
- Fedora's own entries start no kernel with Secure Boot on. GRUB's `linux` command hands the image to shim's
  loader, and shim 16.1-7's `LoadImage()` does not return on this firmware once it has verified the image: with
  shim's log on, the last lines are the image's hash for the measurement, and the allocation's line never comes
  (2026-11-20). The screen stays as it is. The firmware call between the two is the image's measurement into the
  TPM; which of the two hangs is not separated.
- `chainloader` is built into Fedora's arm64 GRUB (2.12-81, 2.12-83). With Secure Boot on GRUB loads the image
  itself: it has shim verify the file, copies it and jumps into it. shim reports no memory attribute protocol
  and an executable heap on this firmware, and the jump works. With Secure Boot off the same command uses the
  firmware's loader.
- The owner's certificate must be in shim's key list (`mokutil --import`, confirmed in shim's key manager at the
  next start; enrolled on the tested unit on 2026-11-20). Without it GRUB answers `bad shim signature` and waits
  for a key (QEMU).
- The kernel's command line is the `chainloader` line's arguments, and the initramfs is a file on the ESP.
  Neither is signed, as in Fedora's own Secure Boot setup.

## The stub

- systemd-stub 262.1 from Fedora 45's systemd source RPM (pinned in `sp11.conf`) with one patch
  (`payload/secureboot/stub/`), built alone in mock from `rpm/sp11-secureboot-stub.spec.in` in 20 s. It names
  itself `systemd-stub 262.1-sp11.1` in the EFI variable `StubInfo`.
- The patch starts the kernel without the firmware's `LoadImage()`, which shim's loader would answer, and reads
  the initramfs named by `sp11_initrd=<path>` from the ESP, the image's own volume first, in pieces of 1 MiB. It
  hands the file to the kernel through the interface GRUB uses for an initramfs.
- The stub reads the file because the kernel's own `initrd=` loader delivered none from the ESP on this
  firmware: the kernel panicked at the root mount (2026-11-20).
- A missing initramfs ends in two error lines for ten seconds and the return to GRUB; the kernel is not started
  (QEMU, 2026-11-21). `sp11_stub=debug` shows the stub's progress and pauses; `sp11_stub=shim-loader` takes
  systemd's own path.
- With the two test patches of the device rounds the same recipe gave the stub the Surface ran on 2026-11-20,
  byte for byte except the PE time stamp.

## The signed image and its package

- Step 25 packs the stub, `vmlinuz` and the unit's device tree out of the built `kernel-core` RPM with `ukify`
  and signs the file with `sbsign`. The image has no `.cmdline` and no `.initrd` section; `--hwids=""` keeps
  ukify from adding a hardware-ID table from the host's systemd. Its `.linux` and `.dtb` sections are byte for
  byte the package's files. It is 17.9 MB for 7.3.5 revision 1.
- Package `sp11-kernel-secureboot-<uname -r>`, with the kernel's version in its name so that several install
  side by side: `/usr/lib/modules/<version>/sp11-secureboot.efi`, `.der` (the certificate) and `.info` (the
  kernel's checksum, the device tree, the stub, the certificate's checksum). It requires `kernel-core` of that
  version; `kernel-core-uname-r` would also be met by `kernel-uki-dtbloader`.
- The key directory (`SECUREBOOT_KEY_DIR`, default `sp11-secureboot/` of the checkout: `sp11-mok.key`,
  `sp11-mok.crt`) is kept out of git by `.gitignore`, which also ignores `sp11-mok.key` anywhere in the tree (since
  2026-11-22; before, `~/.config/sp11-secureboot`). Only `sbsign` in step 25 reads the private key: it enters no
  mock root, no RPM and no file under `build/`. Without the directory step 25 builds nothing and step 26 has
  nothing to check.
- The private key is kept encrypted with its owner's passphrase (PKCS#8, scrypt; since 2026-11-22). `sbsign`
  asks for the passphrase on the terminal; step 25 stops with a message when it has to sign without one, so a
  session without a terminal hands that step to the owner.
- A search for a leaked key must look for the private numbers: the modulus is in every signature and
  certificate.

## On the device

- `/usr/libexec/sp11/sp11-secureboot sync` keeps, for every installed kernel with a signed image, a boot entry
  and an initramfs, a copy of the image and of the initramfs in `/boot/efi/EFI/sp11sb` and writes
  `/boot/grub2/sp11-secureboot.cfg`. The copies have 8.3 names (`k` and seven hex digits of the version's
  checksum) and are written under a temporary name, compared and renamed. Copies of kernels that are gone are
  deleted; files of another name are left alone.
- The entries file holds one `chainloader` entry per kernel, newest first, with the options of that kernel's own
  boot entry (`$tuned_params` passed on, the tool's own words dropped) plus `sp11_initrd=` for the entry's first
  initramfs file. GRUB's default names one of Fedora's entries, which match nothing there: GRUB then takes the
  first entry (`grub-core/normal/menu.c`), the newest signed kernel. What else the file holds acts with Secure
  Boot on (GRUB under Secure Boot, below).
- The tool offers an image only for the kernel build its record names: a rebuild under the same version carries
  other module keys. It refuses options GRUB would interpret.
- `sync` runs after every kernel install and removal (`96-sp11-secureboot.install`, behind dracut's 50, tuned's
  92 and Fedora's default-entry plugin 95; it never fails the install), in the scriptlets of the support RPM and
  of the add-on, and in `sp11-secureboot.service` at every start and shutdown. The unit carries over an
  initramfs rebuilt outside kernel-install, and its journal holds what each run did.
- `grub.cfg` reads the entries file only when GRUB's variable `lockdown` is `y`, its state with Secure Boot on
  (`/etc/grub.d/09_sp11_secureboot`, before Fedora's `10_linux`; 08 is Fedora's `08_fallback_counting`). With
  Secure Boot off the menu and its default are Fedora's.
- `status` ends in one `RESULT:` line (`NOT SET UP`, `NOT READY`, `READY`, `ACTIVE`) and names every installed
  kernel without a signed image. `remove` deletes the copies, the entries and the menu. Up to support 3.15
  `sp11-secureboot try` asked GRUB for one start through a signed entry with Secure Boot off (`TRIED`).
- The copies take the image's 17.9 MB and the initramfs, 79 MB on the tested unit, per kernel; its ESP had
  1864 MiB free with one kernel's copies (2026-11-21).

## GRUB under Secure Boot

- GRUB refuses a font file from the disk (`prohibited by secure boot policy`, one error line before the menu)
  and draws the menu with its built-in font: small at the panel's native mode, the frame as question marks (QEMU,
  and the device with support 3.12 on 2026-11-21). The font inside Fedora's GRUB image, Unifont Regular 16, is as
  small.
- From support 3.13 the entries file moves the menu to the firmware's console (`terminal_output console`) while
  GRUB is locked down. The menu then has a drawn frame, in the firmware console's font, which is as small on
  this panel (QEMU, and the device on 2026-11-21).
- Fedora's GRUB image has the theme engine and its PNG and JPEG readers built in, and a theme and its images
  load under Secure Boot; `videoinfo` is not built in. The PNG reader knows transparency only as an alpha
  channel.
- From support 3.14 a graphical menu stands in front of that text menu, from 3.15 in the usual menu's look.
  `sync` writes `/boot/grub2/sp11-secureboot-menu.cfg`: the signed entries, then the Windows entry and the
  firmware entry as `grub.cfg` holds them, each with a class `sp11-menu-N` before its own. It then has
  `sp11-secureboot-theme` draw the theme under `/boot/grub2/themes/sp11-secureboot`.
- The theme tool (Python's standard library) draws with the glyphs of the console font's PF2 file, which
  `sp11.env` names: every entry's title as one PNG (`icons/sp11-menu-N.png`, all of one size, since a theme
  scales its icons to one), the frame from the glyphs GRUB's text menu draws it with (the heavy lines, U+250F
  and its kin), the menu's two help sentences and the countdown's. The titles GRUB draws itself get the colour
  `#00000000` and do not show.
- The theme's places are the text menu's. GRUB's graphical terminal leaves 10 pixels free at every side and
  lays the font's cells from the top left: 19x38 pixels, 150 columns and 50 rows at 2880x1920. The frame stands
  in column 1 and row 3 and in the last column but one and the last row but six, the help lines and the
  countdown in the rows below it. The screen's size is `SP11_GRUB_GFXMODE` of `sp11.env`. In QEMU at 2880x1920
  the frame, the highlighted entry's bar and the text lie on the same pixels in both menus (2026-11-22).
- The countdown is a progress bar tied to GRUB's timeout whose box carries the sentence as its left parts. It
  goes with the first key, as the text menu's line does.
- GRUB clears its terminal before it starts an entry. Under a theme the terminal is a window, by default 70 % of
  the screen in its middle: only that turned black with support 3.14, and Windows' boot manager left the rest
  of the menu on the screen (the device, 2026-11-22). The theme of 3.15 makes the window the whole screen
  (`terminal-left`, `terminal-top`, `terminal-width`, `terminal-height`, `terminal-border`): no pixel of the
  menu is left once an entry is chosen (QEMU).
- While GRUB is locked down the entries file loads `unicode`, sets the theme and reads the menu's file with
  `configfile`, as a menu of its own; `default`, `timeout` and `timeout_style` are exported for it. Without the
  file or the theme, or once that menu is left with Escape, the text menu on the firmware's console follows
  (QEMU, 2026-11-22).
- The menu stays a text menu, with a line from `sync` saying so, when the theme cannot be drawn (the tool or the
  font missing, the tool failing) or when an entry's title in `grub.cfg` is not one plain quoted word.
- A menu of its own is what gives every entry an image: a theme finds an entry's image by its class, and
  Fedora's firmware entry carries none.
- With Secure Boot on `grub.cfg` names no mode: its `gfxmode` line follows the font it cannot load. GRUB's video
  driver then takes the mode the display's EDID prefers, and 800x600 without one (its source; QEMU's displays
  have none). The device's menu is at 2880x1920 (owner, 2026-11-22). QEMU shows that size on a virtio display
  with the mode named in the VM's `grub.cfg`.
- `blscfg` lists Fedora's entries from the directory the variable `blsdir` names. While GRUB is locked down the
  entries file points it at `/grub2/fonts`, which holds none: the menu then lists the signed entries and what
  the other generators add (QEMU). Where `/boot` is no filesystem of its own that path does not exist and
  Fedora's entries stay listed.
- `insmod` of a module file prints nothing under Secure Boot (2.12-83), so no error line shows whether a module
  was loaded.
- Errors printed after `terminal_output gfxterm` do not reach a serial log; the signed entries switch to
  `console` first.
- A GRUB password works under Secure Boot: Fedora's signed image (2.12-81) has `password_pbkdf2` built in, and
  with `/boot/grub2/user.cfg` from `grub2-setpassword` Fedora's `01_users` block sets the superuser `root`. Pressing
  `e` then asked for `root` and the password (2026-11-23). Entries marked `--unrestricted` start without it: the
  signed entries, Fedora's own (`grub_arg --unrestricted` from `20-grub.install`) and, from support 3.19, the SP11
  Windows entry, which started Windows without the password. UEFI Firmware Settings and os-prober's Windows entry
  carry no `--unrestricted` and need it.
- The graphical menu (`sp11-secureboot-menu.cfg`) copies only the blocks of `29_sp11_windows` and
  `30_uefi-firmware`; the text menu behind Escape is `grub.cfg`'s own, with whatever else `grub2-mkconfig` wrote.

## What it protects

- With Secure Boot on the firmware starts only signed boot loaders, GRUB only a signed image, and the kernel
  refuses unsigned modules and writes to its own memory. The only lockdown lines in the device's boots are
  hibernation's, which the unit does not use.
- Not protected: the initramfs and the command line, which are not signed, and the disk's content while the root
  is not encrypted. The tested installation's root is in LUKS2 with a key sealed in the TPM and bound to PCR 7
  (`docs/hardware.md`, TPM), which opens it at the start (2026-11-23). PCR 7 does not cover the command line or the
  initramfs, so GRUB's editor would reach a shell with the root open: a GRUB password (`grub2-setpassword`) guards
  the editor and GRUB's command line, while Fedora's and Windows' entries start without it. Replacing the unsigned
  initramfs copy on the ESP remains open to someone with the tablet.
- Whoever holds the signing key can sign an image the Surface accepts.

## What the device showed

- 2026-11-20, a test image through a hand-written entry: the login screen with Secure Boot on, 221 modules
  loaded and none refused, no failed unit, mobile data connected by itself.
- 2026-11-21, support 3.12 and the add-on of 7.3.5 revision 1: `status` `READY` after the install; one start
  through the signed entry with Secure Boot off after `try` (`TRIED`, the request cleared); with Secure Boot on
  two starts without a choice in the menu (`ACTIVE`, lockdown `integrity`); a deep sleep of 68 s and its wake;
  mobile data connected 46 s after the start; the unit's sync lines at the start and at the shutdown; no module
  refused; the journal's errors those of a boot with Secure Boot off.
- 2026-11-21, support 3.13 by `dnf upgrade` with Secure Boot on: the entries file has the console rule, and the
  next start came up by itself (`ACTIVE`); the menu had its frame, its text still small (owner).
- 2026-11-22, support 3.14 by `dnf upgrade`: the graphical menu showed at 2880x1920 with its three entries,
  Fedora came up by itself through the signed entry (`ACTIVE`), and Windows started from the menu with Secure
  Boot on. The entries' names stood three times as large as the usual menu's text beside titles of 16 pixels,
  and the cleared terminal window lay over the menu's middle while Windows started (owner, photographs).
- 2026-11-22, support 3.15 by `dnf upgrade` with Secure Boot on: `sync` drew the theme on the device (`status`:
  `graphical`), the menu's file carries the image class of its three entries, and the restart came up by itself
  through the signed entry (`ACTIVE`). The menu looked as QEMU drew it at 2880x1920, Escape led to the text
  menu, and Windows started from the menu (owner).
- 2026-11-22, support 3.16 by `dnf upgrade` with Secure Boot on: `ACTIVE` before and after a restart that came up
  by itself, GRUB's default falling back to the first signed entry; Fedora and Windows started from the menu,
  Escape led to the text menu (owner).

## Known issues

- The live medium needs Secure Boot off: its kernel goes through GRUB's `linux` command.
- A kernel without a signed image cannot be started while Secure Boot is on. GRUB starts the newest signed one
  instead, and `status` names the kernel without.
- A module the kernel's build did not sign is refused while Secure Boot is on.
- The route rests on Fedora's GRUB loading a `chainloader` image itself under Secure Boot and on this firmware
  letting that image run. If an update of shim or GRUB ends either, Fedora starts again with Secure Boot off.
- With Secure Boot on no font file can be loaded: the text menu behind the graphical one is small (GRUB's
  built-in font up to support 3.12, the firmware console's from 3.13), and so are GRUB's editor and command
  line, which `e` and `c` open from the graphical menu in Unifont 16 across the whole screen (QEMU,
  2026-11-22).
- A title longer than the menu's line is cut, as the text menu cuts it.
- Not yet seen on the device: a kernel update with its add-on.
- QEMU cannot run the route to its end with Fedora's GRUB: its firmware with Secure Boot forbids executing the
  memory GRUB's loader uses. The host's checks to the kernel use a GRUB with one changed instruction. Its virtio
  display, which gives the panel's size, shows no firmware console: the text menu behind the graphical one shows
  on the serial line only.

## History

- 2026-11-20: six device rounds. shim's loader does not return on this firmware; the route through GRUB's
  `chainloader` and the patched stub starts Fedora with Secure Boot on.
- 2026-11-21: the route as packages (the stub build, the signed image's add-on, support 3.12 with
  `sp11-secureboot`), confirmed on the device. Support 3.13 moves the menu to the firmware's console: the frame
  is drawn again, the text stays small.
- 2026-11-22: support 3.14 with the graphical menu for Secure Boot, confirmed on the device, Windows from it
  too. Support 3.15 draws that menu on the device, in the usual menu's font and places, and has GRUB clear the
  whole screen before an entry starts; confirmed on the device the same day. Support 3.16 is the same route with
  less code: no `try`, no rules for GRUB's default (its fallback to the first entry does the same), no checks
  for cases this unit does not have, and no sandbox tests (step 26 checks the installed packages); confirmed on
  the device the same day.
- 2026-11-23: a GRUB password under Secure Boot, the Windows entry `--unrestricted` (support 3.19), and the
  encrypted root opened by a key sealed in the TPM against PCR 7; confirmed on the device.
