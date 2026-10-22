#!/usr/bin/env bash
set -euo pipefail
echo '=== RESTART REMOTE DESKTOP COMMANDER ==='
hostname
systemctl restart desktop-commander-remote.service
sleep 4
systemctl show desktop-commander-remote.service --no-pager -p ActiveState -p SubState -p Result -p ExecMainPID
echo '=== END ==='
