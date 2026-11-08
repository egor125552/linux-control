#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
echo '=== SERVICE ==='
systemctl is-active argon-neural-long.service || true
systemctl --no-pager --full status argon-neural-long.service | sed -n '1,45p' || true
echo '=== PROCESS ==='
ps -eo pid,etime,%cpu,%mem,rss,stat,args | grep 'argon_core.neural_continue' | grep -v grep || true
echo '=== LATEST LOG ==='
tail -40 'results/ARGON Neural continuous.log' 2>/dev/null || true
echo '=== CHECKPOINTS ==='
for f in 'results/ARGON Neural Continuous 50000.pt' 'results/ARGON Neural Continuous 50000 Latest.pt'; do
  if [ -f "$f" ]; then
    /srv/era-audio/venv/bin/python - "$f" <<'PY'
import sys,torch,json
p=sys.argv[1]
o=torch.load(p,map_location='cpu',weights_only=True)
m=o.get('metadata',{})
print(json.dumps({
 'file':p,
 'stage':m.get('stage'),
 'epoch':m.get('epoch'),
 'best_epoch':m.get('best_epoch'),
 'best_val':m.get('best_val'),
 'max_epoch':m.get('max_epoch')
},ensure_ascii=False))
PY
  fi
done
