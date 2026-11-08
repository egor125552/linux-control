#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
echo '=== V1 ==='
systemctl is-active argon-neural-long.service || true
echo '=== V2 ==='
systemctl is-active argon-neural-v2.service || true
for f in argon_neural_v2/content.py argon_neural_v2/postfilter.py argon_neural_v2/losses.py argon_neural_v2/critic.py; do
  echo "===== $f ====="
  cat "$f"
done
