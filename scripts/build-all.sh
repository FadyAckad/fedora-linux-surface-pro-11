#!/usr/bin/bash
# Run the whole pipeline. Every step is idempotent; FORCE=1 rebuilds a step's outputs.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
# 35 and 46 run last: they need the live root 50 extracts. On a tree that already has one, 30 and 45 run them
# themselves as well. 45 needs this unit's sensor registry export (scripts/75-export-sensor-registry.sh, once).
for s in 00-setup-host 05-detect-hardware 10-fetch-sources 20-build-kernel 30-build-support-rpm 40-build-iptsd-rpm 45-build-sensors-rpms 50-build-iso 35-verify-support-rpm 46-verify-sensors-rpms; do
  printf '\n\033[1;32m==> %s\033[0m\n' "$s"
  "scripts/$s.sh"
done
