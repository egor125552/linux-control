#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
echo '=== SERVICES ==='
systemctl --no-pager --full status argon-neural-base.service 2>/dev/null | sed -n '1,40p' || true
systemctl --no-pager --full status argon-neural-long.service 2>/dev/null | sed -n '1,60p' || true
echo '=== PROCESSES ==='
ps -eo pid,etime,%cpu,rss,stat,args | grep -E 'argon_core.neural_(pretrain|longtrain|train)|wavecodec' | grep -v grep || true
echo '=== FILES ==='
ls -lh results/'ARGON Neural'* 2>/dev/null || true
echo '=== LONG LOG ==='
tail -80 results/'ARGON Neural long.log' 2>/dev/null || true
