#!/usr/bin/bash
# Export this machine's Windows Bluetooth pairings for the Surface Pro Flex Keyboard and Slim Pen 2
# (selected by USB ID, BT_PAIRING_USB_IDS in sp11.conf) as BlueZ info files plus an import script, bundled for transfer to the installed Fedora.
# Runs in WSL. Triggers ONE Windows UAC prompt: the pairing keys are readable only with elevation.
# Always exports afresh: re-pairing in Windows rewrites the keys in place, so a cached hive would be stale.
. "$(dirname "$0")/lib.sh"
require_cmd python3 powershell.exe tar
python3 -c 'import hivex' 2>/dev/null || die "python3-hivex missing (run scripts/00-setup-host.sh)"
load_hardware

OUT="$BUILD_DIR/bt-pairings"; BUNDLE="$OUT_DIR/sp11-bt-pairings.tar.gz"
WINTMP_WSL="$WINDOWS_ROOT/Users/$(powershell.exe -NoProfile -Command '$env:USERNAME' | tr -d '\r')/AppData/Local/Temp"
[ -d "$WINTMP_WSL" ] || die "cannot locate the Windows temp directory under $WINDOWS_ROOT"
WINTMP_WIN=$(wslpath -w "$WINTMP_WSL")
HIVE_WIN="$WINTMP_WIN\\sp11-bthport-parameters.hiv"; HIVE_WSL="$WINTMP_WSL/sp11-bthport-parameters.hiv"
LOG_WIN="$WINTMP_WIN\\sp11-regsave.log"

mkdir -p "$OUT"; rm -rf "$OUT"/*:*
rm -f "$HIVE_WSL" "$OUT/bthport-parameters.hiv"
log "exporting HKLM\\SYSTEM\\CurrentControlSet\\Services\\BTHPORT\\Parameters (accept the UAC prompt)"
powershell.exe -NoProfile -Command "\$p = Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile','-Command',\"reg save 'HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters' '$HIVE_WIN' /y *> '$LOG_WIN'\"; exit \$p.ExitCode" >/dev/null 2>&1 \
  || die "elevation was refused or failed (UAC prompt cancelled?)"
[ -s "$HIVE_WSL" ] || die "reg save produced no file; log: $(tr -d '\r\0' < "$WINTMP_WSL/sp11-regsave.log" 2>/dev/null)"
mv -f "$HIVE_WSL" "$OUT/bthport-parameters.hiv"; rm -f "$WINTMP_WSL/sp11-regsave.log"
chmod 0600 "$OUT/bthport-parameters.hiv"

log "collecting device names and USB IDs from Windows PnP (no elevation)"
powershell.exe -NoProfile -Command "Get-PnpDevice | Where-Object { \$_.InstanceId -match '^BTH(LE|ENUM)\\\\DEV_' } | Select-Object FriendlyName,InstanceId,HardwareIds | ConvertTo-Json -Depth 3" \
  | tr -d '\r' > "$OUT/pnp-devices.json" || warn "PnP query failed; names will be missing"
# USB VID/PID live on the HID children (VID&02045E_PID&0C7A); merge them by device address.
powershell.exe -NoProfile -Command "Get-PnpDevice -Class HIDClass | Where-Object { \$_.InstanceId -match 'DEV_VID&02[0-9A-F]{4}_PID&[0-9A-F]{4}(_REV&[0-9A-F]{4})?_[0-9A-F]{12}' } | ForEach-Object { if (\$_.InstanceId -match 'DEV_(VID&02[0-9A-F]{4}_PID&[0-9A-F]{4}(?:_REV&[0-9A-F]{4})?)_([0-9A-F]{12})') { [PSCustomObject]@{ InstanceId = 'BTHLE\\DEV_' + \$Matches[2]; HardwareIds = @(\$Matches[1]) } } } | Sort-Object InstanceId -Unique | ConvertTo-Json" \
  | tr -d '\r' > "$OUT/pnp-hid.json" || true
python3 - "$OUT/pnp-devices.json" "$OUT/pnp-hid.json" "$OUT/meta.json" <<'PY'
import json, sys
def load(p):
    try:
        with open(p, encoding="utf-8-sig") as f: d = json.load(f)
    except Exception: return []
    return d if isinstance(d, list) else [d]
devs = load(sys.argv[1]); hid = load(sys.argv[2])
ids = {h["InstanceId"].split("DEV_")[1][:12].upper(): h["HardwareIds"] for h in hid if "InstanceId" in h}
for d in devs:
    mac = d["InstanceId"].split("DEV_")[1][:12].upper()
    if mac in ids: d["HardwareIds"] = list(d.get("HardwareIds") or []) + list(ids[mac])
json.dump(devs, open(sys.argv[3], "w"), indent=1)
PY

log "converting pairing keys for adapter $SP11_BT_MAC (devices: $BT_PAIRING_USB_IDS)"
usb_args=(); for id in $BT_PAIRING_USB_IDS; do usb_args+=(--only-usb "$id"); done
python3 "$SP11_ROOT/scripts/bt-pairings-from-hive.py" --adapter "$SP11_BT_MAC" --meta "$OUT/meta.json" \
  "${usb_args[@]}" "$OUT/bthport-parameters.hiv" "$OUT" | tee "$OUT/devices.txt"
install -m 0755 "$FILES_DIR/sp11-bt-import-pairings" "$OUT/sp11-bt-import-pairings"
rm -f "$BUNDLE"
( cd "$OUT" && tar -czf "$BUNDLE" --owner=0 --group=0 sp11-bt-import-pairings devices.txt ./*:* )
chmod 0600 "$BUNDLE"
log "bundle: $BUNDLE"
log "on Fedora: tar -xzf sp11-bt-pairings.tar.gz && sudo /usr/libexec/sp11/sp11-bt-import-pairings   (or sudo ./sp11-bt-import-pairings)"
