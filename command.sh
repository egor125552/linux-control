#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import json,torch
import torch.nn.functional as F
from argon_core.audio import read_audio,write_audio
from argon_core.losses import anti_robot_loss

sr=24000
pub=Path('/srv/era-audio/argon-neural')
pairs=[]
for i in range(1,5):
    o=pub/f'Контроль {i} оригинал.wav'
    y=pub/f'Контроль {i} ARGON Neural.wav'
    if o.exists() and y.exists(): pairs.append((f'Контроль {i}',o,y))
pairs += [
 ('Виктор',Path('data/victor_source.wav'),pub/'Виктор ARGON Neural.wav'),
 ('Учёный',Path('data/Учёный 2 пробная реплика.wav'),pub/'Учёный ARGON Neural.wav'),
]

def metrics(path):
    x=read_audio(path,sr)
    rms=float(x.square().mean().sqrt())
    peak=float(x.abs().max())
    clip=float((x.abs()>.98).float().mean())
    n=2048;hop=480
    if len(x)<n:x=F.pad(x,(0,n-len(x)))
    win=torch.hann_window(n)
    mag=torch.stft(x,n_fft=n,hop_length=hop,win_length=n,window=win,return_complex=True).abs().square()
    freqs=torch.linspace(0,sr/2,mag.shape[0])
    def band(lo,hi):
        m=(freqs>=lo)&(freqs<hi)
        return float(mag[m].mean()) if m.any() else 0.0
    low=band(80,4000); hi=band(4000,8000); top=band(8000,12000)
    return {'rms':rms,'peak':peak,'clip_fraction':clip,
            'hf_4_8_ratio':hi/(low+1e-9),'hf_8_12_ratio':top/(low+1e-9)}

rows=[]
sil=torch.zeros(int(.6*sr))
for label,orig,out in pairs:
    if not orig.exists() or not out.exists(): continue
    a=read_audio(orig,sr);b=read_audio(out,sr)
    n=min(len(a),len(b))
    losses=anti_robot_loss(b[:n][None],a[:n][None],sr)
    row={'label':label,'original':metrics(orig),'argon':metrics(out),
         'spectral':float(losses['spectral']),'subband':float(losses['subband']),
         'envelope':float(losses['envelope'])}
    rows.append(row)
    if label.startswith('Контроль'):
        ab=torch.cat([a,sil,b])
        write_audio(pub/f'{label} A-B оригинал затем ARGON.wav',ab,sr)

print(json.dumps(rows,ensure_ascii=False,indent=2))
print('FILES')
for p in sorted(pub.glob('*A-B*.wav')):
    print(p.name,p.stat().st_size)
PY
