#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import subprocess,re,hashlib
roots=[Path('/srv/Zombie Horror Game'),Path('/srv/ARGON-VC')]
exts={'.wav','.mp3','.m4a','.flac','.ogg','.opus','.aac'}
pat=re.compile(r'(voice|voices|dialog|dialogue|speech|replic|реплик|голос|виктор|александр|уч[её]н|bandit|диктор|scientist|victor|alexander)',re.I)
rows=[]
seen_hash={}
for root in roots:
    if not root.exists(): continue
    for p in root.rglob('*'):
        if not p.is_file() or p.suffix.lower() not in exts: continue
        if not pat.search(str(p)): continue
        try:
            st=p.stat()
            if st.st_size<20000: continue
            h=hashlib.sha1()
            with p.open('rb') as f:
                for _ in range(4):
                    b=f.read(1024*1024)
                    if not b: break
                    h.update(b)
            key=(st.st_size,h.hexdigest())
            dup=seen_hash.get(key)
            if dup:
                continue
            seen_hash[key]=str(p)
            d=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(p)],text=True).strip())
            rows.append((d,st.st_size,str(p)))
        except Exception:
            pass
rows.sort(reverse=True)
print('UNIQUE_MATCHED',len(rows),'TOTAL_MINUTES',round(sum(x[0] for x in rows)/60,3))
for d,s,p in rows[:300]:
    print(f'{d/60:7.3f} min {s:10d} {p}')
PY
