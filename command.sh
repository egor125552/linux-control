#!/usr/bin/env bash
set -euo pipefail
WORK='/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 7 ручные дубли 9 ноября 2026'
PY='/srv/Zombie Horror Game/Tools/vosk/venv/bin/python'
"$PY" - <<'PY'
from pathlib import Path
import json,re,collections
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
    pos=collections.defaultdict(list)
    for i,w in enumerate(rw):
        if w!='[unk]': pos[w].append(i)
    used=[False]*len(words); assigned={}
    order=sorted(range(len(mp['lines'])),key=lambda i:len(norm(mp['lines'][i])),reverse=True)
    for li in order:
        s=norm(mp['lines'][li]); n=len(s)
        votes=collections.Counter()
        for si,t in enumerate(s):
            for p in pos.get(t,()):
                if not used[p]: votes[p-si]+=1
        seeds=[x for x,_ in votes.most_common(45)]
        if not seeds:
            seeds=list(range(0,len(words),max(1,n//2)))
        starts=set()
        for x in seeds:
            for d in range(-4,5): starts.add(max(0,x+d))
        lo=max(1,int(n*.68)); hi=max(lo,int(n*1.38)+3)
        best=None
        for j in starts:
            if j>=len(words) or used[j]: continue
            for L in range(lo,hi+1):
                k=j+L
                if k>len(words): break
                if any(used[j:k]): break
                dur=float(words[k-1]['end'])-float(words[j]['start'])
                if dur>max(13.0,n*1.35+8): continue
                c=lev(s,rw[j:k])/max(n,L)
                exact=sum(1 for q in range(j,k) if rw[q] in s)/max(1,n)
                score=c+.06*abs(L-n)/max(1,n)-.025*min(1.2,exact)
                if best is None or score<best[0]:
                    best=(score,j,k,c,dur)
        if best:
            score,j,k,c,dur=best
            assigned[li]=best
            for z in range(j,k):used[z]=True
        else: assigned[li]=None
    print('\n===',person,'===')
    for li,line in enumerate(mp['lines']):
        a=assigned[li]
        if not a:
            print(f'{li+1:02d} NO MATCH :: {line[:80]}');continue
        score,j,k,c,dur=a
        print(f"{li+1:02d} tok={len(norm(line)):02d} {words[j]['start']:.2f}-{words[k-1]['end']:.2f} dur={dur:.2f} edit={c:.3f} score={score:.3f} :: {' '.join(rw[j:k])[:145]}")
PY
