#!/usr/bin/env bash
set -euo pipefail

echo '=== TRAINING BEFORE ==='
systemctl is-active argon-neural-long.service || true
PID=$(systemctl show -p MainPID --value argon-neural-long.service)
ps -p "$PID" -o pid,etime,%cpu,%mem,rss,stat,args || true

PUB='/srv/era-audio/argon-neural-quote'
mkdir -p "$PUB"
TEXT='Я сейчас вам покажу, откуда на Беларусь готовилось нападение.'

/srv/argon-tts-venv/bin/pip -q install gTTS
/srv/argon-tts-venv/bin/python - <<'PY'
from gtts import gTTS
text='Я сейчас вам покажу, откуда на Беларусь готовилось нападение.'
gTTS(text=text,lang='ru',slow=False).save('/srv/era-audio/argon-neural-quote/Исходная фраза обычным голосом.mp3')
print('GTTS_OK')
PY

ffmpeg -y -nostdin -loglevel error   -i "$PUB/Исходная фраза обычным голосом.mp3"   -ar 24000 -ac 1 "$PUB/Исходная фраза обычным голосом.wav"

cd /srv/ARGON-VC
for i in $(seq 1 20); do
  cp -f 'results/ARGON Neural Continuous 50000 Latest.pt' /tmp/argon-quote-latest.pt
  if /srv/era-audio/venv/bin/python - <<'PY'
import torch
o=torch.load('/tmp/argon-quote-latest.pt',map_location='cpu',weights_only=True)
print('SNAPSHOT_EPOCH',int(o.get('metadata',{}).get('epoch',0)))
assert int(o.get('metadata',{}).get('epoch',0))>0
PY
  then break; fi
  sleep 1
done

PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import json,torch
from argon_core.audio import read_audio,write_audio
from argon_core.neural_engine import ArgonSourceFilter

pub=Path('/srv/era-audio/argon-neural-quote')
src=pub/'Исходная фраза обычным голосом.wav'
model,meta=ArgonSourceFilter.load('/tmp/argon-quote-latest.pt','cpu')
x=read_audio(src,model.sample_rate)
with torch.inference_mode():
    y=model.convert(x[None])[0]
epoch=int(meta.get('epoch',0))
out=pub/f'ARGON результат эпоха {epoch}.wav'
write_audio(out,y,model.sample_rate)
sil=torch.zeros(int(.6*model.sample_rate))
ab=pub/f'Сравнение обычный голос и ARGON эпоха {epoch}.wav'
write_audio(ab,torch.cat([x,sil,y]),model.sample_rate)
print(json.dumps({
    'epoch':epoch,
    'best_epoch':meta.get('best_epoch'),
    'best_val':meta.get('best_val'),
    'duration':round(len(y)/model.sample_rate,3),
    'output':out.name,
    'comparison':ab.name
},ensure_ascii=False))
PY

echo '=== FILES ==='
find "$PUB" -maxdepth 1 -type f -printf '%f %s\n' | sort

echo '=== TRAINING AFTER ==='
systemctl is-active argon-neural-long.service || true
PID2=$(systemctl show -p MainPID --value argon-neural-long.service)
ps -p "$PID2" -o pid,etime,%cpu,%mem,rss,stat,args || true
tail -3 '/srv/ARGON-VC/results/ARGON Neural continuous.log' || true
