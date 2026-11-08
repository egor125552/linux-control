#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== V1 MUST STAY ACTIVE ==='
systemctl is-active argon-neural-long.service || true

python3 - <<'PY'
from pathlib import Path
p=Path('argon_neural_v2/train.py')
s=p.read_text()

anchor="from argon_core.neural_longtrain import split_validation,_crop\n"
helper="""
def safe_backward_step(loss,optimizer,params,max_norm):
    params=list(params)
    if not torch.isfinite(loss):
        optimizer.zero_grad(set_to_none=True)
        return False,float('nan')
    optimizer.zero_grad(set_to_none=True)
    loss.backward()
    norm=torch.nn.utils.clip_grad_norm_(params,max_norm,error_if_nonfinite=False)
    if not torch.isfinite(norm):
        optimizer.zero_grad(set_to_none=True)
        return False,float(norm)
    optimizer.step()
    return True,float(norm)

"""
if helper.strip() not in s:
    s=s.replace(anchor,anchor+helper,1)

s=s.replace("dopt=torch.optim.AdamW(critic.parameters(),lr=lr*.6,betas=(.8,.99),weight_decay=1e-5)",
            "dopt=torch.optim.AdamW(critic.parameters(),lr=lr*.25,betas=(.8,.99),weight_decay=1e-5)")

s=s.replace("""                dl=critic_hinge_loss(real_logits,fake_logits)
                dl.backward();torch.nn.utils.clip_grad_norm_(critic.parameters(),1.5);dopt.step()
""","""                dl=critic_hinge_loss(real_logits,fake_logits)
                d_ok,d_norm=safe_backward_step(dl,dopt,critic.parameters(),1.0)
""")

s=s.replace("gen=gen+.035*adv+.12*fm","gen=gen+.015*adv+.08*fm")

s=s.replace("""            gopt.zero_grad(set_to_none=True);gen.backward()
            torch.nn.utils.clip_grad_norm_(gen_params,1.5);gopt.step()
            sums['g']+=float(gen.detach());sums['natural']+=float(nat['total'].detach());sums['vq']+=float(aux['vq_loss'].detach())
""","""            g_ok,g_norm=safe_backward_step(gen,gopt,gen_params,1.2)
            if not g_ok:
                print('ARGON_V2_SKIP_NONFINITE',json.dumps({'epoch':epoch,'step':step,'g':float(gen.detach()) if torch.isfinite(gen) else 'nan','grad_norm':g_norm},ensure_ascii=False),flush=True)
            sums['g']+=float(gen.detach()) if torch.isfinite(gen) else 0.0
            sums['natural']+=float(nat['total'].detach()) if torch.isfinite(nat['total']) else 0.0
            sums['vq']+=float(aux['vq_loss'].detach()) if torch.isfinite(aux['vq_loss']) else 0.0
""")

p.write_text(s)
PY

cat > tests/test_neural_v2_safe_step.py <<'PY'
import unittest,torch
from argon_neural_v2.train import safe_backward_step

class SafeStepTests(unittest.TestCase):
    def test_finite_step_updates(self):
        p=torch.nn.Parameter(torch.tensor([2.0]))
        opt=torch.optim.AdamW([p],lr=.1)
        ok,n=safe_backward_step((p.square()).sum(),opt,[p],1.0)
        self.assertTrue(ok)
        self.assertTrue(torch.isfinite(torch.tensor(n)))
        self.assertLess(float(p.detach()),2.0)

    def test_nan_loss_does_not_update(self):
        p=torch.nn.Parameter(torch.tensor([2.0]))
        opt=torch.optim.AdamW([p],lr=.1)
        before=p.detach().clone()
        loss=p.sum()*torch.tensor(float('nan'))
        ok,n=safe_backward_step(loss,opt,[p],1.0)
        self.assertFalse(ok)
        self.assertTrue(torch.equal(before,p.detach()))

if __name__=='__main__':unittest.main()
PY

echo '=== TESTS ==='
python3 -m py_compile argon_neural_v2/train.py
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest  tests.test_neural_v2_safe_step tests.test_neural_v2_f0_learning tests.test_neural_v2_review_fix -v

echo '=== RESTORE CLEAN EPOCH 26 AS RESUME POINT ==='
cp -f 'results/ARGON Neural 2 Long.pt' 'results/ARGON Neural 2 Long Latest.pt'

echo '=== PATCH SERVICE TO DELAY CRITIC ==='
sed -i 's/--critic-start 20/--critic-start 40/' /srv/ARGON-VC/run-argon-neural-v2.sh

echo '=== RESTART V2 ==='
systemctl start argon-neural-v2.service
sleep 5
systemctl is-active argon-neural-v2.service || true
systemctl --no-pager --full status argon-neural-v2.service | sed -n '1,60p' || true

echo '=== CLEAN RESUME META ==='
/srv/era-audio/venv/bin/python - <<'PY'
import torch
o=torch.load('results/ARGON Neural 2 Long Latest.pt',map_location='cpu',weights_only=True)
m=o.get('metadata',{})
print('RESUME_EPOCH',m.get('epoch'),'BEST_EPOCH',m.get('best_epoch'),'BEST_VAL',m.get('best_val'))
PY

echo '=== V1 FINAL CHECK ==='
systemctl is-active argon-neural-long.service || true
