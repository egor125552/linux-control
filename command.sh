#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== V1 ==='
systemctl is-active argon-neural-long.service || true

echo '=== V2 TEST FILES ==='
find tests -maxdepth 1 -type f | grep -Ei 'v2|neural2|neural_v2' | sort || true

echo '=== REVIEW FIX TEST ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest tests.test_neural_v2_review_fix -v

echo '=== DISCOVER EXISTING V2 TESTS ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest discover -s tests -p '*v2*.py' -v || true

echo '=== ONE REAL TRAINING STEP ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
import torch
from argon_core.audio import read_audio
from argon_neural_v2.engine import ArgonNeuralV2
from argon_neural_v2.losses import natural_voice_loss

torch.set_num_threads(1)
x=read_audio('/srv/ARGON-VC/data/victor_source.wav',24000)[:12000][None]
m=ArgonNeuralV2().train()
opt=torch.optim.AdamW(m.parameters(),lr=8e-5)
y,aux=m(x)
loss=natural_voice_loss(y,x,24000)['total']+.015*aux['vq_loss']
assert torch.isfinite(loss)
opt.zero_grad(set_to_none=True)
loss.backward()
gn=torch.nn.utils.clip_grad_norm_(m.parameters(),2.0)
assert torch.isfinite(torch.as_tensor(gn))
opt.step()
print('TRAIN_STEP_OK',float(loss.detach()),float(gn))
print('OUTPUT_RMS',float(y.detach().square().mean().sqrt()))
print('LOG_FILTER_RANGE',float(aux['log_filter'].detach().min()),float(aux['log_filter'].detach().max()))
PY

echo '=== TRAIN INIT / SAVE ==='
grep -nE 'ArgonNeuralV2\(|ArgonNeuralV2\.load|load\(|torch\.load|output|Latest|seed_speaker_checkpoint|save\(' argon_neural_v2/train.py | head -180 || true

echo '=== RUN SCRIPT ==='
cat run-argon-neural-v2.sh || true

echo '=== V2 STOPPED AS EXPECTED ==='
systemctl is-active argon-neural-v2.service || true
