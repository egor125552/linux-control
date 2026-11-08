#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
SRC=/srv/era-audio/argon-neural-v2-vocos-test
OUT=/srv/era-audio/ARGON-Vocos-test.zip
TMP=/tmp/ARGON-Vocos-test
rm -rf "$TMP"
mkdir -p "$TMP"
cp -f argon_neural_v2/vocos_engine.py "$TMP/"
cp -f "$SRC/ARGON Vocos эксперимент.pt" "$TMP/"
cp -f "$SRC/Исходник Виктор.wav" "$TMP/"
cp -f "$SRC"/ARGON\ Vocos\ *чистая.wav "$TMP/" 2>/dev/null || true
cp -f "$SRC"/A-B\ Виктор\ и\ ARGON\ Vocos\ *чистая.wav "$TMP/" 2>/dev/null || true
cp -f "$SRC/Сравнение трёх чистых вариантов ARGON Vocos.wav" "$TMP/"
python3 - <<'PY'
from pathlib import Path
import zipfile
src=Path('/tmp/ARGON-Vocos-test')
out=Path('/srv/era-audio/ARGON-Vocos-test.zip')
if out.exists(): out.unlink()
with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in sorted(src.rglob('*')):
        if p.is_file():
            z.write(p,Path('ARGON-Vocos-test')/p.relative_to(src))
print('FILES',len([p for p in src.iterdir() if p.is_file()]))
print('SIZE',out.stat().st_size)
print('URL','https://169-58-224-216.sslip.io/era-audio/ARGON-Vocos-test.zip')
PY
