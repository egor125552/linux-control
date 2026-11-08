#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== BEFORE ==='
systemctl is-active argon-neural-long.service || true
PID=$(systemctl show -p MainPID --value argon-neural-long.service)
ps -p "$PID" -o pid,etime,%cpu,%mem,rss,stat,args || true

mkdir -p '/srv/era-audio/argon-neural-live'
TMP='/tmp/argon-live-latest.pt'

# Copy a completed saved checkpoint while training continues.
for i in $(seq 1 20); do
  if cp -f 'results/ARGON Neural Continuous 50000 Latest.pt' "$TMP" 2>/dev/null; then
    if /srv/era-audio/venv/bin/python - "$TMP" <<'PY'
import sys,torch
try:
    o=torch.load(sys.argv[1],map_location='cpu',weights_only=True)
    print(int(o.get('metadata',{}).get('epoch',0)))
except Exception:
    raise SystemExit(1)
PY
    then break; fi
  fi
  sleep 1
done

PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import json,torch
from argon_core.audio import read_audio,write_audio
from argon_core.neural_engine import ArgonSourceFilter

root=Path('/srv/ARGON-VC')
pub=Path('/srv/era-audio/argon-neural-live')
src=root/'Зимний прототип/scene/Проверка лаборатории 4 ноября 2026/Виктор/Виктор лаборатория 002.wav'
if not src.exists():
    src=root/'data/victor_source.wav'

x=read_audio(src,24000)
if len(x)>int(3.5*24000):
    x=x[:int(3.5*24000)]

items=[
    ('Лучший',root/'results/ARGON Neural Continuous 50000.pt'),
    ('Свежий',Path('/tmp/argon-live-latest.pt')),
]
rows=[]
for label,ck in items:
    m,meta=ArgonSourceFilter.load(ck,'cpu')
    with torch.inference_mode():
        y=m.convert(x[None])[0]
    epoch=int(meta.get('epoch',0))
    out=pub/f'{label} результат эпоха {epoch}.wav'
    write_audio(out,y,m.sample_rate)
    rows.append({'label':label,'epoch':epoch,'best_epoch':meta.get('best_epoch'),'best_val':meta.get('best_val'),'file':out.name})

write_audio(pub/'Исходная фраза Виктора.wav',x,24000)

# One A-B-C file for easiest listening: original, best, latest.
sil=torch.zeros(int(.55*24000))
best_model,bmeta=ArgonSourceFilter.load(root/'results/ARGON Neural Continuous 50000.pt','cpu')
latest_model,lmeta=ArgonSourceFilter.load('/tmp/argon-live-latest.pt','cpu')
with torch.inference_mode():
    yb=best_model.convert(x[None])[0]
    yl=latest_model.convert(x[None])[0]
abc=torch.cat([x,sil,yb,sil,yl])
abc_name=f'Сравнение оригинал лучший {int(bmeta.get("epoch",0))} свежий {int(lmeta.get("epoch",0))}.wav'
write_audio(pub/abc_name,abc,24000)
print(json.dumps({'source':str(src),'duration':round(len(x)/24000,3),'results':rows,'comparison':abc_name},ensure_ascii=False))
PY

echo '=== PUBLIC FILES ==='
find '/srv/era-audio/argon-neural-live' -maxdepth 1 -type f -printf '%f %s\n' | sort

echo '=== AFTER ==='
systemctl is-active argon-neural-long.service || true
PID2=$(systemctl show -p MainPID --value argon-neural-long.service)
ps -p "$PID2" -o pid,etime,%cpu,%mem,rss,stat,args || true
tail -5 'results/ARGON Neural continuous.log' || true
