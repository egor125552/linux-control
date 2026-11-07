#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
mkdir -p '/srv/era-audio/argon-neural-base'

PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import json,torch
import torch.nn.functional as F
from argon_core.audio import read_audio,write_audio
from argon_core.neural_engine import ArgonSourceFilter
from argon_core.losses import anti_robot_loss

root=Path('/srv/ARGON-VC')
pub=Path('/srv/era-audio/argon-neural-base')
model,meta=ArgonSourceFilter.load(root/'results/ARGON Neural Base.pt','cpu')
sr=model.sample_rate
target=read_audio(root/'data/ARGON uploads/Экспериментальный голос.mp3',sr)
hold=meta.get('target_holdout_ranges_seconds') or []
print('META',json.dumps({
 'unique_files':meta.get('unique_files'),
 'speech_windows':meta.get('speech_windows'),
 'speakers':meta.get('speakers'),
 'holdout':hold,
 'history':meta.get('history'),
 'no_random_source_noise':meta.get('no_random_source_noise')
},ensure_ascii=False))

def metrics(x):
    rms=float(x.square().mean().sqrt());peak=float(x.abs().max());clip=float((x.abs()>.98).float().mean())
    n=2048
    if len(x)<n:x=F.pad(x,(0,n-len(x)))
    win=torch.hann_window(n)
    mag=torch.stft(x,n_fft=n,hop_length=480,win_length=n,window=win,return_complex=True).abs().square()
    freqs=torch.linspace(0,sr/2,mag.shape[0])
    def band(lo,hi):
        m=(freqs>=lo)&(freqs<hi)
        return float(mag[m].mean()) if m.any() else 0.
    low=band(80,4000)
    return {'rms':rms,'peak':peak,'clip':clip,
            'hf4_8':band(4000,8000)/(low+1e-9),
            'hf8_12':band(8000,12000)/(low+1e-9)}

rows=[]
sil=torch.zeros(round(.6*sr))
for i,(a,b) in enumerate(hold,1):
    orig=target[round(a*sr):round(b*sr)]
    with torch.inference_mode(): out=model.convert(orig[None])[0]
    write_audio(pub/f'Контроль {i} оригинал.wav',orig,sr)
    write_audio(pub/f'Контроль {i} ARGON Base.wav',out,sr)
    write_audio(pub/f'Контроль {i} A-B оригинал затем ARGON Base.wav',torch.cat([orig,sil,out]),sr)
    n=min(len(orig),len(out));loss=anti_robot_loss(out[:n][None],orig[:n][None],sr)
    rows.append({'label':f'Контроль {i}','original':metrics(orig),'argon':metrics(out),
                 'spectral':float(loss['spectral']),'subband':float(loss['subband']),
                 'envelope':float(loss['envelope'])})

for label,src in [
    ('Виктор',root/'data/victor_source.wav'),
    ('Учёный',root/'data/Учёный 2 пробная реплика.wav')
]:
    x=read_audio(src,sr)
    with torch.inference_mode():out=model.convert(x[None])[0]
    write_audio(pub/f'{label} ARGON Base.wav',out,sr)
    rows.append({'label':label,'source':metrics(x),'argon':metrics(out)})

(root/'results/ARGON Neural Base metrics.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
print('METRICS',json.dumps(rows,ensure_ascii=False,indent=2))
print('FILES')
for p in sorted(pub.glob('*.wav')):print(p.name,p.stat().st_size)
PY

echo '=== TESTS ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest  tests.test_neural_source tests.test_neural_bottleneck tests.test_neural_filter tests.test_neural_losses  tests.test_neural_engine tests.test_neural_split tests.test_neural_real_aperiodic tests.test_neural_rvq_stability -v
