#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
echo '=== SERVICE ==='
systemctl is-active argon-neural-base.service || true
systemctl --no-pager --full status argon-neural-base.service | sed -n '1,45p' || true
echo '=== PROCESS ==='
ps -eo pid,etime,%cpu,rss,stat,args | grep 'argon_core.neural_pretrain' | grep -v grep || true
echo '=== LOG ==='
tail -60 'results/ARGON Neural base.log' 2>/dev/null || true
echo '=== CHECKPOINT ==='
ls -lh 'results/ARGON Neural Base.pt' 2>/dev/null || true
