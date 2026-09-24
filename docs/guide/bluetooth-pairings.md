# Bluetooth pairings shared with Windows

Sharing the Flex Keyboard and Slim Pen 2 bonds between Windows and Fedora. The key formats and the converter are
described in [`docs/hardware.md`](../hardware.md).

A BLE device keeps one bond per host address, and Linux uses the same controller address as Windows,
so importing the Windows pairing keys lets both systems use the keyboard and pen without pairing again.
In WSL:

```bash
scripts/70-export-bt-pairings.sh
```

The script asks for elevation once (UAC; the keys are readable only elevated), converts the Flex
Keyboard and Slim Pen 2 bonds (`BT_PAIRING_USB_IDS` in `sp11.conf`) and writes
`build/out/sp11-bt-pairings.tar.gz`. Copy the tarball to Fedora and run:

```bash
tar -xzf sp11-bt-pairings.tar.gz && sudo /usr/libexec/sp11/sp11-bt-import-pairings
```

Existing Linux pairings for these devices are backed up under `/var/lib/sp11/`. Pairing a device again in
either system invalidates the other system's bond; export and import again afterwards. The tarball
contains secret keys: do not share it.
