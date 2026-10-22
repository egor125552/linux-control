#!/usr/bin/env bash
set -uo pipefail
echo "=== RDC CONNECTION DIAG $(date -Is) HOST=$(hostname) ==="
unit=desktop-commander-remote.service
echo "SERVICE STATE"
systemctl show "$unit" --no-pager -p ActiveState -p SubState -p NRestarts -p Result -p ExecMainPID -p ExecMainStatus -p EnvironmentFiles
echo "PROCESSES"
ps -C node -o pid,ppid,etimes,comm --no-headers | head -n 25 || true
echo "RECENT JOURNAL: sensitive tokens redacted"
journalctl -u "$unit" --since '45 minutes ago' -n 160 --no-pager -o short-iso 2>&1 |
  sed -E 's/(Bearer[[:space:]]+)[A-Za-z0-9._~+\/-]+/\1[REDACTED]/g;s/(token|apikey|api_key|secret|password|authorization|client_secret)([=:][[:space:]]*)[^[:space:]&,;]+/\1\2[REDACTED]/Ig;s#(https?://)[^/@[:space:]]+:[^/@[:space:]]+@#\1[REDACTED]@#g' |
  tail -n 160
echo "NETWORK TEST"
getent ahostsv4 mcp.desktopcommander.app | head -n 5 || true
for url in https://mcp.desktopcommander.app/ https://api.github.com/;do curl -sSL -o /dev/null --connect-timeout 5 --max-time 12 -w "HTTP=%{http_code} remote=%{remote_ip} ssl=%{ssl_verify_result}\n" "$url" || true;done
echo "SERVICE UNIT WITHOUT ENVIRONMENT/SECRETS"
systemctl show "$unit" -p Type -p Restart -p RestartUSec -p StartLimitBurst -p TimeoutStartUSec --no-pager
echo "=== END DIAG ==="
