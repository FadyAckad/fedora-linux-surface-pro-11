# Install

Writing the media, the firmware settings, the installer and the first boot. What the installer and the first-boot
service do underneath is in [`docs/fedora-media.md`](../fedora-media.md).

1. Write the ISO to a USB stick of 16 GB or more. On Windows, use Rufus in DD image mode or Fedora Media Writer.
   On Linux, run `sudo dd if=<iso> of=/dev/sdX bs=4M status=progress oflag=sync` after checking the target with
   `lsblk` (`dd` erases it).
2. In Windows, shrink `C:` to free at least 60 GB. Keep Windows (see
   [Status and scope](../../README.md#status-and-scope)).
3. Enter the Surface UEFI (hold Volume-Up + Power), disable Secure Boot and put USB first in the boot
   order.
4. Boot the USB and take the first GRUB entry.
5. Run "Install to Hard Drive" and choose "Share disk with other operating systems". Keep a single
   Fedora installation on the machine: a second one takes over the GRUB menu and hides the first.
6. Reboot without the USB and log in. On the first boot, a one-shot service enables the audio DSP, gives
   GRUB the Denali DTB, its display settings and the Windows entry, and rebuilds the initramfs. If audio is
   not up yet, reboot once. The sensors stack comes up with the DSP (auto-rotation, ambient light, compass).

The media carries a note at `/sp11/README.txt` and, under `/sp11/rpms`, every RPM it was built with: the source for
later updates ([`docs/guide/update.md`](update.md)).
