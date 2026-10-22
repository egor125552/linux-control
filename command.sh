#!/usr/bin/env bash
set -Eeuo pipefail
echo "=== PATCH REMOTE DESKTOP COMMANDER TO OFFICIAL STABLE 0.3.0 ==="
script="$(mktemp /tmp/rdc-v030.XXXXXXXX.sh)"
trap 'rm -f "$script"' EXIT
curl -fLsS --connect-timeout 10 --max-time 45 \
  "https://raw.githubusercontent.com/egor125552/linux-control/c94b00e0460c9704bd1026ac071b85f439d34779/desktop-commander-v030-update.sh" -o "$script"
bash "$script"
