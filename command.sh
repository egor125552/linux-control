#!/usr/bin/env bash
set -Eeuo pipefail
echo "=== SERVER ACCESSPILOT: SECOND PASS AFTER REGRESSION FIX ==="
echo "HOST=$(hostname)"
work="$(mktemp /tmp/vps-accesspilot.XXXXXXXX.sh)"
trap 'rm -f "$work"' EXIT
curl -fLsS --connect-timeout 10 --max-time 45 "https://raw.githubusercontent.com/egor125552/linux-control/36dd75f8aacb2bedcff9f92f59e46d2e0cee6293/server-accesspilot-resume.sh" -o "$work"
bash "$work"
