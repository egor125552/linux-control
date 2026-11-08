#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
PUB='/srv/era-audio/argon-neural-v2-generative'
mkdir -p "$PUB"

echo '=== TRAINING BEFORE ==='
systemctl is-active argon-neural-v2.service || true
tail -5 'results/ARGON Neural 2 generative.log' || true

cp -f 'results/ARGON Neural 2 Generative.pt' /tmp/argon-v2-generative-best.pt

PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import torch,json
from argon_core.audio import read_audio,write_audio
from argon_neural_v2.engine import ArgonNeuralV2

root=Path('/srv/ARGON-VC');pub=Path('/srv/era-audio/argon-neural-v2-generative')
m,meta=ArgonNeuralV2.load('/tmp/argon-v2-generative-best.pt','cpu')
spk=meta.get('speaker_table') or {}
def emb(name):
    return torch.tensor(spk[name],dtype=torch.float32)[None]

victor=read_audio(root/'data/victor_source.wav',24000)[:72000]
with torch.inference_mode():
    va,_=m(victor[None],speaker_embedding=emb('alexander'),shift_pitch=True,content_wav=victor[None])

exp=read_audio(root/'data/ARGON uploads/Экспериментальный голос.mp3',24000)
start=int(173.07*24000);exp=exp[start:start+72000]
with torch.inference_mode():
    ee,_=m(exp[None],speaker_embedding=emb('experimental'),shift_pitch=True,content_wav=exp[None])

epoch=int(meta.get('epoch',0))
sil=torch.zeros(int(.55*24000))
write_audio(pub/'Исходник Виктор.wav',victor,24000)
write_audio(pub/f'Виктор в Александр генеративная эпоха {epoch}.wav',va[0],24000)
write_audio(pub/f'A-B Виктор и Александр генеративная эпоха {epoch}.wav',torch.cat([victor,sil,va[0]]),24000)
write_audio(pub/'Исходник Экспериментальный.wav',exp,24000)
write_audio(pub/f'Экспериментальный генеративная эпоха {epoch}.wav',ee[0],24000)
write_audio(pub/f'A-B Экспериментальный генеративная эпоха {epoch}.wav',torch.cat([exp,sil,ee[0]]),24000)
print(json.dumps({'epoch':epoch,'best_val':meta.get('best_val'),'architecture':meta.get('architecture')},ensure_ascii=False))
PY

echo '=== FILES / URLS ==='
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
from urllib.parse import quote
import subprocess
root=Path('/srv/era-audio/argon-neural-v2-generative')
base='https://169-58-224-216.sslip.io/era-audio/argon-neural-v2-generative/'
for p in sorted(root.glob('*.wav')):
    u=base+quote(p.name)
    r=subprocess.run(['curl','-ksS','-o','/dev/null','-w','%{http_code} %{size_download}',u],capture_output=True,text=True)
    print(r.stdout,p.name)
    print('URL',u)
PY

echo '=== TRAINING AFTER ==='
systemctl is-active argon-neural-v2.service || true
tail -8 'results/ARGON Neural 2 generative.log' || true
