#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
sleep 20
echo '=== ACTIVE ==='
systemctl is-active argon-neural-long.service || true
systemctl --no-pager --full status argon-neural-long.service | sed -n '1,45p' || true
echo '=== PROCESS COUNT ==='
ps -eo args | grep 'argon_core.neural_longtrain' | grep -v grep | wc -l || true
echo '=== LOG ==='
tail -120 'results/ARGON Neural long.log' 2>/dev/null || true
echo '=== CHECKPOINTS ==='
ls -lh 'results/ARGON Neural Long 1000.pt' 'results/ARGON Neural Long 1000 Latest.pt' 2>/dev/null || true
