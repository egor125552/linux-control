#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

python3 - <<'PY'
from pathlib import Path
p=Path('argon_neural_v2/tract.py')
s=p.read_text()
s=s.replace("self.gamma=nn.Parameter(torch.ones(1,dim,1)*0.08)","self.gamma=nn.Parameter(torch.ones(1,dim,1)*0.1)")
if "ConditionedBlock=GenerativeBlock" not in s:
    s=s.replace("\nclass DeepVocalTract(nn.Module):","\n# Backward-compatible name for older architecture tests and tooling.\nConditionedBlock=GenerativeBlock\n\nclass DeepVocalTract(nn.Module):",1)
p.write_text(s)
PY

echo '=== COMPILE ==='
python3 -m py_compile argon_neural_v2/tract.py argon_neural_v2/critic.py argon_neural_v2/engine.py argon_neural_v2/train.py

echo '=== ALL AFFECTED TESTS ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest  tests.test_neural_v2_generative  tests.test_neural_v2_live_phase  tests.test_neural_v2_f0_learning  tests.test_neural_v2_review_fix  tests.test_neural_v2_safe_step -v

echo '=== REAL GENERATIVE STEP ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
import torch
from argon_core.audio import read_audio
from argon_neural_v2.engine import ArgonNeuralV2
from argon_neural_v2.train import perturb_timbre
from argon_neural_v2.losses import naturalness_loss

torch.set_num_threads(1)
x=read_audio('/srv/ARGON-VC/data/victor_source.wav',24000)[:12000][None]
content=perturb_timbre(x,24000,seed=42)
m=ArgonNeuralV2().train()
emb=torch.randn(1,m.speaker_dim,requires_grad=True)
params=list(m.parameters())+[emb]
opt=torch.optim.AdamW(params,lr=3e-5)
y,aux=m(x,speaker_embedding=emb,content_wav=content)
loss=naturalness_loss(y,x,24000)['total']+.015*aux['vq_loss']
assert torch.isfinite(loss)
opt.zero_grad(set_to_none=True);loss.backward()
gn=torch.nn.utils.clip_grad_norm_(params,1.2)
assert torch.isfinite(torch.as_tensor(gn))
opt.step()
print('GEN_STEP_OK',float(loss.detach()),float(gn))
print('PERTURB_DELTA',float((x-content).abs().mean()))
print('OUTPUT_RMS',float(y.detach().square().mean().sqrt()))
print('MODEL_PARAMS',sum(p.numel() for p in m.parameters()))
PY

echo '=== START CLEAN GENERATIVE TRAINING ==='
rm -f 'results/ARGON Neural 2 Generative.pt' 'results/ARGON Neural 2 Generative Latest.pt' 'results/ARGON Neural 2 generative.log'
systemctl start argon-neural-v2.service
sleep 5
systemctl is-active argon-neural-v2.service || true
systemctl --no-pager --full status argon-neural-v2.service | sed -n '1,65p' || true
echo '=== V1 ==='
systemctl is-active argon-neural-long.service || true
