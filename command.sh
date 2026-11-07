#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
echo '=== PRETRAIN ==='
sed -n '1,260p' argon_core/neural_pretrain.py
echo '=== FINETUNE ==='
sed -n '1,260p' argon_core/neural_train.py
echo '=== LOSS ==='
sed -n '1,240p' argon_core/losses.py
echo '=== VOICE FOLDER COUNTS ==='
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
from collections import Counter
exts={'.wav','.mp3','.m4a','.flac','.ogg','.opus','.aac'}
root=Path('/srv/Zombie Horror Game/Зимний прототип/scene')
parents=Counter(); ancestors=Counter(); files=0
for p in root.rglob('*'):
    if not p.is_file() or p.suffix.lower() not in exts: continue
    files+=1
    parents[p.parent.name]+=1
    for part in p.relative_to(root).parts[:-1]:
        ancestors[part]+=1
print('TOTAL_AUDIO_FILES',files)
for name,count in parents.most_common(100):
    print('PARENT',count,name)
print('--- TOP ANCESTORS ---')
for name,count in ancestors.most_common(120):
    print('ANCESTOR',count,name)
PY
echo '=== CURRENT MANIFEST ==='
wc -l 'models/ARGON Neural corpus.txt' || true
