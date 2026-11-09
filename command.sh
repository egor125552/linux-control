#!/usr/bin/env bash
set -euo pipefail
ROOT='/srv/Zombie Horror Game/Зимний прототип'
WORK="$ROOT/scene/Сцена 7 ручные дубли 9 ноября 2026"
UP='/srv/ARGON-VC/data/ARGON uploads'
PY='/srv/Zombie Horror Game/Tools/vosk/venv/bin/python'
mkdir -p "$WORK"
cat > "$WORK/Довести нарезку сцены 7.py" <<'PY'
from pathlib import Path
import json,wave,hashlib,subprocess,shutil,math
import numpy as np

root=Path('/srv/Zombie Horror Game/Зимний прототип')
work=root/'scene'/'Сцена 7 ручные дубли 9 ноября 2026'
up=Path('/srv/ARGON-VC/data/ARGON uploads')
raw=root/'audio'/'voices'/'raw'
game=root/'audio'/'voices'/'game'
mp3root=work/'Готовые MP3'
mp3root.mkdir(parents=True,exist_ok=True)

speech={
'Александр':[
(.78,9.84),(12.24,20.97),(23.91,32.31),(35.25,41.16),(43.71,45.09),(47.22,51.93),
(54.03,61.11),(63.24,71.94),(72.90,78.93),(80.73,88.47),(90.09,99.78),(102.81,109.50),
(111.27,113.85),(115.71,117.87),(191.73,201.21),(202.68,214.89),(216.48,220.20),
(221.40,228.00),(230.01,237.03),(238.65,246.24),(247.80,252.33),(253.71,261.21),
(264.18,266.46),(267.90,270.96),(274.50,284.94),(285.90,293.67)],
'Дмитрий':[
(1.11,6.51),(8.52,12.30),(13.92,18.87),(22.89,28.32),(31.77,39.45),(42.18,48.84),
(51.81,56.97),(60.69,71.97),(72.87,104.10),None,(196.71,227.16),(231.87,243.03),
(244.56,250.89),(252.72,257.58),(258.66,261.94)],
'Виктор':[(2.58,7.56),(9.87,12.72),(14.01,21.87),(23.04,30.75),(32.70,44.73),(47.01,55.53),(56.97,60.90),(62.88,68.82)],
'Незнакомый 1':[(.69,5.70),(7.83,15.24)],
'Диктор':[(.33,21.12)]
}
dmitry10_parts=[(106.14,111.15),(183.18,195.87)]

