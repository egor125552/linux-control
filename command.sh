#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
PUB=/srv/era-audio/argon-neural-v2-vocos-test
echo '=== ARGON VOCOS POST-RUN INSPECTION ==='
date
echo '--- module ---'
ls -lh argon_neural_v2/vocos_engine.py || true
python3 - <<'PY'
from pathlib import Path
p=Path('argon_neural_v2/vocos_engine.py')
print('exists',p.exists(),'bytes',p.stat().st_size if p.exists() else 0)
if p.exists():
    s=p.read_text(errors='replace')
    print('source_wav_in_module', 'source_wav' in s)
    print('vocos_decode', 'vocos.decode' in s)
    print('wavlm', 'WAVLM_BASE' in s)
PY
echo '--- outputs ---'
find "$PUB" -maxdepth 1 -type f -printf '%f %s bytes\n' 2>/dev/null | sort || true
echo '--- audio probes ---'
for f in "$PUB"/*.wav; do
  [ -e "$f" ] || continue
  ffprobe -v error -show_entries format=duration,size -of default=nw=1 "$f" || true
done
echo '--- model ---'
ls -lh "$PUB"/*.pt 2>/dev/null || true
echo '--- process/service ---'
ps -eo pid,etime,%cpu,%mem,cmd | grep -E 'run_argon_vocos|python.*vocos|WAVLM' | grep -v grep || true
systemctl is-active argon-neural-v2.service || true
echo '--- public URLs ---'
python3 - <<'PY'
from pathlib import Path
from urllib.parse import quote
root=Path('/srv/era-audio/argon-neural-v2-vocos-test')
base='https://169-58-224-216.sslip.io/era-audio/argon-neural-v2-vocos-test/'
for p in sorted(root.glob('*.wav')):
    print('URL',base+quote(p.name))
PY
