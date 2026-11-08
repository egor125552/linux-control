#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== SERVICES ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true

echo '=== LOG ==='
tail -30 'results/ARGON Neural 2 long.log' 2>/dev/null || true

echo '=== CHECKPOINT META ==='
/srv/era-audio/venv/bin/python - <<'PY'
import torch,os
for p in ['results/ARGON Neural 2 Long.pt','results/ARGON Neural 2 Long Latest.pt']:
    if not os.path.exists(p): continue
    o=torch.load(p,map_location='cpu',weights_only=True)
    m=o.get('metadata',{})
    bad=[]
    for k,v in o.get('state',{}).items():
        if hasattr(v,'isfinite') and not torch.isfinite(v).all():
            bad.append(k)
    print(p,'epoch',m.get('epoch'),'best_epoch',m.get('best_epoch'),'best_val',m.get('best_val'),'bad',bad[:10])
PY

echo '=== BACKUP CODE ==='
mkdir -p 'results/ARGON Neural 2 phase fix backup'
cp -f argon_neural_v2/features.py 'results/ARGON Neural 2 phase fix backup/features.py'
cp -f argon_neural_v2/tract.py 'results/ARGON Neural 2 phase fix backup/tract.py'
cp -f argon_neural_v2/engine.py 'results/ARGON Neural 2 phase fix backup/engine.py'
ls -lh 'results/ARGON Neural 2 phase fix backup'
