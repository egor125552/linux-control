#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
test -s 'models/ARGON Neural corpus.txt'

python3 - <<'PY'
from pathlib import Path
p=Path('argon_core/neural_train.py')
s=p.read_text()
s=s.replace("total=losses['total']+.08*aux['vq_loss']","total=losses['total']+.02*aux['vq_loss']")
p.write_text(s)
print('FINETUNE_VQ_WEIGHT_UPDATED',".02*aux['vq_loss']" in s)
PY

rm -f 'results/ARGON Neural base.log' 'results/ARGON Neural base.pid'
nohup /srv/era-audio/venv/bin/python -u -m argon_core.neural_pretrain   'models/ARGON Neural corpus.txt' 'results/ARGON Neural Base.pt'   --epochs 1 --threads 4 --crop .75 --lr 0.00015   > 'results/ARGON Neural base.log' 2>&1 &
echo $! > 'results/ARGON Neural base.pid'
sleep 2
echo BASE_PID=$(cat 'results/ARGON Neural base.pid')
ps -o pid,etime,%cpu,rss,stat,args -p "$(cat 'results/ARGON Neural base.pid')" || true
echo '=== LOG ==='
tail -20 'results/ARGON Neural base.log' || true
