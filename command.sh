#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
python3 - <<'PY'
from pathlib import Path
import subprocess,json
roots=[Path('data')]
rows=[]
seen=set()
for root in roots:
    for p in root.rglob('*'):
        if not p.is_file() or p.suffix.lower() not in {'.wav','.mp3','.m4a','.flac','.ogg','.opus','.aac'}:
            continue
        try:
            rp=p.resolve()
            key=(p.stat().st_size, p.name)
            # keep distinct paths only when contents may differ; exact duplicate target copies will be deduped later by hash
            out=subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(p)],text=True).strip()
            dur=float(out)
            rows.append((dur,p.stat().st_size,str(p)))
        except Exception as e:
            print('ERR',p,e)
rows.sort(reverse=True)
print('FILES',len(rows),'TOTAL_MINUTES',round(sum(x[0] for x in rows)/60,3))
for dur,size,p in rows:
    print(f'{dur/60:7.3f} min {size:10d} {p}')
PY
