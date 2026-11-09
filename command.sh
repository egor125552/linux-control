#!/usr/bin/env bash
set -euo pipefail
ROOT='/srv/Zombie Horror Game/Зимний прототип'
python3 - <<'PY'
from pathlib import Path
from urllib.parse import quote
import urllib.request,ssl,hashlib
root=Path('/srv/Zombie Horror Game/Зимний прототип')
files=sorted((root/'audio/voices/game').glob('Сцена 7 *.mp3'))
ctx=ssl._create_unverified_context()
bad=[]
for i,p in enumerate(files,1):
    url='https://169-58-224-216.sslip.io/winter/audio/voices/'+quote(p.name)
    try:
        with urllib.request.urlopen(url,context=ctx,timeout=20) as r:
            b=r.read(); code=r.status
    except Exception as e:
        bad.append((p.name,'HTTP',str(e)));continue
    lh=hashlib.sha256(p.read_bytes()).hexdigest()
    rh=hashlib.sha256(b).hexdigest()
    if code!=200 or lh!=rh:bad.append((p.name,code,lh,rh))
print('PUBLIC_CHECKED',len(files),'BAD',len(bad))
for x in bad:print('BAD',x)
if len(files)!=52 or bad:raise SystemExit(1)
PY
cd "$ROOT"
node --test tests/file-manifest.test.mjs tests/file-manifest-server.test.mjs 'tests/Аудио сборка.test.mjs'
echo '=== FINAL ==='
python3 - <<'PY'
import json
p='/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 7 ручные дубли 9 ноября 2026/Итог нарезки.json'
r=json.load(open(p,encoding='utf-8'))
print('validation_ok',r['validation_ok'])
print('total',r['total_clips'])
print('game_mp3',r['game_mp3_count'])
print('source_unchanged',all(v['unchanged'] for v in r['source_hashes'].values()))
PY
