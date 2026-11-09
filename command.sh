#!/usr/bin/env bash
set -euo pipefail
ROOT='/srv/Zombie Horror Game/Зимний прототип'
echo '=== MANIFEST CLIENT ==='
sed -n '1,260p' "$ROOT/js/update/file-manifest.js"
echo '=== LIVE MANIFEST PROBES ==='
for u in 'https://169-58-224-216.sslip.io/winter/file-manifest.json' 'https://169-58-224-216.sslip.io/winter/manifest.json' 'https://169-58-224-216.sslip.io/winter/api/file-manifest'; do
 code=$(curl -ksS -o /tmp/mf -w '%{http_code}' "$u")
 printf '%s %s ' "$code" "$u"
 python3 - <<'PY'
from pathlib import Path
p=Path('/tmp/mf')
b=p.read_bytes()
print('bytes',len(b),'scene7',b.count('Сцена 7'.encode()),'head',b[:80])
PY
done
echo '=== TEST EXPECTATIONS ==='
sed -n '1,260p' "$ROOT/tests/file-manifest-server.test.mjs"
