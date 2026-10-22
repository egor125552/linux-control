#!/usr/bin/env bash
set -u
echo '=== LINUX CONTROL: 2026-10-22 REMOTE DESKTOP DIAGNOSTICS ==='
echo 'System:'; hostname; date -Is; uname -sr
echo 'Runner:'; whoami; id -u; sudo -n id -u || true
echo 'Desktop Commander units:'
systemctl list-unit-files --type=service --no-legend | grep -Ei 'desktop.?commander|remote.?desktop|actions.runner' || true
for unit in desktop-commander-remote.service actions.runner.egor125552-linux-control.vmi3528738.service; do
  echo "--- $unit ---"
  systemctl show "$unit" --no-pager -p LoadState -p ActiveState -p SubState -p UnitFileState -p ExecMainPID -p NRestarts -p Result -p ActiveEnterTimestamp 2>&1 || true
done
echo 'Node runtimes:'; command -v node || true; node -v || true
echo 'Node processes (names only, no arguments):'
ps -C node -o pid,etime,comm --no-headers | head -n 20 || true
echo 'Network outbound HTTPS availability:'
curl -sS -L -o /dev/null --connect-timeout 5 --max-time 10 -w 'Github API HTTP=%{http_code} connection=%{time_connect}s\n' https://api.github.com/ || true
echo 'Existing AccessPilot checkout:'
if test -d /tmp/bulbam-accesspilot/Bulbam; then
  git -C /tmp/bulbam-accesspilot/Bulbam rev-parse --is-inside-work-tree || true
  git -C /tmp/bulbam-accesspilot/Bulbam branch --show-current || true
else echo 'No previous clone'; fi
echo '=== END DIAGNOSTICS ==='
