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
cp -f "$SRC"/"ARGON Vocos "*чистая.wav "$TMP/" 2>/dev/null || true
cp -f "$SRC"/"A-B Виктор и ARGON Vocos "*чистая.wav "$TMP/" 2>/dev/null || true
cp -f "$SRC/Сравнение трёх чистых вариантов ARGON Vocos.wav" "$TMP/"
cd /tmp
rm -f "$OUT"
zip -r -9 "$OUT" "ARGON-Vocos-test" >/dev/null
ls -lh "$OUT"
python3 - <<'PY'
from pathlib import Path
from urllib.parse import quote
p=Path('/srv/era-audio/ARGON-Vocos-test.zip')
print('URL','https://169-58-224-216.sslip.io/era-audio/'+quote(p.name))
print('SIZE',p.stat().st_size)
PY
