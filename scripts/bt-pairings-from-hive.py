#!/usr/bin/python3
"""Convert Windows Bluetooth pairing keys into BlueZ /var/lib/bluetooth info files.

Input: a registry hive exported with `reg save` of either
  HKLM\\SYSTEM\\CurrentControlSet\\Services\\BTHPORT\\Parameters  (contains a Keys subkey), or
  HKLM\\SYSTEM\\CurrentControlSet\\Services\\BTHPORT\\Parameters\\Keys, or
  a full SYSTEM hive (ControlSet00N resolved through Select\\Current).
Optional: a JSON list of Windows PnP devices for names and USB vendor/product IDs.

Windows stores, per adapter (subkey named by the adapter address without separators):
  <device-address> = REG_BINARY 16 bytes            classic BR/EDR link key
  <device-address>\\LTK, KeyLength, ERand, EDIV, IRK, AddressType, AuthReq   LE bond
BlueZ 5.x expects (doc/settings-storage.txt):
  [LongTermKey] Key (hex), Authenticated (MGMT key type: 0 legacy, 1 legacy+MITM, 2 SC, 3 SC+MITM),
                EncSize, EDiv (decimal), Rand (decimal uint64)
  [IdentityResolvingKey] Key (hex)
  [LinkKey] Key (hex), Type, PINLength
"""
import argparse
import json
import os
import re
import sys

import hivex

ESP_MAC = re.compile(r"^[0-9a-f]{12}$")
AUTHREQ_MITM = 0x04
AUTHREQ_SC = 0x08


def fmt_mac(raw):
    raw = raw.lower()
    return ":".join(raw[i:i + 2] for i in range(0, 12, 2)).upper()


def child(h, node, name):
    for c in h.node_children(node):
        if h.node_name(c).lower() == name.lower():
            return c
    return None


def value(h, node, name):
    for v in h.node_values(node):
        if h.value_key(v).lower() == name.lower():
            return h.value_value(v)  # (type, bytes)
    return None


def as_int(tb):
    if tb is None:
        return None
    return int.from_bytes(tb[1], "little")


def as_hex(tb):
    return tb[1].hex().upper() if tb else None


def find_keys_node(h):
    root = h.root()
    names = [h.node_name(c) for c in h.node_children(root)]
    if child(h, root, "Select") is not None:  # full SYSTEM hive
        sel = value(h, child(h, root, "Select"), "Current")
        cs = child(h, root, "ControlSet%03d" % as_int(sel))
        node = cs
        for part in ("Services", "BTHPORT", "Parameters", "Keys"):
            node = child(h, node, part)
            if node is None:
                sys.exit("hive has no %s under ControlSet%03d" % (part, as_int(sel)))
        return node
    if child(h, root, "Keys") is not None:  # Parameters hive
        return child(h, root, "Keys")
    if any(ESP_MAC.match(n.lower()) for n in names):  # Keys hive itself
        return root
    sys.exit("unrecognised hive layout; top-level keys: %s" % ", ".join(names))


def address_type(win_type, mac):
    # Windows: 0 public, 1 random. Sanity-check random against the static-address bit pattern.
    if win_type == 0:
        return "public"
    first = int(mac.split(":")[0], 16)
    return "static" if (first & 0xC0) == 0xC0 else "public"


def le_device(h, node, mac, meta):
    ltk = value(h, node, "LTK")
    if ltk is None:
        return None
    authreq = as_int(value(h, node, "AuthReq")) or 0
    sc = bool(authreq & AUTHREQ_SC)
    mitm = bool(authreq & AUTHREQ_MITM)
    key_type = (2 if sc else 0) + (1 if mitm else 0)
    ediv = as_int(value(h, node, "EDIV")) or 0
    rand = as_int(value(h, node, "ERand")) or 0
    enc = as_int(value(h, node, "KeyLength")) or 16
    irk = value(h, node, "IRK")
    win_type = as_int(value(h, node, "AddressType"))
    lines = ["[General]"]
    if meta.get("name"):
        lines.append("Name=%s" % meta["name"])
    lines += ["AddressType=%s" % address_type(win_type, mac),
              "SupportedTechnologies=LE;", "Trusted=true", "Blocked=false", ""]
    if meta.get("vid") is not None:
        lines += ["[DeviceID]", "Source=2", "Vendor=%d" % meta["vid"],
                  "Product=%d" % meta["pid"], "Version=%d" % meta.get("rev", 0), ""]
    if irk is not None and any(irk[1]):
        lines += ["[IdentityResolvingKey]", "Key=%s" % as_hex(irk), ""]
    lines += ["[LongTermKey]", "Key=%s" % as_hex(ltk), "Authenticated=%d" % key_type,
              "EncSize=%d" % enc, "EDiv=%d" % ediv, "Rand=%d" % rand, ""]
    desc = "LE, %s, %s%s" % ("Secure Connections" if sc else "legacy pairing",
                            "authenticated" if mitm else "unauthenticated",
                            ", IRK" if irk is not None else "")
    return "\n".join(lines), desc


