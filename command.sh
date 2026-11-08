#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== SERVICES ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true
systemctl --no-pager --full status argon-neural-v2.service | sed -n '1,80p' || true

echo '=== V2 FILE LIST ==='
find argon_neural_v2 -maxdepth 2 -type f -printf '%p %s\n' | sort

echo '=== V2 FILES ==='
for f in $(find argon_neural_v2 -maxdepth 1 -type f -name '*.py' | sort); do
  echo "===== $f ====="
  cat "$f"
done

echo '=== V2 TESTS ==='
find tests -maxdepth 1 -type f -iname '*v2*' -o -iname '*neural2*' 2>/dev/null | sort | while read f; do echo "===== $f ====="; cat "$f"; done

echo '=== SERVICE UNIT ==='
systemctl cat argon-neural-v2.service || true
