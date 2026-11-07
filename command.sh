#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
echo ACTIVE=$(systemctl is-active argon-neural-base.service || true)
ps -eo pid,etime,%cpu,rss,stat,args | grep 'argon_core.neural_pretrain' | grep -v grep || true
echo '=== LOG ==='
tail -120 'results/ARGON Neural base.log' 2>/dev/null || true
echo '=== CHECKPOINT ==='
ls -lh 'results/ARGON Neural Base.pt' 2>/dev/null || true
