#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
sleep 60
echo '=== ACTIVE ==='
systemctl is-active argon-neural-base.service || true
systemctl --no-pager --full status argon-neural-base.service | sed -n '1,45p' || true
echo '=== LOG ==='
tail -100 'results/ARGON Neural base.log' 2>/dev/null || true
echo '=== CHECKPOINT ==='
ls -lh 'results/ARGON Neural Base.pt' 2>/dev/null || true
