#!/usr/bin/bash
# Run the whole pipeline. Every step is idempotent; FORCE=1 rebuilds a step's outputs.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
# 35 runs last: it needs the live root 50 extracts. On a tree that already has one, 30 runs it itself.
for s in 00-setup-host 05-detect-hardware 10-fetch-sources 20-build-kernel 30-build-support-rpm 40-build-iptsd-rpm 50-build-iso 35-verify-support-rpm; do
  printf '\n\033[1;32m==> %s\033[0m\n' "$s"
  "scripts/$s.sh"
done