def classic_device(tb, mac, meta):
    if tb is None or len(tb[1]) != 16:
        return None
    lines = ["[General]"]
    if meta.get("name"):
        lines.append("Name=%s" % meta["name"])
    lines += ["SupportedTechnologies=BR/EDR;", "Trusted=true", "Blocked=false", ""]
    lines += ["[LinkKey]", "Key=%s" % as_hex(tb), "Type=4", "PINLength=0", ""]
    return "\n".join(lines), "BR/EDR link key"


def load_meta(path):
    meta = {}
    if not path or not os.path.exists(path):
        return meta
    with open(path, encoding="utf-8-sig") as f:
        data = json.load(f)
    if isinstance(data, dict):
        data = [data]
    for d in data:
        inst = d.get("InstanceId", "")
        m = re.search(r"DEV_([0-9A-Fa-f]{12})", inst)
        if not m:
            continue
        mac = fmt_mac(m.group(1))
        entry = meta.setdefault(mac, {})
        entry.setdefault("name", d.get("FriendlyName") or d.get("Name"))
        for hid in d.get("HardwareIds") or []:
            vm = re.search(r"VID&(\d{2})([0-9A-Fa-f]{4})_PID&([0-9A-Fa-f]{4})(?:_REV&([0-9A-Fa-f]{4}))?", hid)
            if vm and "vid" not in entry:
                entry["vid"] = int(vm.group(2), 16)
                entry["pid"] = int(vm.group(3), 16)
                entry["rev"] = int(vm.group(4), 16) if vm.group(4) else 0
    return meta


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("hive")
    ap.add_argument("outdir")
    ap.add_argument("--meta", help="JSON from Get-PnpDevice (FriendlyName, InstanceId, HardwareIds)")
    ap.add_argument("--adapter", help="only this adapter address (AA:BB:CC:DD:EE:FF)")
    ap.add_argument("--only", action="append", default=[], help="only this device address (repeatable)")
    args = ap.parse_args()
    meta = load_meta(args.meta)
    only = {m.upper().replace("-", ":") for m in args.only}
    h = hivex.Hivex(args.hive)
    keys = find_keys_node(h)
    written = []
    for anode in h.node_children(keys):
        aname = h.node_name(anode).lower()
        if not ESP_MAC.match(aname):
            continue
        adapter = fmt_mac(aname)
        if args.adapter and adapter != args.adapter.upper():
            continue
        # LE bonds: subkeys named by device address
        for dnode in h.node_children(anode):
            dname = h.node_name(dnode).lower()
            if not ESP_MAC.match(dname):
                continue
            mac = fmt_mac(dname)
            if only and mac not in only:
                continue
            res = le_device(h, dnode, mac, meta.get(mac, {}))
            if res:
                written.append((adapter, mac, res))
        # classic link keys: values named by device address
        for v in h.node_values(anode):
            vname = h.value_key(v).lower()
            if not ESP_MAC.match(vname):
                continue
            mac = fmt_mac(vname)
            if only and mac not in only:
                continue
            if any(w[1] == mac and w[0] == adapter for w in written):
                continue  # dual-mode device already covered by its LE bond
            res = classic_device(h.value_value(v), mac, meta.get(mac, {}))
            if res:
                written.append((adapter, mac, res))
    if not written:
        sys.exit("no pairing keys found in the hive")
    for adapter, mac, (content, desc) in written:
        d = os.path.join(args.outdir, adapter, mac)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "info"), "w", encoding="utf-8") as f:
            f.write(content)
        os.chmod(os.path.join(d, "info"), 0o600)
        name = meta.get(mac, {}).get("name") or "(unnamed)"
        print("%s  %-32s %s  [%s]" % (mac, name, desc, adapter))


if __name__ == "__main__":
    main()
