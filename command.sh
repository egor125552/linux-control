#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== SERVICES ==='
systemctl is-active argon-neural-long.service || true
systemctl is-active argon-neural-v2.service || true

echo '=== CURRENT V2 ==='
tail -20 'results/ARGON Neural 2 long.log' 2>/dev/null || true

echo '=== TRAIN RESUME LOGIC ==='
sed -n '55,100p' argon_neural_v2/train.py

echo '=== CURRENT CHECKPOINT META ==='
for f in 'results/ARGON Neural 2 Long.pt' 'results/ARGON Neural 2 Long Latest.pt'          'results/ARGON Neural 2 backup before-review-fix/ARGON Neural 2 Long.pt'          'results/ARGON Neural 2 backup before-review-fix/ARGON Neural 2 Long Latest.pt'; do
  if [ -f "$f" ]; then
    /srv/era-audio/venv/bin/python - "$f" <<'PY'
import sys,torch,json
o=torch.load(sys.argv[1],map_location='cpu',weights_only=True)
m=o.get('metadata',{})
print(json.dumps({'file':sys.argv[1],'epoch':m.get('epoch'),'best_epoch':m.get('best_epoch'),'best_val':m.get('best_val'),'stage':m.get('stage'),'speakers':m.get('speakers')},ensure_ascii=False))
PY
  fi
done

echo '=== SPEAKER TABLE KEYS ==='
/srv/era-audio/venv/bin/python - <<'PY'
import torch,glob,os
for p in ['results/ARGON Neural 2 Long.pt','results/ARGON Neural 2 Long Latest.pt']:
    if not os.path.exists(p): continue
    o=torch.load(p,map_location='cpu',weights_only=True)
    m=o.get('metadata',{})
    print(p,'speaker_table keys',list((m.get('speaker_table') or {}).keys()))
PY

echo '=== CANDIDATE SOURCE FILES ==='
find '/srv/Zombie Horror Game/Зимний прототип/scene' -type f \( -iname '*.wav' -o -iname '*.mp3' \) | grep -E '/(Виктор|Александр)/' | head -40 || true
echo '=== EXPERIMENTAL FILE ==='
ls -lh 'data/ARGON uploads/Экспериментальный голос.mp3' 2>/dev/null || true
