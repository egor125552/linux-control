#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
echo '=== ACTIVE ==='
systemctl is-active argon-neural-long.service || true
systemctl --no-pager --full status argon-neural-long.service | sed -n '1,45p' || true
echo '=== LOG ==='
tail -160 'results/ARGON Neural long.log' 2>/dev/null || true
echo '=== CHECKPOINTS ==='
ls -lh 'results/ARGON Neural Long 1000.pt' 'results/ARGON Neural Long 1000 Latest.pt' 2>/dev/null || true
