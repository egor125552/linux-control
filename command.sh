#!/usr/bin/env bash
set -euo pipefail
PY='/srv/Zombie Horror Game/Tools/vosk/venv/bin/python'
"$PY" - <<'PY'
from pathlib import Path
import wave,math,struct
up=Path('/srv/ARGON-VC/data/ARGON uploads')
checks=[
('Александр',22.5,33.0),('Александр',114.5,122.0),('Александр',190.0,202.5),
('Дмитрий',104.0,113.5),('Дмитрий',180.0,197.0),('Дмитрий',257.0,262.12)]
for person,a,b in checks:
    src=up/f'Сцена 7 {person}.wav'
    with wave.open(str(src),'rb') as w:
        sr=w.getframerate(); w.setpos(int(a*sr)); raw=w.readframes(int((b-a)*sr))
    vals=struct.unpack('<'+'h'*(len(raw)//2),raw)
    frame=max(1,int(.02*sr)); act=[]
    for pos in range(0,len(vals),frame):
        seg=vals[pos:pos+frame]
        if not seg:continue
        rms=math.sqrt(sum(x*x for x in seg)/len(seg))
        if rms>85:act.append(a+pos/sr)
    groups=[]
    if act:
        s=p=act[0]
        for t in act[1:]:
            if t-p>.22:
                groups.append((s,p+.02));s=t
            p=t
        groups.append((s,p+.02))
    print('\n',person,a,b)
    for x,y in groups:print(f'{x:.3f}-{y:.3f} dur={y-x:.3f}')
PY
