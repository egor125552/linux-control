#!/usr/bin/env bash
set -Eeuo pipefail
echo '=== UPDATE REMOTE DESKTOP COMMANDER SESSION FIX ==='
echo 'Host:'; hostname
script="$(mktemp /tmp/rdc-patch.XXXXXXXX.sh)"
trap 'rm -f "$script"' EXIT
curl --fail --silent --show-error --location --connect-timeout 10 --max-time 45 \
  "https://raw.githubusercontent.com/egor125552/linux-control/ac78e7a5ac2a2bcd10f2d6321ebb0d8a51912d35/desktop-commander-version-fix.sh" \
  -o "$script"
bash "$script"
