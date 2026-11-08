#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
echo '=== V2 FILES ==='
find argon_neural_v2 -maxdepth 2 -type f -name '*.py' -printf '%p\n' | sort
echo '=== IMPORTS ==='
grep -R '^from \|^import ' argon_neural_v2 --include='*.py' | sort
echo '=== TRAINING STILL ACTIVE ==='
systemctl is-active argon-neural-long.service || true
