#!/usr/bin/bash
# Step 1: read this machine's identity from Windows (WSL interop) and validate it against the build's regexes.
# Output: build/hardware.env. Re-run with FORCE=1 to re-detect.
. "$(dirname "$0")/lib.sh"

# ps_lines CMD — every non-empty output line of a PowerShell command. Never fails: an empty result is
# reported by validate() with a message.
ps_lines() {
  powershell.exe -NoProfile -NonInteractive -Command "$1" 2>/dev/null | tr -d '\r' | sed 's/[[:space:]]*$//' | sed '/^$/d' || true
}
ps_query() { ps_lines "$1" | head -1 || true; }

# Regex self-test against the known SKU strings of this device family. The build never guesses:
# if a regex stops matching the 5G SKU the build fails here.
self_test() {
  local s ok=1
  for s in "Microsoft Surface Pro with 5G, 11th Edition" "Microsoft Surface Pro, 11th Edition"; do
    [[ $s =~ $SP11_PRODUCT_REGEX ]] || { warn "SP11_PRODUCT_REGEX does not match '$s'"; ok=0; }
  done
  for s in Surface_Pro_with_5G_11th_Edition_2077 Surface_Pro_11th_Edition_2076 Surface_Pro_11th_Edition_For_Business_2085; do
    [[ $s =~ $SP11_SKU_REGEX ]] || { warn "SP11_SKU_REGEX does not match '$s'"; ok=0; }
  done
  for s in "Microsoft Corporation-Surface-Microsoft Surface Pro with 5G, 11th Edition" \
           "Microsoft Corporation-Surface-Microsoft Surface Pro, 11th Edition"; do
    printf '%s\n' "$s" | grep -Eq "$UCM_SP11_REGEX" || { warn "UCM_SP11_REGEX does not match '$s'"; ok=0; }
  done
  [ "$ok" = 1 ] || die "regex self-test failed; fix sp11.conf"
  log "regex self-test passed (5G and non-5G SKUs)"
}

validate() {
  [[ $SP11_PRODUCT =~ $SP11_PRODUCT_REGEX ]] || die "unsupported product name '$SP11_PRODUCT'"
  [[ $SP11_SKU =~ $SP11_SKU_REGEX ]] || die "unsupported SKU '$SP11_SKU'"
  [[ $SP11_CPU == *X1E80100* ]] || die "unsupported SoC '$SP11_CPU' (only Snapdragon X Elite X1E80100 is supported)"
  [ "$SP11_PANEL_VENDOR" = SDC ] || die "panel vendor '$SP11_PANEL_VENDOR' is not Samsung (SDC); only the OLED variant is supported"
  [[ $SP11_BT_MAC =~ ^([0-9A-F]{2}:){5}[0-9A-F]{2}$ ]] || die "invalid Bluetooth address '$SP11_BT_MAC' (set SP11_BT_MAC=XX:XX:XX:XX:XX:XX)"
  [[ $SP11_BT_MAC != 00:00:00:00:* ]] || die "placeholder Bluetooth address '$SP11_BT_MAC'"
  printf '%s\n' "$SP11_UCM_DMI_INFO" | grep -Eq "$UCM_SP11_REGEX" \
    || die "UCM_SP11_REGEX does not match this machine's DMI string '$SP11_UCM_DMI_INFO'"
}

self_test

if [ -f "$HARDWARE_ENV" ] && [ "${FORCE:-0}" != 1 ]; then
  load_hardware; validate
  log "using existing $HARDWARE_ENV: $SP11_PRODUCT / $SP11_SKU / DTB $SP11_DTB_SELECTED"
  exit 0
fi

command -v powershell.exe >/dev/null 2>&1 \
  || die "powershell.exe unavailable. Create $HARDWARE_ENV by hand (see README) or run inside WSL with interop enabled."

