#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== V2 STATUS ==='
systemctl is-active argon-neural-v2.service || true
systemctl --no-pager --full status argon-neural-v2.service | sed -n '1,70p' || true
tail -80 'results/ARGON Neural 2 long.log' 2>/dev/null || true

for f in   argon_neural_v2/content.py   argon_neural_v2/features.py   argon_neural_v2/losses.py   argon_neural_v2/critic.py   argon_neural_v2/train.py
do
  echo "===== $f ====="
  cat "$f"
done

echo '=== CURRENT FOUR FILE HEADS ==='
for f in argon_neural_v2/source.py argon_neural_v2/tract.py argon_neural_v2/postfilter.py argon_neural_v2/engine.py; do
  echo "===== $f ====="
  sed -n '1,260p' "$f"
done

echo '=== SERVICE ==='
systemctl cat argon-neural-v2.service || true
