#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
echo ACTIVE=$(systemctl is-active argon-neural-long.service || true)
echo '=== LAST EPOCHS ==='
tail -8 'results/ARGON Neural long.log' 2>/dev/null || true
echo '=== FILES ==='
stat -c '%y %s %n' 'results/ARGON Neural Long 1000.pt' 'results/ARGON Neural Long 1000 Latest.pt' 2>/dev/null || true
