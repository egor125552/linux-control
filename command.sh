#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== KEEP BOTH TRAINERS RUNNING DURING PATCH ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true
tail -5 'results/ARGON Neural 2 long.log' || true

python3 - <<'PY'
from pathlib import Path
p=Path('argon_neural_v2/engine.py')
s=p.read_text()
needle="""        if speaker_embedding is None:
            speaker_embedding=self.voice.expand(wav.shape[0],-1)
        elif speaker_embedding.ndim==1:
            speaker_embedding=speaker_embedding[None].expand(wav.shape[0],-1)

        # При конверсии переносим среднюю высоту голоса в регистр целевого диктора, сохраняя интонацию
        if shift_pitch:
            voiced = f0 > 20.0
"""
replacement="""        if speaker_embedding is None:
            speaker_embedding=self.voice.expand(wav.shape[0],-1)
        elif speaker_embedding.ndim==1:
            speaker_embedding=speaker_embedding[None].expand(wav.shape[0],-1)

        # Автоматически учим рабочий регистр каждого диктора даже при обычном обучении.
        voiced = f0 > 20.0
        pred_log_f0 = self.f0_proj(speaker_embedding).clamp(4.0, 5.8)
        if self.training and voiced.any():
            real_meds = []
            for b in range(f0.shape[0]):
                v = voiced[b]
                med = f0[b, v].median().clamp_min(50.0) if v.any() else torch.tensor(100.0, device=f0.device, dtype=f0.dtype)
                real_meds.append(torch.log(med))
            target_log_f0 = torch.stack(real_meds)[:, None]
            vq_loss = vq_loss + 0.25 * F.mse_loss(pred_log_f0, target_log_f0.detach())

        # При конверсии переносим среднюю высоту голоса в регистр целевого диктора, сохраняя интонацию
        if shift_pitch:
"""
if needle not in s:
    raise SystemExit('engine insertion point not found')
p.write_text(s.replace(needle,replacement,1))
PY

cat > tests/test_neural_v2_f0_learning.py <<'PY'
import unittest,torch
from argon_neural_v2.engine import ArgonNeuralV2

class F0LearningTests(unittest.TestCase):
    def test_f0_projection_receives_gradient_during_training(self):
        torch.manual_seed(7)
        m=ArgonNeuralV2().train()
        t=torch.arange(0,12000,dtype=torch.float32)/24000.0
        x=(0.08*torch.sin(2*torch.pi*145.0*t))[None]
        emb=torch.randn(1,m.speaker_dim,requires_grad=True)
        _,aux=m(x,speaker_embedding=emb,shift_pitch=False)
        loss=aux['vq_loss']
        loss.backward()
        self.assertIsNotNone(m.f0_proj.weight.grad)
        self.assertGreater(float(m.f0_proj.weight.grad.detach().abs().sum()),0.0)
        self.assertIsNotNone(emb.grad)
        self.assertGreater(float(emb.grad.detach().abs().sum()),0.0)

    def test_conversion_uses_learned_pitch_projection(self):
        torch.manual_seed(8)
        m=ArgonNeuralV2().eval()
        t=torch.arange(0,7200,dtype=torch.float32)/24000.0
        x=(0.08*torch.sin(2*torch.pi*180.0*t))[None]
        emb=torch.zeros(1,m.speaker_dim)
        with torch.no_grad():
            m.f0_proj.bias.fill_(4.7)
            _,a=m(x,speaker_embedding=emb,shift_pitch=True)
        voiced=a['f0'][0]>20
        self.assertTrue(bool(voiced.any()))
        med=float(a['f0'][0,voiced].median())
        self.assertGreater(med,80.0)
        self.assertLess(med,150.0)

if __name__=='__main__':unittest.main()
PY

echo '=== COMPILE ==='
python3 -m py_compile argon_neural_v2/engine.py

echo '=== F0 TESTS ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest tests.test_neural_v2_f0_learning -v

echo '=== EXISTING REVIEW TESTS ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest tests.test_neural_v2_review_fix -v

echo '=== CHECK CURRENT SAVED EPOCH ==='
/srv/era-audio/venv/bin/python - <<'PY'
import torch,os
for p in ['results/ARGON Neural 2 Long Latest.pt','results/ARGON Neural 2 Long.pt']:
    if os.path.exists(p):
        o=torch.load(p,map_location='cpu',weights_only=True)
        print(p,o.get('metadata',{}).get('epoch'),o.get('metadata',{}).get('best_epoch'),o.get('metadata',{}).get('best_val'))
PY

echo '=== RESTART ONLY V2 TO LOAD PATCH ==='
systemctl restart argon-neural-v2.service
sleep 5
systemctl is-active argon-neural-v2.service || true
systemctl --no-pager --full status argon-neural-v2.service | sed -n '1,55p' || true
echo '=== V1 MUST REMAIN ACTIVE ==='
systemctl is-active argon-neural-long.service || true
echo '=== V2 LOG TAIL ==='
tail -20 'results/ARGON Neural 2 long.log' 2>/dev/null || true
