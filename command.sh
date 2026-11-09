#!/usr/bin/env bash
set -euo pipefail
WORK='/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 7 ручные дубли 9 ноября 2026'
SCRIPT="$WORK/Довести нарезку сцены 7.py"
python3 - <<'PY'
from pathlib import Path
p=Path('/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 7 ручные дубли 9 ноября 2026/Довести нарезку сцены 7.py')
s=p.read_text('utf-8')
old="""        rawgap=speech[person][j][0]-speech[person][i][1] if speech[person][i] and speech[person][j] else 99
        if rawgap<1.25 and cur[1]>=nxt[0]-.02:
            mid=(speech[person][i][1]+speech[person][j][0])/2
            cur[1]=min(cur[1],mid-.02);nxt[0]=max(nxt[0],mid+.02)"""
new="""        if speech[person][i] and speech[person][j]:
            mid=(speech[person][i][1]+speech[person][j][0])/2
            cur[1]=min(cur[1],mid-.03)
            nxt[0]=max(nxt[0],mid+.03)"""
if old not in s: raise SystemExit('old adjacency block not found')
s=s.replace(old,new)
old2="""            if person=='Дмитрий' and i==14:
                a=min(a,258.58);b=max(b,262.02)
            write(dst,p,data,a,b)"""
new2="""            if person=='Дмитрий' and i==10:
                a=max(a,196.30)
            if person=='Дмитрий' and i==14:
                a=min(a,258.58);b=max(b,262.02)
            write(dst,p,data,a,b)"""
if old2 not in s: raise SystemExit('special block not found')
s=s.replace(old2,new2)
# Add duration-to-speech validation.
old3="""        if d<.45 or d>45:issues.append(f'{w.name}: suspicious duration {d:.3f}')
        if w.stat().st_size<1000:issues.append(f'{w.name}: tiny file')"""
new3="""        if d<.45 or d>45:issues.append(f'{w.name}: suspicious duration {d:.3f}')
        idx=int(w.stem.rsplit(' ',1)[-1])-1
        sp=speech[person][idx]
        if sp is not None:
            base=sp[1]-sp[0]
            if d < max(.45,base-.45) or d > base+2.55:
                issues.append(f'{w.name}: duration {d:.3f} vs speech {base:.3f}')
        if w.stat().st_size<1000:issues.append(f'{w.name}: tiny file')"""
if old3 not in s: raise SystemExit('validation block not found')
s=s.replace(old3,new3)
p.write_text(s,'utf-8')
print('PATCHED_BOUNDARIES')
PY
python3 "$SCRIPT"
echo '=== REPORT ==='
python3 - <<'PY'
import json,wave
from pathlib import Path
work=Path('/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 7 ручные дубли 9 ноября 2026')
r=json.load(open(work/'Итог нарезки.json',encoding='utf-8'))
print('OK',r['validation_ok'],'TOTAL',r['total_clips'],'GAME',r['game_mp3_count'],'ISSUES',r['validation_issues'])
for c in r['characters']:
 ds=[]
 for w in sorted((work/c).glob('*.wav')):
  with wave.open(str(w),'rb') as f: ds.append(round(f.getnframes()/f.getframerate(),2))
 print(c,ds)
PY
