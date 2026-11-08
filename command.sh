#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
echo '=== SERVICES ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true
echo '=== STATUS ==='
systemctl --no-pager --full status argon-neural-v2.service | sed -n '1,85p' || true
echo '=== PROCESS ==='
PID=$(systemctl show -p MainPID --value argon-neural-v2.service)
ps -p "$PID" -o pid,etime,time,%cpu,%mem,rss,nlwp,stat,args || true
echo '=== CHILDREN ==='
ps -o pid,ppid,etime,%cpu,%mem,stat,args --ppid "$PID" || true
echo '=== LOG ==='
ls -lh 'results/ARGON Neural 2 generative.log' 2>/dev/null || true
tail -100 'results/ARGON Neural 2 generative.log' 2>/dev/null || true
echo '=== OUTPUTS ==='
ls -lh 'results/ARGON Neural 2 Generative.pt' 'results/ARGON Neural 2 Generative Latest.pt' 2>/dev/null || true
