#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
PUB=/srv/era-audio/argon-neural-v2-vocos-test
cat > /tmp/render_vocos_variants.py <<'PY'
from pathlib import Path
import torch
from argon_core.audio import read_audio,write_audio
from argon_neural_v2.vocos_engine import ArgonStudioVC

pub=Path('/srv/era-audio/argon-neural-v2-vocos-test')
ck=torch.load(pub/'ARGON Vocos эксперимент.pt',map_location='cpu',weights_only=False)
m=ArgonStudioVC('cpu')
m.net.load_state_dict(ck['net'])
m.bank_keys=ck['bank_keys']
m.bank_mels=ck['bank_mels']
m.target_f0_median=float(ck['target_f0_median'])
m.net.eval()

src=read_audio('/srv/ARGON-VC/data/victor_source.wav',24000)[:72000]
sil=torch.zeros(int(.45*24000))
outs=[]
for blend,label in [(0.30,'мягкая'),(0.65,'средняя'),(0.90,'сильная')]:
    with torch.inference_mode():
        out=m.convert(src,blend)
    assert torch.isfinite(out).all()
    peak=float(out.abs().max())
    rms=float(out.square().mean().sqrt())
    write_audio(pub/f'ARGON Vocos {label}.wav',out,24000)
    write_audio(pub/f'A-B Виктор и ARGON Vocos {label}.wav',torch.cat([src,sil,out]),24000)
    print(label,'blend',blend,'samples',out.numel(),'peak',round(peak,5),'rms',round(rms,5))
    outs += [out,sil]
write_audio(pub/'Сравнение трёх вариантов ARGON Vocos.wav',torch.cat(outs[:-1]),24000)
PY
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python /tmp/render_vocos_variants.py
echo '=== FILES ==='
for f in "$PUB"/*.wav; do
  printf '%s ' "$(basename "$f")"
  ffprobe -v error -show_entries format=duration,size -of csv=p=0 "$f" || true
done
echo '=== URLS ==='
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
from urllib.parse import quote
root=Path('/srv/era-audio/argon-neural-v2-vocos-test')
base='https://169-58-224-216.sslip.io/era-audio/argon-neural-v2-vocos-test/'
for p in sorted(root.glob('*.wav')):
    if 'мягкая' in p.name or 'средняя' in p.name or 'сильная' in p.name or 'Сравнение трёх' in p.name:
        print('URL',base+quote(p.name))
PY
