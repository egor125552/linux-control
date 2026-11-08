#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
sleep 30
echo '=== SERVICES ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true
echo '=== V2 STATUS ==='
systemctl --no-pager --full status argon-neural-v2.service | sed -n '1,55p' || true
echo '=== V2 LOG ==='
tail -60 'results/ARGON Neural 2 long.log' 2>/dev/null || true
echo '=== V2 OUTPUTS ==='
ls -lh 'results/ARGON Neural 2 Long.pt' 'results/ARGON Neural 2 Long Latest.pt' 2>/dev/null || true
