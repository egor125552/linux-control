#!/usr/bin/env bash
# Only affects Remote Desktop Commander on the already-authorized VPS.
# This runs under the existing self-hosted Linux Control GitHub Actions runner.
set -uo pipefail
unit=desktop-commander-remote.service
echo '=== RECOVER REMOTE DESKTOP COMMANDER: 2026-10-22 ==='
echo 'HOST:'; hostname; date -Is
echo 'RUNNER USER:'; id -un
echo 'BEFORE:'
systemctl show "$unit" --no-pager -p LoadState -p ActiveState -p SubState -p ExecMainPID -p NRestarts -p Result || true
echo 'GITHUB RUNNER:'
systemctl is-active actions.runner.egor125552-linux-control.vmi3528738.service || true
if ! systemctl cat "$unit" >/dev/null 2>&1; then
  echo 'BLOCKED: RDC service not installed, no guessed installation attempted.'
  systemctl list-unit-files --type=service --no-legend | grep -Ei 'desktop|commander|remote' || true
  exit 41
fi
echo 'RESTARTING RDC SERVICE'
systemctl reset-failed "$unit" || true
if ! timeout 45s systemctl restart "$unit"; then
  echo 'ERROR: systemctl restart failed'
  systemctl show "$unit" --no-pager -p ActiveState -p SubState -p Result -p ExecMainStatus || true
  exit 42
fi
sleep 8
echo 'AFTER:'
systemctl show "$unit" --no-pager -p ActiveState -p SubState -p ExecMainPID -p Result -p ExecMainStatus -p ActiveEnterTimestamp
if ! systemctl is-active --quiet "$unit"; then
  echo 'ERROR: RDC is not active after restart'
  exit 43
fi
echo 'RDC SERVICE ACTIVE. Verify connection via Remote Desktop Commander before test run.'
echo '=== END RECOVERY ==='
