#!/usr/bin/env bash
set -Eeuo pipefail
echo '=== DESKTOP COMMANDER REMOTE AGENT PATCH ==='
echo 'Host:'; hostname
unit=desktop-commander-remote.service
pkg=/usr/local/lib/node_modules/@wonderwhy-er/desktop-commander/package.json
if ! systemctl cat "$unit" >/dev/null 2>&1; then echo 'ABORT: service absent'; exit 2; fi
if [[ ! -f "$pkg" ]]; then echo 'ABORT: global npm package not in expected location'; exit 3; fi
echo "BEFORE_VERSION=$(node -p "require('$pkg').version")"
echo 'INSTALLING PINNED 0.2.52 SECURITY/SESSION FIX'
npm install --global --no-audit --no-fund --ignore-scripts @wonderwhy-er/desktop-commander@0.2.52
version="$(node -p "require('$pkg').version")"
echo "AFTER_VERSION=$version"
if [[ "$version" != "0.2.52" ]]; then echo 'ABORT: version did not match pin'; exit 4; fi
echo 'Restarting only remote agent (not VPN, Caddy or runner)'
systemctl restart "$unit"
sleep 5
echo "RDC_PROCESS=$(systemctl is-active "$unit" || true)"
echo 'The existing refresh token may still need one-time browser reauthorization.'
echo 'No device pairing code or authentication secret is printed into this public repository.'
echo '=== END REMOTE AGENT PATCH ==='
