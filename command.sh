#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
sleep 60
echo '=== SERVICES ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true
echo '=== V2 PROCESS ==='
PID=$(systemctl show -p MainPID --value argon-neural-v2.service)
ps -p "$PID" -o pid,etime,%cpu,%mem,rss,stat,args || true
echo '=== V2 LOG ==='
tail -100 'results/ARGON Neural 2 long.log' 2>/dev/null || true
echo '=== V2 OUTPUTS ==='
ls -lh 'results/ARGON Neural 2 Long.pt' 'results/ARGON Neural 2 Long Latest.pt' 2>/dev/null || true
