#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== SERVICES ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true
systemctl --no-pager --full status argon-neural-v2.service | sed -n '1,55p' || true

echo '=== LOG ==='
tail -40 'results/ARGON Neural 2 long.log' 2>/dev/null || true

for f in  argon_neural_v2/features.py  argon_neural_v2/source.py  argon_neural_v2/content.py  argon_neural_v2/tract.py  argon_neural_v2/postfilter.py  argon_neural_v2/losses.py  argon_neural_v2/critic.py  argon_neural_v2/engine.py  argon_neural_v2/train.py  run-argon-neural-v2.sh
do
 echo "===== $f ====="
 cat "$f"
done

echo '=== TESTS ==='
for f in tests/test_neural_v2*.py; do
 [ -e "$f" ] || continue
 echo "===== $f ====="
 cat "$f"
done
