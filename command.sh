#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
sleep 25
echo '=== SERVICES ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true
echo '=== PROCESS TREE ==='
PID=$(systemctl show -p MainPID --value argon-neural-v2.service)
ps -o pid,ppid,etime,%cpu,%mem,stat,args --forest -p "$PID" --ppid "$PID" || true
echo '=== LOG ==='
tail -18 'results/ARGON Neural 2 long.log' 2>/dev/null || true
echo '=== NONFINITE MARKERS ==='
grep -n 'ARGON_V2_SKIP_NONFINITE' 'results/ARGON Neural 2 long.log' | tail -10 || true
