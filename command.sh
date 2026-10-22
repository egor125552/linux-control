#!/usr/bin/env bash
set -euo pipefail
echo '=== REMOTE DESKTOP COMMANDER SAFE DIAGNOSTICS ==='
echo "HOST=$(hostname)"
echo "TIME_UTC=$(date -u +%FT%TZ)"
unit=desktop-commander-remote.service
echo "ACTIVE=$(systemctl is-active "$unit" || true)"
echo "ENABLED=$(systemctl is-enabled "$unit" || true)"
systemctl show "$unit" --no-pager -p Result -p ExecMainCode -p ExecMainStatus -p NRestarts -p MainPID -p ActiveEnterTimestamp
pkg=/usr/local/lib/node_modules/@wonderwhy-er/desktop-commander/package.json
if [[ -f "$pkg" ]]; then
  echo "VERSION=$(node -p "require('$pkg').version")"
else
  echo 'VERSION=not-found'
fi
echo '=== SANITIZED RECENT JOURNAL EVENTS ==='
journalctl -u "$unit" --since '30 minutes ago' --no-pager -o cat |
  tail -n 150 |
  awk 'BEGIN{IGNORECASE=1}
    /connected to remote mcp/{print "EVENT=connected"}
    /waiting for authorization|authorization required/{print "EVENT=authorization_required"}
    /device code has expired/{print "EVENT=device_code_expired"}
    /invalid refresh token|session invalid|token refresh/{print "EVENT=token_or_session_error"}
    /device startup failed/{print "EVENT=startup_failed"}
    /error|exception|failed/{print "EVENT=other_error"}
  ' | tail -n 25
echo '=== END SAFE DIAGNOSTICS ==='
