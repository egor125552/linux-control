#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
sleep 25

echo '=== SERVICES ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true

echo '=== V2 LOG AFTER F0 RESTART ==='
tail -25 'results/ARGON Neural 2 long.log' 2>/dev/null || true

echo '=== HTTP A B FILES ==='
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
from urllib.parse import quote
import subprocess
base='https://169-58-224-216.sslip.io/era-audio/argon-neural-v2-ab/'
root=Path('/srv/era-audio/argon-neural-v2-ab')
for p in sorted(root.glob('*.wav')):
    url=base+quote(p.name)
    r=subprocess.run(['curl','-ksS','-o','/dev/null','-w','%{http_code} %{size_download}',url],capture_output=True,text=True)
    print(r.stdout,p.name)
    print('URL',url)
PY
