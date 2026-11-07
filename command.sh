#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== BEFORE ==='
ps -eo pid,etime,%cpu,rss,stat,args | grep 'argon_core.neural_pretrain' | grep -v grep || true

systemctl stop argon-neural-base.service 2>/dev/null || true
pkill -TERM -f 'python -u -m argon_core.neural_pretrain' 2>/dev/null || true
sleep 1
pkill -KILL -f 'python -u -m argon_core.neural_pretrain' 2>/dev/null || true
sleep 1

rm -f 'results/ARGON Neural Base.pt' 'results/ARGON Neural base.log' 'results/ARGON Neural base.pid'
systemctl start argon-neural-base.service
sleep 3

echo '=== AFTER ==='
ps -eo pid,etime,%cpu,rss,stat,args | grep 'argon_core.neural_pretrain' | grep -v grep || true
echo COUNT=$(ps -eo args | grep 'argon_core.neural_pretrain' | grep -v grep | wc -l)
echo '=== SERVICE ==='
systemctl --no-pager --full status argon-neural-base.service | sed -n '1,70p' || true
echo '=== LOG ==='
tail -30 'results/ARGON Neural base.log' 2>/dev/null || true
