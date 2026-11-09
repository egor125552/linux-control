#!/usr/bin/env bash
set -euo pipefail
ROOT='/srv/Zombie Horror Game/Зимний прототип'
WORK="$ROOT/scene/Сцена 7 ручные дубли 9 ноября 2026"
UP='/srv/ARGON-VC/data/ARGON uploads'
PY='/srv/Zombie Horror Game/Tools/vosk/venv/bin/python'
"$PY" - <<'PY'
from pathlib import Path
import importlib.util,json,wave,math,struct
root=Path('/srv/Zombie Horror Game/Зимний прототип')
work=root/'scene'/'Сцена 7 ручные дубли 9 ноября 2026'
up=Path('/srv/ARGON-VC/data/ARGON uploads')
tool=Path('/srv/Zombie Horror Game/Tools/vosk/Разрезать большой дубль Vosk.py')
spec=importlib.util.spec_from_file_location('splitter',tool)
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for person in ['Александр','Дмитрий','Виктор','Незнакомый 1','Диктор']:
    src=up/f'Сцена 7 {person}.wav'
    mp=json.loads((work/f'Карта {person}.json').read_text('utf-8'))
    words,elapsed,ignored=m.recognize(src,mp['lines'],m.DEFAULT_MODEL,include_ignored=True)
    by,acc=m.align(mp['lines'],words,ignored)
    (work/f'Слова Vosk {person}.json').write_text(json.dumps(words,ensure_ascii=False,indent=2),'utf-8')
    with wave.open(str(src),'rb') as w:
        sr=w.getframerate(); n=w.getnframes(); raw=w.readframes(n)
    vals=struct.unpack('<'+'h'*(len(raw)//2),raw)
    frame=max(1,int(.02*sr))
    active=[]
    for pos in range(0,n,frame):
        seg=vals[pos:min(pos+frame,n)]
        if not seg: continue
        rms=math.sqrt(sum(x*x for x in seg)/len(seg))
        if rms>80: active.append(pos/sr)
    print('===',person,'expected',len(mp['lines']),'vosk_words',len(words),'accuracy',round(acc,3),'ignored',len(ignored),'duration',round(n/sr,2))
    for gap in (.35,.5,.75,1.0,1.25,1.5,2.0):
        groups=[]
        if active:
            s=active[0]; prev=active[0]
            for t in active[1:]:
                if t-prev>gap:
                    groups.append((s,prev+.02))
                    s=t
                prev=t
            groups.append((s,prev+.02))
        print(' gap',gap,'groups',len(groups),'durations',[round(b-a,2) for a,b in groups[:35]])
    for i,line in enumerate(mp['lines']):
        e=by[i]; ass=[x for x in e if x[1] is not None]; mat=[x for x in ass if x[2]<1]
        ratio=len(mat)/max(1,len(e))
        inds=[x[1] for x in ass]
        if inds:
            print(' line',i+1,'ratio',round(ratio,2),'time',round(words[min(inds)]['start'],2),round(words[max(inds)]['end'],2),'text',line[:55])
        else:
            print(' line',i+1,'ratio',0,'NO WORDS','text',line[:55])
PY
