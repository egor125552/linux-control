#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== SERVICES ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true

echo '=== WAIT FOR FIRST GENERATIVE CHECKPOINT ==='
for i in $(seq 1 90); do
  if [ -f 'results/ARGON Neural 2 Generative.pt' ]; then break; fi
  sleep 1
done

echo '=== LOG ==='
tail -30 'results/ARGON Neural 2 generative.log' 2>/dev/null || true

if [ ! -f 'results/ARGON Neural 2 Generative.pt' ]; then
  echo 'NO_CHECKPOINT_YET'
  exit 2
fi

echo '=== META ==='
/srv/era-audio/venv/bin/python - <<'PY'
import torch
o=torch.load('results/ARGON Neural 2 Generative.pt',map_location='cpu',weights_only=True)
m=o.get('metadata',{})
print('epoch',m.get('epoch'),'best_epoch',m.get('best_epoch'),'best_val',m.get('best_val'),'seed_stats',m.get('seed_stats'))
PY

echo '=== RENDER CONTROL ==='
PUB='/srv/era-audio/argon-neural-v2-generative'
mkdir -p "$PUB"
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import torch,json
from argon_core.audio import read_audio,write_audio
from argon_neural_v2.engine import ArgonNeuralV2
root=Path('/srv/ARGON-VC');pub=Path('/srv/era-audio/argon-neural-v2-generative')
m,meta=ArgonNeuralV2.load(root/'results/ARGON Neural 2 Generative.pt','cpu')
spk=meta.get('speaker_table') or {}
x=read_audio(root/'data/victor_source.wav',24000)[:72000]
emb=torch.tensor(spk['alexander'],dtype=torch.float32)[None]
with torch.inference_mode():
    y,_=m(x[None],speaker_embedding=emb,shift_pitch=True,content_wav=x[None])
write_audio(pub/f'Виктор в Александр генеративная эпоха {meta.get("epoch")}.wav',y[0],24000)
write_audio(pub/'Исходник Виктор.wav',x,24000)
sil=torch.zeros(int(.55*24000))
write_audio(pub/f'A-B исходник и генеративная эпоха {meta.get("epoch")}.wav',torch.cat([x,sil,y[0]]),24000)
print(json.dumps({'epoch':meta.get('epoch'),'best_val':meta.get('best_val')},ensure_ascii=False))
PY

echo '=== HTTP ==='
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
from urllib.parse import quote
import subprocess
base='https://169-58-224-216.sslip.io/era-audio/argon-neural-v2-generative/'
for p in sorted(Path('/srv/era-audio/argon-neural-v2-generative').glob('*.wav')):
    u=base+quote(p.name)
    r=subprocess.run(['curl','-ksS','-o','/dev/null','-w','%{http_code} %{size_download}',u],capture_output=True,text=True)
    print(r.stdout,p.name)
    print('URL',u)
PY
