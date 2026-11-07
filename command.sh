#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
PID=$(systemctl show -p MainPID --value argon-neural-long.service)
echo '=== CPU ==='
lscpu | grep -E 'Model name|CPU\(s\)|Thread|Core|Socket|MHz|BogoMIPS' || true
echo '=== SERVICE ==='
systemctl is-active argon-neural-long.service || true
ps -p "$PID" -o pid,etime,time,%cpu,%mem,rss,nlwp,psr,stat,cmd
echo '=== THREADS TOP ==='
ps -L -p "$PID" -o tid,psr,%cpu,stat,comm --sort=-%cpu | head -12
echo '=== LOAD ==='
uptime
echo '=== VMSTAT ==='
vmstat 1 5
echo '=== LATEST EPOCHS ==='
tail -40 'results/ARGON Neural long.log' || true
