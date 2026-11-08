#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
sleep 45
echo '=== SERVICES ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true
echo '=== INSTANT CPU ==='
PID1=$(systemctl show -p MainPID --value argon-neural-long.service)
PID2=$(systemctl show -p MainPID --value argon-neural-v2.service)
ps -p "$PID1","$PID2" -o pid,etime,%cpu,%mem,rss,stat,args || true
echo '=== V2 LOG ==='
tail -100 'results/ARGON Neural 2 long.log' 2>/dev/null || true
echo '=== V2 CHECKPOINTS ==='
ls -lh 'results/ARGON Neural 2 Long.pt' 'results/ARGON Neural 2 Long Latest.pt' 2>/dev/null || true
