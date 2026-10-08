# What the scripts decide for you

The choices built into the pipeline and the support RPM, with the reason for each. The mechanism behind every
bullet is in the working note it names.

- Kernel: Fedora's `kernel-7.2.9-300.fc45` source RPM with Fedora's configuration, rebuilt with the 74 patches of
  the branch `sp11/7.2.9` of the project's kernel fork (on the stable tag `v7.2.9`, pinned by commit; SP11
  revision 11) and with `payload/kernel-local`. [`docs/kernel.md`](../kernel.md); each patch, its authors and what
  it is needed for: [`docs/kernel-patches.md`](../kernel-patches.md).
  - `kernel-local` enables the patch set's touch driver and two camera sensor drivers, and two drivers Fedora's
    configuration leaves out, the video clock controller and the crypto engine: without them Linux never lowers
    the power-rail and bus votes it takes at boot, and the compute DSP never wakes from sleep.
  - The patches are ooaklee's Surface Pro 11 work from linux_ms_dev_kit-sp11 v23 with the X1E fixes from jglathe's
    tree that act on this machine, turbineBMW's camera branch and this repository's own commits; that tree's
    Ubuntu packaging, SAUCE patches, camera stack and ADSP attach series are not carried.
- Device tree: `qcom/x1e80100-microsoft-denali-oled.dtb` from the kernel package, loaded explicitly everywhere:
  GRUB `devicetree` on the live media, `GRUB_DEVICETREE` in every boot entry through the kernel-install plugin
  `15-sp11-surface.install`, because Fedora's automatic selection (`kernel-uki-dtbloader`) matches none of this
  SKU's SMBIOS hardware IDs. [`docs/hardware.md`](../hardware.md), [`docs/fedora-media.md`](../fedora-media.md).
- Kernel arguments: `clk_ignore_unused pd_ignore_unused systemd.tpm2_wait=0`, which Fedora's "Snapdragon WoA
  Laptop Install" page prescribes for X1E laptops, and `soundwire_qcom.sp11_feedback_active_offset2_zero=1` (the
  SP11 audio patches). The live media adds `modprobe.blacklist=qcom_q6v5_pas rd.driver.blacklist=qcom_q6v5_pas`,
  the same page's advice for booting from USB-C, because restarting the ADSP resets the port; the installed system
  drops them. [`docs/hardware.md`](../hardware.md).
- GRUB: `gfxterm` at the panel's native `2880x1920,auto` with a 40 pt DejaVu Sans Mono PF2 font, built with
  `grub2-mkfont` and shipped in the support RPM (`/usr/share/sp11/fonts/sp11-console.pf2`, named by `GRUB_FONT`),
  since GRUB has no text-scale setting and sizes its character cell from the loaded font. The live menu is Fedora's
  own with the device tree and the kernel arguments added to each entry. Installed menu order: Fedora entries,
  Windows Boot Manager, UEFI Firmware Settings. [`docs/fedora-media.md`](../fedora-media.md).
- Windows dual-boot: `/etc/grub.d/29_sp11_windows` finds the ESP holding `EFI/Microsoft/Boot/bootmgfw.efi` (a
  separate Windows ESP is fine) and adds a chainload entry. Fedora's aarch64 GRUB image lacks the `chain` module,
  and Fedora's os-prober cannot find Windows on aarch64, so the module is copied from `grub2-efi-aa64-modules` to
  `/boot/grub2/arm64-efi/`; it is loadable because Secure Boot is off. [`docs/hardware.md`](../hardware.md).
- SELinux, sandboxes and CPU frequency: the kernel uses Fedora's configuration, so SELinux runs enforcing with
  Fedora's targeted policy and unprivileged user namespaces (Flatpak's bwrap, browser sandboxes) work as on any
  Fedora. Fedora builds `scmi-cpufreq` as a module that does not load on its own on these laptops; the support RPM
  loads it (`/usr/lib/modules-load.d/sp11-scmi-cpufreq.conf`, Fedora's documented fix).
  [`docs/kernel.md`](../kernel.md).
- Bluetooth address: ooaklee's helper sets the controller address byte-reversed. The RPM build fixes the octet
  order, so Linux uses the address Windows reports for the built-in radio, which the shared pairings depend on.
  [`docs/hardware.md`](../hardware.md).
- Audio: ooaklee's FullIO v19c topology and UCM, with the UCM device matcher extended to the 5G SKU and the
  internal microphone's gain (`UCM_MIC_GAIN`, +16 dB) inserted into the UCM Mic device, which v19c leaves at the
  0 dB reset value. [`docs/hardware.md`](../hardware.md).
- Pen: `sp11-iptsd` links against Fedora's `spdlog`, `fmt` and `inih`; the ISO build installs whichever of them the
  live image lacks (`LIVE_EXTRA_PKGS`; Workstation lacks `spdlog`) and refuses RPMs with unmet dependencies.
  [`docs/fedora-media.md`](../fedora-media.md).
- Stock kernel: the ISO build replaces the live root's stock kernel packages with the SP11 build of the same
  packages, so the installer installs only the SP11 kernel. The support RPM's dnf repository override hides the
  stock ones (`kernel`, `kernel-core`, `kernel-modules*`, `kernel-uki-*`) in every configured repository, while
  SP11 kernel RPMs install from local files as they are ([`docs/guide/update.md`](update.md)).
  [`docs/fedora-media.md`](../fedora-media.md).
- Firmware: only the five files the Denali device tree requests (ADSP and CDSP images with their device-tree
  blobs, GPU zap shader), under the names it requests them by. [`docs/hardware.md`](../hardware.md).
- Initramfs: the live one carries only the GPU zap shader; the ADSP/CDSP firmware (about 24 MiB) and the Adreno
  microcode go into the installed system's initramfs. No rescue image: Fedora's rescue entry would name a
  device-tree directory that does not exist. [`docs/fedora-media.md`](../fedora-media.md).
- Live image: repacked as LZMA EROFS with the source image's file times (`mkfs.erofs --mkfs-time`), because `-T`
  alone stamps every file with the build time, which the installer then copies onto the installed system.
  [`docs/fedora-media.md`](../fedora-media.md).
- Sensors: the four RPMs of the stack are installed into the live root with their scriptlet effects applied by the
  build. The live session never starts them, since there is no FastRPC node while the ADSP is off; the installed
  system starts them on its first boot. [`docs/sensors.md`](../sensors.md).
- Cameras: the drivers and device-tree nodes are part of the SP11 patch set; libcamera is Fedora's own package,
  unmodified. [`docs/camera.md`](../camera.md).
- Hardware detection uses the built-in panel (WMI connection type internal) and the built-in Bluetooth radio, so an
  external monitor or a USB Bluetooth dongle does not change the result. [`docs/hardware.md`](../hardware.md).
- Tablet mode: mainline gives the Surface Pro 11 the Surface Aggregator's KIP cover switch, whose change event this
  firmware never sends, so the kernel always reported laptop mode. The last patch of the SP11 patch set registers
  the POS posture switch instead, which follows the keyboard: tablet mode while it is detached or folded back.
  GNOME then offers auto-rotation (with the sensors packages), and libinput switches the keyboard and touchpad off
  while the keyboard is folded back. [`docs/sensors.md`](../sensors.md).
