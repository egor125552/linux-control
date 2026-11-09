#!/usr/bin/env bash
set -euo pipefail
WORK='/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 7 ручные дубли 9 ноября 2026'
PY='/srv/Zombie Horror Game/Tools/vosk/venv/bin/python'
"$PY" - <<'PY'
from pathlib import Path
import json,re,collections,math
work=Path('/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 7 ручные дубли 9 ноября 2026')

def norm(s): return re.findall(r'[а-я0-9]+',s.lower().replace('ё','е'))
def sub(a,b):
    if a==b:return 0.0
    if min(len(a),len(b))>=3 and (a.startswith(b) or b.startswith(a)):return .35
    return 1.0
def lev(a,b):
    prev=list(map(float,range(len(b)+1)))
    for x in a:
        cur=[prev[0]+1]
        for j,y in enumerate(b,1):
            cur.append(min(prev[j]+1,cur[-1]+1,prev[j-1]+sub(x,y)))
        prev=cur
    return prev[-1]

for person in ['Александр','Дмитрий','Виктор','Незнакомый 1','Диктор']:
    mp=json.loads((work/f'Карта {person}.json').read_text('utf-8'))
    words=json.loads((work/f'Слова Vosk {person}.json').read_text('utf-8'))
    rw=[str(w['word']).lower().replace('ё','е') for w in words]
    idx={}
    for z in (3,2,1):
        d=collections.defaultdict(list)
        for p in range(0,len(rw)-z+1):
            key=tuple(rw[p:p+z])
            if '[unk]' not in key:d[key].append(p)
        idx[z]=d
    used=[False]*len(words); assigned={}
    order=sorted(range(len(mp['lines'])),key=lambda i:len(norm(mp['lines'][i])),reverse=True)
    for li in order:
        s=norm(mp['lines'][li]); n=len(s); votes=collections.Counter(); gram_used=0
        for z in (3,2,1):
            votes.clear()
            if n<z:continue
            for si in range(n-z+1):
                key=tuple(s[si:si+z])
                for p in idx[z].get(key,()):
                    if not any(used[p:p+z]): votes[p-si]+=z
            if votes:
                gram_used=z;break
        seeds=[off for off,_ in votes.most_common(10)]
        best=None
        pad=max(2,math.ceil(n*.25))
        lo=max(1,n-pad); hi=min(len(words),n+pad+2)
        for off in seeds:
            for delta in range(-2,3):
                j=max(0,off+delta)
                for L in range(lo,hi+1):
                    k=j+L
                    if k>len(words):break
                    if any(used[j:k]):break
                    dur=float(words[k-1]['end'])-float(words[j]['start'])
                    if dur>max(14,n*1.25+7):continue
                    c=lev(s,rw[j:k])/max(n,L)
                    score=c+.04*abs(L-n)/max(1,n)
                    if best is None or score<best[0]:best=(score,j,k,c,dur,gram_used)
        if best:
            assigned[li]=best
            _,j,k,_,_,_=best
            for p in range(j,k):used[p]=True
        else:assigned[li]=None
    print('\n===',person,'===')
    for li,line in enumerate(mp['lines']):
        a=assigned[li]
        if not a:
            print(f'{li+1:02d} NO MATCH :: {line[:70]}');continue
        score,j,k,c,dur,z=a
        print(f"{li+1:02d} gram={z} {words[j]['start']:.2f}-{words[k-1]['end']:.2f} dur={dur:.2f} edit={c:.3f} :: {' '.join(rw[j:k])[:160]}")
PY
