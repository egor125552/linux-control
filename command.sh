#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== TRAINING ==='
systemctl is-active argon-neural-long.service || true
ps -eo pid,etime,%cpu,%mem,args | grep 'argon_core.neural_continue' | grep -v grep || true

for f in   argon_core/source.py   argon_core/bottleneck.py   argon_core/filter.py   argon_core/losses.py   argon_core/neural_engine.py   argon_core/neural_features.py   argon_core/neural_longtrain.py   argon_core/neural_continue.py
do
  echo "===== $f ====="
  cat "$f"
done
