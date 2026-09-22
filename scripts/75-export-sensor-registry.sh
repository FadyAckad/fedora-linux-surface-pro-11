#!/usr/bin/bash
# Export this machine's Snapdragon Sensor Core registry from Windows for scripts/45-build-sensors-rpms.sh: the
# pre-parsed sensor registry the ADSP's sensor framework wrote under Windows (per-sensor platform data and this
# unit's calibration; without it the framework rebuilds its registry from the configuration on every boot) and
# Surface's calibration overrides.
# Both live under C:\Windows\System32\drivers\DriverData\Qualcomm\fastRPC, readable only with elevation, so this
# runs in WSL and triggers ONE Windows UAC prompt. Always exports afresh: Windows updates calibration in place.
# Output (per unit, git-ignored, keep private): build/sensors/registry/ and build/sensors/config-overrides/.
. "$(dirname "$0")/lib.sh"
require_cmd powershell.exe wslpath

OUT="$BUILD_DIR/sensors"; REG="$OUT/registry"; OVR="$OUT/config-overrides"
WINTMP_WSL="$WINDOWS_ROOT/Users/$(powershell.exe -NoProfile -Command '$env:USERNAME' | tr -d '\r')/AppData/Local/Temp"
[ -d "$WINTMP_WSL" ] || die "cannot locate the Windows temp directory ($WINTMP_WSL; the profile directory is assumed to be named after \$env:USERNAME)"
WINTMP_WIN=$(wslpath -w "$WINTMP_WSL")
DEST_WSL="$WINTMP_WSL/sp11-sensor-registry"; DEST_WIN="$WINTMP_WIN\\sp11-sensor-registry"
PS1_WSL="$WINTMP_WSL/sp11-sensor-registry.ps1"; PS1_WIN="$WINTMP_WIN\\sp11-sensor-registry.ps1"
SRC_WIN='C:\Windows\System32\drivers\DriverData\Qualcomm\fastRPC'
rm -rf "$DEST_WSL" "$PS1_WSL"

# robocopy exit codes below 8 mean success (1 = files copied); the overrides directory may not exist on every
# Windows build, so only the registry copy decides the exit status.
cat > "$PS1_WSL" <<PS
\$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path '$DEST_WIN' | Out-Null
robocopy '$SRC_WIN\\persist\\sensors\\registry' '$DEST_WIN\\registry' /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
\$rc1 = \$LASTEXITCODE
robocopy '$SRC_WIN\\vendor\\etc\\sensors\\config' '$DEST_WIN\\config-overrides' /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
\$rc2 = \$LASTEXITCODE
"registry=\$rc1 overrides=\$rc2" | Out-File -Encoding ascii '$DEST_WIN\\robocopy.rc'
if (\$rc1 -ge 8) { exit \$rc1 } else { exit 0 }
PS
log "copying $SRC_WIN\\persist\\sensors\\registry (accept the UAC prompt)"
# A cancelled UAC prompt makes Start-Process fail without a process object; that must not pass as exit 0. The
# status is caught on the pipeline itself: under errexit and pipefail a $PIPESTATUS check after it is never reached.
rc=0
powershell.exe -NoProfile -Command "try { \$p = Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$PS1_WIN' } catch { Write-Host \$_; exit 99 }; if (-not \$p) { exit 98 }; exit \$p.ExitCode" 2>&1 | tr -d '\r' | sed 's/^/  powershell: /' >&2 || rc=$?
rm -f "$PS1_WSL"
[ "$rc" -eq 0 ] || die "elevation was refused or the copy failed (exit $rc; UAC prompt cancelled? $(tr -d '\r' < "$DEST_WSL/robocopy.rc" 2>/dev/null))"
log "robocopy: $(tr -d '\r' < "$DEST_WSL/robocopy.rc" 2>/dev/null || echo 'no status file')"
for f in registry/registry/sns_reg_config registry/registry/sns_secure_database.bin; do
  [ -s "$DEST_WSL/$f" ] || die "the export lacks $f; the Windows sensor stack has not written its registry, or the copy failed"
done

rm -rf "$REG" "$OVR"; mkdir -p "$OUT"
cp -a "$DEST_WSL/registry/registry" "$REG"
# Windows keeps the framework's two bookkeeping files one level up; they travel with the export, and step 45 moves
# them to the payload's registry-parent/, from where they are served beside the registry copy.
for f in parsed_file_list.csv sns_reg_version; do [ -f "$DEST_WSL/registry/$f" ] && cp -a "$DEST_WSL/registry/$f" "$REG/$f"; done
if [ -d "$DEST_WSL/config-overrides" ]; then cp -a "$DEST_WSL/config-overrides" "$OVR"; else mkdir -p "$OVR"; warn "no vendor\\etc\\sensors\\config on this Windows installation; no calibration overrides"; fi
rm -rf "$DEST_WSL"
find "$OUT" -type d -exec chmod 0700 {} + ; find "$OUT" -type f -exec chmod 0600 {} +
log "registry: $(find "$REG" -type f | wc -l) files (entries plus the two parent-directory files), $(stat -c %s "$REG/sns_reg_config") bytes sns_reg_config, $(stat -c %s "$REG/sns_secure_database.bin") bytes sns_secure_database.bin"
log "overrides: $(find "$OVR" -type f | wc -l) files"
log "next: scripts/45-build-sensors-rpms.sh"
