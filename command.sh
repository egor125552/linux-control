#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
echo '=== UNIVERSAL ACCESSPILOT TEST ON USER VPS ==='
echo 'Host:'; hostname
script="$(mktemp /tmp/accesspilot-vps.XXXXXXXX.sh)"
trap 'rm -f "$script"' EXIT
curl --fail --silent --show-error --location \
  --connect-timeout 10 --max-time 45 \
  "https://raw.githubusercontent.com/egor125552/linux-control/59c447f34ba3c4cfe4074dc85212932d88edc630/accesspilot-server-test.sh" \
  -o "$script"
bash "$script"
