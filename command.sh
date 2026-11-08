#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== KEEP V1 RUNNING ==='
systemctl is-active argon-neural-long.service || true

echo '=== STOP ONLY BAD V2 BRANCH ==='
systemctl stop argon-neural-v2.service || true
systemctl is-active argon-neural-v2.service || true

echo '=== BEST CLEAN CHECKPOINT ==='
/srv/era-audio/venv/bin/python - <<'PY'
import torch
p='results/ARGON Neural 2 Long.pt'
o=torch.load(p,map_location='cpu',weights_only=True)
m=o.get('metadata',{})
print('epoch',m.get('epoch'),'best_epoch',m.get('best_epoch'),'best_val',m.get('best_val'))
bad=[]
for k,v in o.get('state',{}).items():
    if hasattr(v,'isfinite') and not torch.isfinite(v).all():
        bad.append(k)
print('bad',bad)
PY

echo '=== TRAIN UPDATE SECTION ==='
sed -n '1,320p' argon_neural_v2/train.py

echo '=== CRITIC ==='
sed -n '1,280p' argon_neural_v2/critic.py