def sha(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()

def load(path):
    with wave.open(str(path),'rb') as w:
        p=w.getparams()
        if p.nchannels!=1 or p.sampwidth!=2 or p.comptype!='NONE':
            raise RuntimeError(f'Unexpected WAV {path}: {p}')
        d=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').copy()
    return p,d

def groups(data,sr,threshold=85,gap=.22):
    frame=max(1,int(.02*sr)); active=[]
    for pos in range(0,len(data),frame):
        seg=data[pos:min(pos+frame,len(data))].astype(np.float64)
        if len(seg) and float(np.sqrt(np.mean(seg*seg)))>threshold:active.append(pos/sr)
    out=[]
    if active:
        s=prev=active[0]
        for t in active[1:]:
            if t-prev>gap:
                out.append((s,prev+.02));s=t
            prev=t
        out.append((s,prev+.02))
    return out

def refine(ss,se,gs,total):
    start=max(0,ss-.18); end=min(total,se+.24)
    for a,b in gs:
        if a-.08 <= ss <= b+.08:
            start=max(0,a-.06);break
    for a,b in gs:
        if a-.08 <= se <= b+.12:
            end=min(total,b+.08);break
    return start,end

def write(path,p,data,a,b):
    ia=max(0,int(round(a*p.framerate))); ib=min(len(data),int(round(b*p.framerate)))
    if ib<=ia:raise RuntimeError(f'empty {path}')
    path.parent.mkdir(parents=True,exist_ok=True)
    with wave.open(str(path),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(p.framerate)
        w.writeframes(data[ia:ib].astype('<i2').tobytes())

def write_join(path,p,data,parts,pause=.35):
    chunks=[]
    for a,b in parts:
        ia=max(0,int(round(a*p.framerate)));ib=min(len(data),int(round(b*p.framerate)))
        chunks.append(data[ia:ib])
    silence=np.zeros(int(round(pause*p.framerate)),dtype=np.int16)
    joined=np.concatenate([chunks[0],silence,chunks[1]])
    path.parent.mkdir(parents=True,exist_ok=True)
    with wave.open(str(path),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(p.framerate);w.writeframes(joined.astype('<i2').tobytes())
    return len(joined)/p.framerate

summary={'method':'Vosk known-script words + longest-first anchors + acoustic performance edges','characters':{},'special_fixes':{},'source_hashes':{}}
total=0
for person in ['Александр','Дмитрий','Виктор','Незнакомый 1','Диктор']:
    src=up/f'Сцена 7 {person}.wav'
    before=sha(src); p,data=load(src); dur=len(data)/p.framerate; gs=groups(data,p.framerate)
    mapping=json.loads((work/f'Карта {person}.json').read_text('utf-8'))
    outdir=work/person
    if outdir.exists():shutil.rmtree(outdir)
    outdir.mkdir(parents=True)
    items=[]
    refined=[]
    for i,span in enumerate(speech[person]):
        if person=='Дмитрий' and i==9:
            refined.append(None);continue
        a,b=refine(span[0],span[1],gs,dur)
        refined.append([a,b])
    # Prevent neighboring real lines from stealing each other's breath/tails.
    valid=[(i,x) for i,x in enumerate(refined) if x]
    for q in range(len(valid)-1):
        i,cur=valid[q]; j,nxt=valid[q+1]
        rawgap=speech[person][j][0]-speech[person][i][1] if speech[person][i] and speech[person][j] else 99
        if rawgap<1.25 and cur[1]>=nxt[0]-.02:
            mid=(speech[person][i][1]+speech[person][j][0])/2
            cur[1]=min(cur[1],mid-.02);nxt[0]=max(nxt[0],mid+.02)
    for i,(name,line) in enumerate(zip(mapping['clips'],mapping['lines'])):
        dst=outdir/name
        if person=='Дмитрий' and i==9:
            rparts=[refine(a,b,gs,dur) for a,b in dmitry10_parts]
            # Never include the inserted Gemini block between the two real halves.
            rparts[0]=(max(105.82,rparts[0][0]),min(111.65,rparts[0][1]))
            rparts[1]=(max(182.95,rparts[1][0]),min(196.25,rparts[1][1]))
            cdur=write_join(dst,p,data,rparts,.35)
            item={'index':i+1,'file':name,'line':line,'duration':round(cdur,3),'source_parts':[[round(a,3),round(b,3)] for a,b in rparts],'inserted_pause':.35,'manual_splice':True}
        else:
            a,b=refined[i]
            # Explicitly protect known extra-block boundaries and final gasp.
            if person=='Александр' and i==13:b=min(b,118.12)
            if person=='Александр' and i==14:a=max(a,190.55)
            if person=='Дмитрий' and i==14:
                a=min(a,258.58);b=max(b,262.02)
            write(dst,p,data,a,b)
            item={'index':i+1,'file':name,'line':line,'start':round(a,3),'end':round(b,3),'duration':round(b-a,3),'speech_start':round(speech[person][i][0],3),'speech_end':round(speech[person][i][1],3)}
        items.append(item);total+=1
    # Preserve source in project as a copy, never move it.
    rawdst=raw/f'Зима дубль Сцена 7 {person}.wav'
    shutil.copy2(src,rawdst)
    after=sha(src)
    if before!=after:raise RuntimeError(f'source changed: {person}')
    summary['source_hashes'][person]={'sha256':before,'unchanged':True,'duration':round(dur,3)}
    summary['characters'][person]={'clips':len(items),'items':items}
summary['special_fixes']={
'Александр':'Excluded Gemini extra block between line 14 and line 15; true line 15 anchored by Vosk at 191.73 s.',
'Дмитрий':'Line 10 was split by a Gemini extra block; joined two Vosk-confirmed source parts. Line 15 preserves gasp plus Не убил.'
}

# Encode WAVs and install unique Scene 7 MP3 files.
game.mkdir(parents=True,exist_ok=True)
for person in summary['characters']:
    outmp=mp3root/person
    if outmp.exists():shutil.rmtree(outmp)
    outmp.mkdir(parents=True)
    for wavp in sorted((work/person).glob('*.wav')):
        mp3=outmp/(wavp.stem+'.mp3')
        cp=subprocess.run(['/usr/bin/ffmpeg','-v','error','-y','-i',str(wavp),'-map_metadata','-1','-ac','1','-ar','24000','-codec:a','libmp3lame','-b:a','96k',str(mp3)],capture_output=True,text=True)
        if cp.returncode or not mp3.exists() or mp3.stat().st_size==0:
            raise RuntimeError(cp.stderr[-1000:])
        shutil.copy2(mp3,game/mp3.name)

# Validation
expected={'Александр':26,'Дмитрий':15,'Виктор':8,'Незнакомый 1':2,'Диктор':1}
issues=[]
for person,n in expected.items():
    ws=sorted((work/person).glob('*.wav')); ms=sorted((mp3root/person).glob('*.mp3'))
    if len(ws)!=n or len(ms)!=n:issues.append(f'{person}: count {len(ws)}/{len(ms)} expected {n}')
    for w in ws:
        with wave.open(str(w),'rb') as f:d=f.getnframes()/f.getframerate()
        if d<.45 or d>45:issues.append(f'{w.name}: suspicious duration {d:.3f}')
        if w.stat().st_size<1000:issues.append(f'{w.name}: tiny file')
game_count=len(list(game.glob('Сцена 7 *.mp3')))
if game_count!=52:issues.append(f'game scene7 count {game_count}')
summary['total_clips']=total
summary['game_mp3_count']=game_count
summary['validation_issues']=issues
summary['validation_ok']=not issues
(work/'Итог нарезки.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),'utf-8')
if issues:raise RuntimeError('; '.join(issues))
print(json.dumps({'ok':True,'total':total,'game_mp3':game_count,'source_unchanged':all(x['unchanged'] for x in summary['source_hashes'].values()),'workspace':str(work)},ensure_ascii=False))
for person,n in expected.items():
    ds=[]
    for w in sorted((work/person).glob('*.wav')):
        with wave.open(str(w),'rb') as f:ds.append(round(f.getnframes()/f.getframerate(),3))
    print(person,n,ds)
PY
"$PY" "$WORK/Довести нарезку сцены 7.py"
echo '=== FILE COUNTS ==='
find "$WORK" -mindepth 2 -maxdepth 2 -type f -name 'Сцена 7 *.wav' | wc -l
find "$WORK/Готовые MP3" -type f -name 'Сцена 7 *.mp3' | wc -l
find "$ROOT/audio/voices/game" -maxdepth 1 -type f -name 'Сцена 7 *.mp3' | wc -l
echo '=== REPORT ==='
python3 - <<'PY'
import json
p='/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 7 ручные дубли 9 ноября 2026/Итог нарезки.json'
r=json.load(open(p,encoding='utf-8'))
print('OK',r['validation_ok'],'TOTAL',r['total_clips'],'GAME',r['game_mp3_count'],'ISSUES',r['validation_issues'])
print('SPECIAL',r['special_fixes'])
PY
