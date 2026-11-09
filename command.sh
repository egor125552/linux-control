#!/usr/bin/env bash
set -euo pipefail
ROOT='/srv/Zombie Horror Game/Зимний прототип'
WORK="$ROOT/scene/Сцена 7 ручные дубли 9 ноября 2026"
PY='/srv/Zombie Horror Game/Tools/vosk/venv/bin/python'
"$PY" - <<'PY'
from pathlib import Path
import json,re,math

work=Path('/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 7 ручные дубли 9 ноября 2026')

def norm(s):
    return re.findall(r'[а-яё0-9]+',s.lower().replace('ё','е'))

def sub(a,b):
    if a==b:return 0.0
    if min(len(a),len(b))>=3 and (a.startswith(b) or b.startswith(a)):return .35
    return 1.0

def lev(a,b):
    prev=[float(j) for j in range(len(b)+1)]
    for x in a:
        cur=[prev[0]+1]
        for j,y in enumerate(b,1):
            cur.append(min(prev[j]+1,cur[-1]+1,prev[j-1]+sub(x,y)))
        prev=cur
    return prev[-1]

for person in ['Александр','Дмитрий','Виктор','Незнакомый 1','Диктор']:
    mp=json.loads((work/f'Карта {person}.json').read_text('utf-8'))
    words=json.loads((work/f'Слова Vosk {person}.json').read_text('utf-8'))
    rw=[w['word'].lower().replace('ё','е') for w in words]
    used=[False]*len(words)
    assigned={}
    order=sorted(range(len(mp['lines'])),key=lambda i:len(norm(mp['lines'][i])),reverse=True)
    for li in order:
        s=norm(mp['lines'][li]); n=len(s)
        lo=max(1,int(n*.62)); hi=min(len(words),int(n*1.45)+4)
        best=None
        for j in range(len(words)):
            if used[j]: continue
            for L in range(lo,hi+1):
                k=j+L
                if k>len(words):break
                if any(used[j:k]):break
                dur=float(words[k-1]['end'])-float(words[j]['start'])
                # Do not let a candidate swallow several unrelated takes.
                if dur > max(12.0,n*1.45+8): continue
                c=lev(s,rw[j:k])/max(n,L)
                lp=.07*abs(L-n)/max(1,n)
                # prefer compact candidates, but allow dramatic pauses
                dp=max(0,dur-(n*.72+5))*0.003
                score=c+lp+dp
                if best is None or score<best[0]:
                    best=(score,j,k,c,dur)
        if best is None:
            assigned[li]=None; continue
        score,j,k,c,dur=best
        assigned[li]=(j,k,score,c,dur)
        for z in range(j,k):used[z]=True
    print('\n===',person,'===')
    for li in range(len(mp['lines'])):
        a=assigned.get(li)
        if not a:
            print(li+1,'NO MATCH',mp['lines'][li][:65]);continue
        j,k,score,c,dur=a
        excerpt=' '.join(rw[j:k])
        print(f"{li+1:02d} tok={len(norm(mp['lines'][li])):02d} {words[j]['start']:.2f}-{words[k-1]['end']:.2f} dur={dur:.2f} edit={c:.3f} score={score:.3f} :: {excerpt[:125]}")
PY
