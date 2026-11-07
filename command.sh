#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== PROCESS ==='
ps -eo pid,etime,%cpu,rss,stat,args | grep -E 'argon_core.neural_train|ARGON Neural Experimental' | grep -v grep || true

echo '=== TRAIN LOG ==='
tail -n 80 'results/ARGON Neural обучение.txt' 2>/dev/null || true

echo '=== CHECKPOINT ==='
if [ -f 'results/ARGON Neural Experimental.pt' ]; then
  /srv/era-audio/venv/bin/python - <<'PY'
import torch,json
p='results/ARGON Neural Experimental.pt'
o=torch.load(p,map_location='cpu',weights_only=True)
m=o.get('metadata',{})
print(json.dumps({
  'best_epoch':m.get('best_epoch'),
  'best_val':m.get('best_val'),
  'train_phrases':m.get('train_phrases'),
  'holdout_ranges_seconds':m.get('holdout_ranges_seconds'),
  'history_tail':(m.get('history') or [])[-5:]
},ensure_ascii=False,indent=2))
PY

  mkdir -p '/srv/era-audio/argon-neural'
  cp -f 'results/ARGON Neural Experimental.pt' '/srv/era-audio/argon-neural/ARGON Neural Experimental.pt'

  /srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import torch
from argon_core.audio import read_audio,write_audio
from argon_core.neural_engine import ArgonSourceFilter

root=Path('/srv/ARGON-VC')
pub=Path('/srv/era-audio/argon-neural')
model,meta=ArgonSourceFilter.load(root/'results/ARGON Neural Experimental.pt','cpu')

tests=[
 ('Виктор ARGON Neural.wav',root/'data/victor_source.wav'),
 ('Учёный ARGON Neural.wav',root/'data/Учёный 2 пробная реплика.wav'),
]
for name,src in tests:
    x=read_audio(src,model.sample_rate)[None]
    with torch.inference_mode():
        y=model.convert(x,2026)[0]
    write_audio(pub/name,y,model.sample_rate)
    print('WROTE',name,'seconds',round(len(y)/model.sample_rate,3))

hold=root/'results/ARGON Neural Experimental'
if hold.exists():
    for p in sorted(hold.glob('Контроль * оригинал.wav')):
        x=read_audio(p,model.sample_rate)[None]
        with torch.inference_mode():
            y=model.convert(x,2026)[0]
        out=pub/(p.stem.replace(' оригинал',' ARGON Neural')+'.wav')
        write_audio(out,y,model.sample_rate)
        print('WROTE',out.name,'seconds',round(len(y)/model.sample_rate,3))
        pub_orig=pub/p.name
        pub_orig.write_bytes(p.read_bytes())
PY

  echo '=== PUBLIC FILES ==='
  find '/srv/era-audio/argon-neural' -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %s %f\n' | sort
else
  echo 'CHECKPOINT_NOT_READY'
fi
