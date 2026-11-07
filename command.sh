#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

python3 - <<'PY'
from pathlib import Path
p=Path('argon_core/neural_pretrain.py')
s=p.read_text()
if "from .corpus import classify_speaker" not in s:
    s=s.replace("from .losses import anti_robot_loss","from .losses import anti_robot_loss\nfrom .corpus import classify_speaker")
start=s.index("def speaker_name(path):")
end=s.index("\ndef dedupe_paths",start)
new="""def speaker_name(path):
    name=classify_speaker(path)
    if name:return name
    path=Path(path)
    return path.parent.name+' :: '+path.stem.split(' ')[0]
"""
s=s[:start]+new+s[end:]
p.write_text(s)
PY

/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
from collections import defaultdict
from argon_core.corpus import discover_voice_files,classify_speaker,duration
scene=Path('/srv/Zombie Horror Game/Зимний прототип/scene')
data=Path('/srv/ARGON-VC/data')
files=discover_voice_files(scene,data)
rows=[];by=defaultdict(float);count=defaultdict(int)
for p in files:
    d=duration(p)
    if d<.25 or d>1800:continue
    s=classify_speaker(p)
    rows.append((p,d,s));by[s]+=d;count[s]+=1
manifest=Path('models/ARGON Neural all voices.txt')
manifest.write_text('\n'.join(str(p) for p,d,s in rows)+'\n')
print('UNIQUE_FILES',len(rows))
print('TOTAL_MINUTES',round(sum(d for p,d,s in rows)/60,3))
for s in sorted(by,key=lambda k:-by[k]):
    print('SPEAKER',s,'FILES',count[s],'MINUTES',round(by[s]/60,3))
print('MANIFEST',manifest)
chosen=[];seen=set()
for p,d,s in rows:
    if s=='experimental' and s not in seen:
        chosen.append(p);seen.add(s)
for p,d,s in sorted(rows,key=lambda x:x[1]):
    if s not in seen and d>=.8:
        chosen.append(p);seen.add(s)
Path('models/ARGON Neural smoke voices.txt').write_text('\n'.join(str(x) for x in chosen)+'\n')
print('SMOKE_FILES',len(chosen),sorted(seen))
PY

echo '=== TESTS ==='
python3 -m py_compile argon_core/neural_pretrain.py argon_core/neural_longtrain.py argon_core/corpus.py
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest  tests.test_neural_corpus tests.test_neural_source tests.test_neural_rvq_stability -v

echo '=== LONG TRAIN SMOKE ==='
rm -f '/tmp/ARGON Long Smoke.pt' '/tmp/ARGON Long Smoke Latest.pt'
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -u -m argon_core.neural_longtrain  'models/ARGON Neural smoke voices.txt' 'results/ARGON Neural Base.pt' '/tmp/ARGON Long Smoke.pt'  --epochs 1 --steps 8 --threads 4 --crop .75 --lr 0.00005 --val-every 1 --patience-checks 2 --checkpoint-every 1
ls -lh '/tmp/ARGON Long Smoke.pt' '/tmp/ARGON Long Smoke Latest.pt'
