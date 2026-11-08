#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== V1 MUST STAY ACTIVE ==='
systemctl is-active argon-neural-long.service || true

echo '=== LOSS SIGNATURES ==='
grep -n '^def ' argon_neural_v2/losses.py

echo '=== TRAIN INIT ==='
grep -nE 'ArgonNeuralV2\(|naturalness_loss|optimizer|AdamW|save\(|output|Latest|seed_speaker_checkpoint' argon_neural_v2/train.py | head -220

echo '=== ONE REAL TRAINING STEP ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
import torch
from argon_core.audio import read_audio
from argon_neural_v2.engine import ArgonNeuralV2
from argon_neural_v2.losses import naturalness_loss

torch.set_num_threads(1)
x=read_audio('/srv/ARGON-VC/data/victor_source.wav',24000)[:12000][None]
m=ArgonNeuralV2().train()
opt=torch.optim.AdamW(m.parameters(),lr=8e-5)
y,aux=m(x)
losses=naturalness_loss(y,x,24000)
loss=losses['total']+.015*aux['vq_loss']
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

echo '=== ARCHIVE EARLY OLD V2 OUTPUTS ==='
STAMP='before-review-fix'
mkdir -p "results/ARGON Neural 2 backup $STAMP"
for f in 'results/ARGON Neural 2 Long.pt' 'results/ARGON Neural 2 Long Latest.pt' 'results/ARGON Neural 2 long.log'; do
  if [ -f "$f" ]; then cp -f "$f" "results/ARGON Neural 2 backup $STAMP/"; fi
done
rm -f 'results/ARGON Neural 2 Long.pt' 'results/ARGON Neural 2 Long Latest.pt' 'results/ARGON Neural 2 long.log'

echo '=== START FIXED V2 ==='
systemctl start argon-neural-v2.service
sleep 4
systemctl --no-pager --full status argon-neural-v2.service | sed -n '1,70p' || true
echo '=== LOG ==='
tail -30 'results/ARGON Neural 2 long.log' 2>/dev/null || true

echo '=== V1 FINAL CHECK ==='
systemctl is-active argon-neural-long.service || true
