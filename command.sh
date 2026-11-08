#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
sleep 20
echo '=== SERVICES ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true
echo '=== PROCESSES ==='
ps -eo pid,etime,%cpu,%mem,rss,stat,args | grep -E 'argon_core.neural_continue|argon_neural_v2.train' | grep -v grep || true
echo '=== V2 LOG ==='
tail -80 'results/ARGON Neural 2 long.log' 2>/dev/null || true
echo '=== V2 CHECKPOINTS ==='
ls -lh 'results/ARGON Neural 2 Long.pt' 'results/ARGON Neural 2 Long Latest.pt' 2>/dev/null || true
