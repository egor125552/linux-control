#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
sleep 30
echo '=== SERVICE ==='
systemctl is-active argon-neural-base.service || true
systemctl --no-pager --full status argon-neural-base.service | sed -n '1,50p' || true
echo '=== PROCESS ==='
ps -eo pid,etime,%cpu,rss,stat,args | grep -E 'argon_core.neural_pretrain|ffmpeg .*ARGON|ffmpeg .*Зимний' | grep -v grep || true
echo '=== LOG ==='
tail -80 'results/ARGON Neural base.log' 2>/dev/null || true
echo '=== CHECKPOINT ==='
ls -lh 'results/ARGON Neural Base.pt' 2>/dev/null || true
