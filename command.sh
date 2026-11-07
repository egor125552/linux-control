#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import hashlib,subprocess,re,json

root=Path('/srv/Zombie Horror Game/Зимний прототип/scene')
allowed=('Александр','Виктор','Учёный 1','Учёный 2','Диктор','Бандит','Бандиты','Незнакомый')
exts={'.wav','.mp3','.m4a','.flac','.ogg','.opus','.aac'}
candidates=[Path('/srv/ARGON-VC/data/ARGON uploads/Экспериментальный голос.mp3')]

if root.exists():
    for p in root.rglob('*'):
        if not p.is_file() or p.suffix.lower() not in exts: continue
        parts=p.parts
        if any('Готовые MP3'==x for x in parts): continue
        if any(x in allowed for x in parts):
            candidates.append(p)

# Add standalone clean speech references, but reserve two files for honest transfer tests.
for p in Path('/srv/ARGON-VC/data').rglob('*'):
    if not p.is_file() or p.suffix.lower() not in exts: continue
    if p.name in {'Экспериментальный голос.mp3','victor_source.wav','Учёный 2 пробная реплика.wav'}: continue
    s=str(p).lower()
    if any(k in s for k in ('александр','alexander','профиль')):
        candidates.append(p)

unique=[];seen={}
for p in candidates:
    if not p.exists() or p.stat().st_size<20000:continue
    h=hashlib.sha1()
    with p.open('rb') as f:
        while True:
            b=f.read(1024*1024)
            if not b:break
            h.update(b)
    key=(p.stat().st_size,h.hexdigest())
    if key in seen:continue
    seen[key]=p
    try:
        dur=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(p)],text=True).strip())
    except Exception:
        continue
    if .25 <= dur <= 1800:
        unique.append((p,dur))

manifest=Path('models/ARGON Neural corpus.txt');manifest.parent.mkdir(parents=True,exist_ok=True)
manifest.write_text('\n'.join(str(p) for p,d in unique)+'\n')
by={}
for p,d in unique:
    who='experimental' if p.name=='Экспериментальный голос.mp3' else next((x for x in allowed if x in p.parts),'other')
    by[who]=by.get(who,0)+d
print('UNIQUE_FILES',len(unique))
print('TOTAL_MINUTES',round(sum(d for p,d in unique)/60,3))
for k,v in sorted(by.items(),key=lambda kv:-kv[1]):
    print('SPEAKER',k,'MINUTES',round(v/60,3))
print('MANIFEST',manifest)
print('FIRST_FILES')
for p,d in unique[:25]:
    print(round(d,2),p)
PY
