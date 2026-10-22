#!/usr/bin/env bash
set -Eeuo pipefail
echo "=== DESKTOP COMMANDER REMOTE 0.3.0 UPGRADE ==="
unit=desktop-commander-remote.service
pkg=/usr/local/lib/node_modules/@wonderwhy-er/desktop-commander/package.json
if ! systemctl cat "$unit" >/dev/null 2>&1;then echo "ERROR: remote service missing";exit 5;fi
if [[ ! -f "$pkg" ]];then echo "ERROR: package manifest missing";exit 6;fi
old="$(node -p "require('$pkg').version")"
echo "OLD_VERSION=$old"
echo "Installing official stable 0.3.0"
npm install --global --no-fund --no-audit --ignore-scripts @wonderwhy-er/desktop-commander@0.3.0
new="$(node -p "require('$pkg').version")"
echo "NEW_VERSION=$new"
if [[ "$new" != "0.3.0" ]];then echo "Unexpected installed version";exit 7;fi
systemctl restart "$unit"
sleep 5
echo "SERVICE_STATUS=$(systemctl is-active "$unit" || true)"
echo "RDC_ONLINE_PROTOCOL_STATUS:"
journalctl -u "$unit" --since "3 minutes ago" -o cat --no-pager |
  grep -Ei 'connected to remote mcp|authenticat|waiting for authorization|session invalid|device ready|device startup failed|token refresh' |
  sed -E 's/(Invalid Refresh Token:).*/\1 [REDACTED]/;s/(session invalid:).*/\1 [REDACTED]/' |
  tail -n 12 || true
echo "=== END RDC UPGRADE ==="
