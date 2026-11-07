#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== WAIT FOR EPOCH 60 ==='
while true; do
  EPOCH=$(grep 'ARGON_LONG_EPOCH' 'results/ARGON Neural long.log' | tail -1 | sed -n 's/.*"epoch": \([0-9][0-9]*\).*/\1/p')
  EPOCH=${EPOCH:-0}
  echo CURRENT_EPOCH=$EPOCH
  if [ "$EPOCH" -ge 60 ]; then break; fi
  sleep 1
done

echo '=== WAIT FOR SAVED EPOCH 60 CHECKPOINT ==='
while true; do
  SAVED=$(/srv/era-audio/venv/bin/python - <<'PY'
import torch
p='results/ARGON Neural Long 1000 Latest.pt'
try:
    o=torch.load(p,map_location='cpu',weights_only=True)
    print(int(o.get('metadata',{}).get('epoch',0)))
except Exception:
    print(0)
PY
)
  echo SAVED_EPOCH=$SAVED
  if [ "$SAVED" -ge 60 ]; then break; fi
  sleep 1
done

systemctl stop argon-neural-long.service
sleep 1

echo '=== STOPPED ==='
systemctl is-active argon-neural-long.service || true
tail -5 'results/ARGON Neural long.log' || true

mkdir -p '/srv/era-audio/argon-neural-long'
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import json,torch
from argon_core.audio import read_audio,write_audio
from argon_core.neural_engine import ArgonSourceFilter
from argon_core.corpus import classify_speaker,duration

root=Path('/srv/ARGON-VC')
checkpoint=root/'results/ARGON Neural Long 1000 Latest.pt'
model,meta=ArgonSourceFilter.load(checkpoint,'cpu')
epoch=int(meta.get('epoch',0))

manifest=root/'models/ARGON Neural all voices.txt'
candidates=[]
for line in manifest.read_text().splitlines():
    p=Path(line)
    if classify_speaker(p)!='victor':
        continue
    d=duration(p)
    if 1.2 <= d <= 3.5:
        candidates.append((abs(d-2.2),d,p))
if not candidates:
    src=root/'data/victor_source.wav'
else:
    _,_,src=sorted(candidates,key=lambda x:x[0])[0]

x=read_audio(src,model.sample_rate)
if len(x)>int(3.5*model.sample_rate):
    x=x[:int(3.5*model.sample_rate)]
with torch.inference_mode():
    y=model.convert(x[None])[0]

pub=Path('/srv/era-audio/argon-neural-long')
out=pub/f'Короткая фраза эпоха {epoch}.wav'
orig=pub/'Исходная короткая фраза.wav'
write_audio(orig,x,model.sample_rate)
write_audio(out,y,model.sample_rate)
print(json.dumps({
    'epoch':epoch,
    'source':str(src),
    'duration':round(len(y)/model.sample_rate,3),
    'output':str(out),
    'original':str(orig)
},ensure_ascii=False))
PY

echo '=== FILES ==='
find '/srv/era-audio/argon-neural-long' -maxdepth 1 -type f -printf '%f %s\n' | sort

echo '=== HTTP ==='
curl -ksS -o /dev/null -w 'converted %{http_code} %{size_download}\n' 'https://169-58-224-216.sslip.io/era-audio/argon-neural-long/%D0%9A%D0%BE%D1%80%D0%BE%D1%82%D0%BA%D0%B0%D1%8F%20%D1%84%D1%80%D0%B0%D0%B7%D0%B0%20%D1%8D%D0%BF%D0%BE%D1%85%D0%B0%2060.wav'
curl -ksS -o /dev/null -w 'original %{http_code} %{size_download}\n' 'https://169-58-224-216.sslip.io/era-audio/argon-neural-long/%D0%98%D1%81%D1%85%D0%BE%D0%B4%D0%BD%D0%B0%D1%8F%20%D0%BA%D0%BE%D1%80%D0%BE%D1%82%D0%BA%D0%B0%D1%8F%20%D1%84%D1%80%D0%B0%D0%B7%D0%B0.wav'
