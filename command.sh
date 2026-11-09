#!/usr/bin/env bash
set -euo pipefail
WORK='/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 7 ручные дубли 9 ноября 2026'
SCRIPT="$WORK/Довести нарезку сцены 7.py"
python3 - <<'PY'
from pathlib import Path
p=Path('/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 7 ручные дубли 9 ноября 2026/Довести нарезку сцены 7.py')
s=p.read_text('utf-8')
s=s.replace('import numpy as np','from array import array')
s=s.replace("d=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').copy()","d=array('h'); d.frombytes(w.readframes(w.getnframes()))")
s=s.replace("seg=data[pos:min(pos+frame,len(data))].astype(np.float64)\n        if len(seg) and float(np.sqrt(np.mean(seg*seg)))>threshold:active.append(pos/sr)","seg=data[pos:min(pos+frame,len(data))]\n        if len(seg) and math.sqrt(sum(x*x for x in seg)/len(seg))>threshold:active.append(pos/sr)")
s=s.replace("w.writeframes(data[ia:ib].astype('<i2').tobytes())","w.writeframes(data[ia:ib].tobytes())")
s=s.replace("silence=np.zeros(int(round(pause*p.framerate)),dtype=np.int16)\n    joined=np.concatenate([chunks[0],silence,chunks[1]])","silence=array('h',[0])*int(round(pause*p.framerate))\n    joined=array('h'); joined.extend(chunks[0]); joined.extend(silence); joined.extend(chunks[1])")
s=s.replace("w.writeframes(joined.astype('<i2').tobytes())","w.writeframes(joined.tobytes())")
p.write_text(s,'utf-8')
print('PATCHED', 'numpy' not in s)
PY
python3 "$SCRIPT"
echo '=== FILE COUNTS ==='
find "$WORK" -mindepth 2 -maxdepth 2 -type f -name 'Сцена 7 *.wav' | wc -l
find "$WORK/Готовые MP3" -type f -name 'Сцена 7 *.mp3' | wc -l
find '/srv/Zombie Horror Game/Зимний прототип/audio/voices/game' -maxdepth 1 -type f -name 'Сцена 7 *.mp3' | wc -l
echo '=== REPORT ==='
python3 - <<'PY'
import json
p='/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 7 ручные дубли 9 ноября 2026/Итог нарезки.json'
r=json.load(open(p,encoding='utf-8'))
print('OK',r['validation_ok'],'TOTAL',r['total_clips'],'GAME',r['game_mp3_count'],'ISSUES',r['validation_issues'])
print('SPECIAL',r['special_fixes'])
for c,v in r['characters'].items():
 print(c,v['clips'])
PY