log "querying Windows for SMBIOS, panel and Bluetooth identity"
SP11_PRODUCT=$(ps_query '(Get-CimInstance Win32_ComputerSystem).Model')
SP11_SKU=$(ps_query '(Get-CimInstance Win32_ComputerSystem).SystemSKUNumber')
SP11_FAMILY=$(ps_query '(Get-CimInstance Win32_ComputerSystem).SystemFamily')
SP11_BOARD_VENDOR=$(ps_query '(Get-CimInstance Win32_BaseBoard).Manufacturer')
SP11_BOARD_NAME=$(ps_query '(Get-CimInstance Win32_BaseBoard).Product')
SP11_CPU=$(ps_query '(Get-CimInstance Win32_Processor | Select-Object -First 1).Name')
SP11_BIOS=$(ps_query '(Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion')
# Panels as "<vendor> <VideoOutputTechnology>"; 2147483648 (D3DKMDT_VOT_INTERNAL) is the built-in panel, so
# an external display attached during detection is never mistaken for it.
PANELS=$(ps_lines '$conn = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams; Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID | ForEach-Object { $m = $_; $c = $conn | Where-Object { $_.InstanceName -eq $m.InstanceName } | Select-Object -First 1; ([System.Text.Encoding]::ASCII.GetString($m.ManufacturerName) -replace "\0","") + " " + $c.VideoOutputTechnology }')
SP11_PANEL_VENDOR=$(printf '%s\n' "$PANELS" | awk '$2 == 2147483648 { print $1; exit }')
[ -n "$SP11_PANEL_VENDOR" ] || SP11_PANEL_VENDOR=$(printf '%s\n' "$PANELS" | awk 'NR == 1 { print $1 }')
if [ -z "$SP11_BT_MAC" ]; then
  # Address of the built-in radio (DEVPKEY_Bluetooth_RadioAddress on the Bluetooth-class device); a USB dongle
  # would show up as a second radio under USB\ and is skipped. The PAN adapter's MAC is only a fallback.
  RADIOS=$(ps_lines 'Get-PnpDevice -Class Bluetooth -PresentOnly | ForEach-Object { $p = Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName "{a92f26ca-eda7-4b1d-9db2-27b68aa5a2eb} 1" -ErrorAction SilentlyContinue; if ($p -and $p.Data) { "{0:X12} {1}" -f [uint64]$p.Data, $_.InstanceId } }')
  SP11_BT_MAC=$(printf '%s\n' "$RADIOS" | awk '$2 !~ /^USB\\/ { print $1; exit }' | sed 's/../&:/g; s/:$//')
  if [ -z "$SP11_BT_MAC" ]; then
    warn "no built-in Bluetooth radio found via PnP (radios: ${RADIOS:-none}); falling back to the PAN adapter"
    SP11_BT_MAC=$(ps_query '(Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "Bluetooth Device \(Personal Area Network\)" } | Select-Object -First 1).MacAddress')
  fi
fi
SP11_BT_MAC=$(printf '%s' "$SP11_BT_MAC" | tr 'a-f-' 'A-F:')
SP11_UCM_DMI_INFO="${SP11_BOARD_VENDOR}-${SP11_FAMILY}-${SP11_BOARD_NAME}"
SP11_DTB_SELECTED="$SP11_DTB"

validate

cat > "$HARDWARE_ENV" <<ENV
# Generated by scripts/05-detect-hardware.sh on $(date -u +%FT%TZ)
SP11_PRODUCT="$SP11_PRODUCT"
SP11_SKU="$SP11_SKU"
SP11_FAMILY="$SP11_FAMILY"
SP11_BOARD_VENDOR="$SP11_BOARD_VENDOR"
SP11_BOARD_NAME="$SP11_BOARD_NAME"
SP11_CPU="$SP11_CPU"
SP11_BIOS="$SP11_BIOS"
SP11_PANEL_VENDOR="$SP11_PANEL_VENDOR"
SP11_BT_MAC="$SP11_BT_MAC"
SP11_UCM_DMI_INFO="$SP11_UCM_DMI_INFO"
SP11_DTB_SELECTED="$SP11_DTB_SELECTED"
ENV
chmod 0600 "$HARDWARE_ENV"
log "product: $SP11_PRODUCT"
log "SKU:     $SP11_SKU"
log "SoC:     $SP11_CPU"
log "panels:  $(printf '%s' "$PANELS" | tr '\n' ';')"
log "panel:   $SP11_PANEL_VENDOR (OLED) -> DTB $SP11_DTB_SELECTED"
log "BT MAC:  $SP11_BT_MAC"
log "wrote $HARDWARE_ENV"
