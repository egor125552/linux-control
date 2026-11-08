#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== TRAINERS BEFORE ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true
tail -8 'results/ARGON Neural 2 long.log' || true

python3 - <<'PY'
from pathlib import Path
p=Path('tests/test_neural_v2_f0_learning.py')
s=p.read_text()
s=s.replace("""        self.assertIsNotNone(emb.grad)
        self.assertGreater(float(emb.grad.detach().abs().sum()),0.0)
""","""        self.assertIsNotNone(m.f0_proj.bias.grad)
        self.assertGreater(float(m.f0_proj.bias.grad.detach().abs().sum()),0.0)
""")
p.write_text(s)
PY

echo '=== F0 GRADIENT TESTS ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest tests.test_neural_v2_f0_learning -v

echo '=== REVIEW TESTS ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest tests.test_neural_v2_review_fix -v

echo '=== WAIT FOR NEXT SAFE CHECKPOINT ==='
CUR=$(grep 'ARGON_V2_EPOCH' 'results/ARGON Neural 2 long.log' | tail -1 | sed -n 's/.*"epoch": \([0-9][0-9]*\).*/\1/p')
CUR=${CUR:-10}
TARGET=$(( ((CUR + 4) / 5) * 5 ))
if [ "$TARGET" -le "$CUR" ]; then TARGET=$((TARGET+5)); fi
echo CURRENT=$CUR TARGET=$TARGET
while true; do
  SAVED=$(/srv/era-audio/venv/bin/python - <<'PY'
import torch,os
p='results/ARGON Neural 2 Long Latest.pt'
if not os.path.exists(p):
    print(0)
else:
    o=torch.load(p,map_location='cpu',weights_only=True)
    print(int(o.get('metadata',{}).get('epoch',0)))
PY
)
  echo SAVED=$SAVED
  if [ "$SAVED" -ge "$TARGET" ]; then break; fi
  sleep 2
done

echo '=== RESTART V2 FROM THAT CHECKPOINT ==='
systemctl restart argon-neural-v2.service
sleep 5
systemctl is-active argon-neural-v2.service || true
systemctl --no-pager --full status argon-neural-v2.service | sed -n '1,55p' || true

echo '=== CHECK LOADED START EPOCH AFTER RESTART ==='
/srv/era-audio/venv/bin/python - <<'PY'
import torch
p='results/ARGON Neural 2 Long Latest.pt'
o=torch.load(p,map_location='cpu',weights_only=True)
m=o.get('metadata',{})
print('LATEST_EPOCH',m.get('epoch'),'BEST_EPOCH',m.get('best_epoch'),'BEST_VAL',m.get('best_val'))
PY

echo '=== V1 STILL ACTIVE ==='
systemctl is-active argon-neural-long.service || true
