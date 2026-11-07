#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

cat > argon_core/corpus.py <<'PY'
from __future__ import annotations
from pathlib import Path
import hashlib, subprocess

AUDIO_EXTS={'.wav','.mp3','.m4a','.flac','.ogg','.opus','.aac'}
EXCLUDED_PARTS={'Готовые MP3','sfx','SFX','game','raw'}

def classify_speaker(path):
    p=Path(path)
    low=str(p).lower()
    if 'экспериментальный голос' in low:return 'experimental'
    parts=[x.lower() for x in p.parts]
    mapping=(
        (('незнакомый 1',),'unknown_1'),
        (('незнакомый 2',),'unknown_2'),
        (('незнакомый 3',),'unknown_3'),
        (('учёный 1','ученый 1'),'scientist_1'),
        (('учёный 2','ученый 2'),'scientist_2'),
        (('александр','alexander'),'alexander'),
        (('виктор','victor'),'victor'),
        (('диктор','narrator'),'narrator'),
    )
    for needles,name in mapping:
        if any(any(n in part for n in needles) for part in parts):
            return name
    return None

def is_voice_file(path):
    p=Path(path)
    if not p.is_file() or p.suffix.lower() not in AUDIO_EXTS:return False
    if any(part in EXCLUDED_PARTS for part in p.parts):return False
    return classify_speaker(p) is not None

def sha1_file(path):
    h=hashlib.sha1()
    with Path(path).open('rb') as f:
        while True:
            b=f.read(1024*1024)
            if not b:break
            h.update(b)
    return h.hexdigest()

def duration(path):
    try:
        s=subprocess.check_output([
            'ffprobe','-v','error','-show_entries','format=duration',
            '-of','default=nw=1:nk=1',str(path)
        ],text=True).strip()
        return float(s)
    except Exception:
        return 0.0

def discover_voice_files(scene_root,data_root):
    candidates=[]
    scene_root=Path(scene_root)
    data_root=Path(data_root)
    if scene_root.exists():
        for p in scene_root.rglob('*'):
            if is_voice_file(p):candidates.append(p)
    if data_root.exists():
        for p in data_root.rglob('*'):
            if not p.is_file() or p.suffix.lower() not in AUDIO_EXTS:continue
            if p.name in {'victor_source.wav','Учёный 2 пробная реплика.wav'}:continue
            if classify_speaker(p) is not None:candidates.append(p)
    out=[];seen=set()
    for p in candidates:
        try:
            if p.stat().st_size<20000:continue
            key=(p.stat().st_size,sha1_file(p))
        except OSError:
            continue
        if key in seen:continue
        seen.add(key);out.append(p)
    return out
PY

cat > argon_core/neural_longtrain.py <<'PY'
from __future__ import annotations
import argparse,copy,json,math,random,time
from pathlib import Path
import torch
from .audio import read_audio
from .neural_engine import ArgonSourceFilter
from .neural_pretrain import build_windows
from .losses import anti_robot_loss

def split_validation(corpus,per_speaker=2):
    train={};valid={}
    by={}
    for ci,c in enumerate(corpus):
        by.setdefault(c['speaker'],[]).extend((ci,pos) for pos in c['windows'])
    for speaker,items in by.items():
        if len(items)<2:
            train[speaker]=items;valid[speaker]=[]
            continue
        count=min(int(per_speaker),max(1,len(items)//12))
        # deterministic, spread across the speaker instead of taking adjacent clips
        ids=[]
        for j in range(count):
            idx=round((j+1)*len(items)/(count+1))-1
            ids.append(max(0,min(len(items)-1,idx)))
        chosen={items[i] for i in ids}
        valid[speaker]=[x for x in items if x in chosen]
        train[speaker]=[x for x in items if x not in chosen]
    return train,valid

def _crop(corpus,item,n):
    ci,pos=item
    y=corpus[ci]['audio'][pos:pos+n]
    if len(y)<n:y=torch.nn.functional.pad(y,(0,n-len(y)))
    y=y-y.mean();r=y.square().mean().sqrt().clamp_min(1e-5)
    return (y*(.065/r)).clamp(-.95,.95)

@torch.no_grad()
def validate(model,table,sid,corpus,valid,n,device):
    model.eval();vals=[];per={}
    for speaker,items in valid.items():
        sv=[]
        for item in items:
            y=_crop(corpus,item,n)[None].to(device)
            emb=table(torch.tensor([sid[speaker]],device=device))
            pred,aux=model(y,speaker_embedding=emb)
            loss=anti_robot_loss(pred,y,model.sample_rate)['total']+.02*aux['vq_loss']
            sv.append(float(loss))
        if sv:
            per[speaker]=sum(sv)/len(sv);vals.extend(sv)
    model.train()
    return (sum(vals)/len(vals) if vals else float('inf')),per

def _save(model,table,sid,output,meta):
    with torch.no_grad():
        if 'experimental' in sid:model.voice.copy_(table.weight[sid['experimental']:sid['experimental']+1])
        else:model.voice.copy_(table.weight.mean(0,keepdim=True))
    meta=dict(meta)
    meta['speaker_table']={name:table.weight[i].detach().cpu().tolist() for name,i in sid.items()}
    model.save(output,meta)

def train(manifest,base,output,epochs=1000,steps_per_epoch=96,threads=4,
          crop_seconds=.75,lr=5e-5,val_every=5,patience_checks=40,
          checkpoint_every=10,seed=5501):
    torch.manual_seed(seed);torch.set_num_threads(max(1,int(threads)))
    paths=[Path(x.strip()) for x in Path(manifest).read_text().splitlines() if x.strip()]
    sr=24000
    corpus,target_holdout=build_windows(paths,sr,crop_seconds)
    train_groups,valid_groups=split_validation(corpus,2)
    speakers=sorted(k for k,v in train_groups.items() if v)
    sid={s:i for i,s in enumerate(speakers)}
    if not speakers:raise RuntimeError('no speakers for long training')
    model,base_meta=ArgonSourceFilter.load(base,'cpu');model.train()
    table=torch.nn.Embedding(len(speakers),model.speaker_dim)
    torch.nn.init.normal_(table.weight,std=.08)
    with torch.no_grad():
        if 'experimental' in sid:
            table.weight[sid['experimental']].copy_(model.voice[0])
    params=list(model.parameters())+list(table.parameters())
    opt=torch.optim.AdamW(params,lr=float(lr),weight_decay=1e-4)
    sched=torch.optim.lr_scheduler.ReduceLROnPlateau(opt,mode='min',factor=.5,patience=6,min_lr=5e-6)
    n=round(crop_seconds*sr)
    history=[];best=float('inf');best_epoch=0;best_state=None;best_table=None
    checks_without=0;started=time.monotonic()
    out=Path(output);latest=out.with_name(out.stem+' Latest'+out.suffix)
    for epoch in range(1,int(epochs)+1):
        rng=random.Random(seed+epoch*7919)
        sums={'total':0.,'spectral':0.,'subband':0.,'envelope':0.,'vq':0.}
        order=speakers[:];rng.shuffle(order)
        for step in range(int(steps_per_epoch)):
            speaker=order[step%len(order)]
            if step%len(order)==len(order)-1:rng.shuffle(order)
            item=rng.choice(train_groups[speaker])
            y=_crop(corpus,item,n)[None]
            emb=table(torch.tensor([sid[speaker]]))
            pred,aux=model(y,speaker_embedding=emb)
            losses=anti_robot_loss(pred,y,sr)
            # Slight loudness penalty prevents the increasingly quiet output seen in the one-epoch base.
            pr=pred.square().mean().sqrt().clamp_min(1e-5)
            tr=y.square().mean().sqrt().clamp_min(1e-5)
            loud=(torch.log(pr)-torch.log(tr)).abs()
            total=losses['total']+.02*aux['vq_loss']+.08*loud
            if not torch.isfinite(total):raise RuntimeError('non-finite long training loss')
            opt.zero_grad(set_to_none=True);total.backward()
            torch.nn.utils.clip_grad_norm_(params,2.0);opt.step()
            sums['total']+=float(total.detach());sums['vq']+=float(aux['vq_loss'].detach())
            for k in ('spectral','subband','envelope'):sums[k]+=float(losses[k].detach())
        row={'epoch':epoch,'lr':opt.param_groups[0]['lr'],
             **{k:v/max(1,steps_per_epoch) for k,v in sums.items()},
             'seconds':time.monotonic()-started}
        if epoch%int(val_every)==0 or epoch==1:
            val,per=validate(model,table,sid,corpus,valid_groups,n,'cpu')
            row['val']=val;row['val_by_speaker']=per
            sched.step(val)
            if math.isfinite(val) and val < best-1e-4:
                best=val;best_epoch=epoch;checks_without=0
                best_state=copy.deepcopy(model.state_dict());best_table=copy.deepcopy(table.state_dict())
                meta={'stage':'long_multispeaker','max_epochs':epochs,'epoch':epoch,'best_epoch':best_epoch,
                      'best_val':best,'history':history+[row],'speakers':speakers,
                      'unique_files':len(corpus),'train_windows':sum(len(v) for v in train_groups.values()),
                      'validation_windows':sum(len(v) for v in valid_groups.values()),
                      'target_holdout_ranges_seconds':target_holdout,'base_checkpoint':str(base),
                      'no_random_source_noise':True}
                _save(model,table,sid,out,meta)
            else:
                checks_without+=1
        history.append(row)
        print('ARGON_LONG_EPOCH',json.dumps(row,ensure_ascii=False),flush=True)
        if epoch%int(checkpoint_every)==0:
            meta={'stage':'long_multispeaker_latest','max_epochs':epochs,'epoch':epoch,
                  'best_epoch':best_epoch,'best_val':best,'history':history[-100:],
                  'speakers':speakers,'unique_files':len(corpus),
                  'train_windows':sum(len(v) for v in train_groups.values()),
                  'validation_windows':sum(len(v) for v in valid_groups.values()),
                  'target_holdout_ranges_seconds':target_holdout,'base_checkpoint':str(base),
                  'no_random_source_noise':True}
            _save(model,table,sid,latest,meta)
        if checks_without>=int(patience_checks):
            print('ARGON_LONG_EARLY_STOP',json.dumps({'epoch':epoch,'best_epoch':best_epoch,'best_val':best},ensure_ascii=False),flush=True)
            break
    if best_state is not None:
        model.load_state_dict(best_state);table.load_state_dict(best_table)
    meta={'stage':'long_multispeaker_final','max_epochs':epochs,'finished_epoch':history[-1]['epoch'],
          'best_epoch':best_epoch,'best_val':best,'history':history,'speakers':speakers,
          'unique_files':len(corpus),'train_windows':sum(len(v) for v in train_groups.values()),
          'validation_windows':sum(len(v) for v in valid_groups.values()),
          'target_holdout_ranges_seconds':target_holdout,'base_checkpoint':str(base),
          'no_random_source_noise':True}
    _save(model,table,sid,out,meta)
    return model,meta

def main():
    p=argparse.ArgumentParser()
    p.add_argument('manifest');p.add_argument('base');p.add_argument('output')
    p.add_argument('--epochs',type=int,default=1000);p.add_argument('--steps',type=int,default=96)
    p.add_argument('--threads',type=int,default=4);p.add_argument('--crop',type=float,default=.75)
    p.add_argument('--lr',type=float,default=5e-5);p.add_argument('--val-every',type=int,default=5)
    p.add_argument('--patience-checks',type=int,default=40);p.add_argument('--checkpoint-every',type=int,default=10)
    a=p.parse_args()
    train(a.manifest,a.base,a.output,a.epochs,a.steps,a.threads,a.crop,a.lr,
          a.val_every,a.patience_checks,a.checkpoint_every)
if __name__=='__main__':main()
PY

python3 - <<'PY'
from pathlib import Path
p=Path('argon_core/neural_train.py')
s=p.read_text()
old="pred,_=model(y[None].to(next(model.parameters()).device),noise=torch.zeros(1,((len(y)//model.hop)+2)*model.hop,device=next(model.parameters()).device))"
new="pred,_=model(y[None].to(next(model.parameters()).device))"
if old not in s:
    raise SystemExit('expected old holdout call not found')
p.write_text(s.replace(old,new))
PY

cat > tests/test_neural_corpus.py <<'PY'
import tempfile,unittest
from pathlib import Path
from argon_core.corpus import classify_speaker,is_voice_file
from argon_core.neural_longtrain import split_validation

class CorpusTests(unittest.TestCase):
    def test_all_named_characters_are_classified(self):
        cases={
            '/x/Александр/a.wav':'alexander',
            '/x/Виктор/a.wav':'victor',
            '/x/Учёный 1/a.wav':'scientist_1',
            '/x/Учёный 2/a.wav':'scientist_2',
            '/x/Незнакомый 1/a.wav':'unknown_1',
            '/x/Незнакомый 2/a.wav':'unknown_2',
            '/x/Незнакомый 3/a.wav':'unknown_3',
            '/x/Диктор/a.wav':'narrator',
            '/x/Экспериментальный голос.mp3':'experimental',
        }
        for p,want in cases.items():self.assertEqual(classify_speaker(Path(p)),want)

    def test_ready_mp3_copy_is_excluded(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'Готовые MP3'/'Александр'/'a.wav';p.parent.mkdir(parents=True);p.write_bytes(b'x'*30000)
            self.assertFalse(is_voice_file(p))

    def test_validation_is_disjoint_per_speaker(self):
        corpus=[
            {'speaker':'a','windows':list(range(20))},
            {'speaker':'b','windows':list(range(10))},
        ]
        tr,va=split_validation(corpus,2)
        for s in tr:
            self.assertTrue(set(tr[s]).isdisjoint(set(va[s])))
            self.assertGreater(len(tr[s]),0)
            self.assertGreater(len(va[s]),0)

if __name__=='__main__':unittest.main()
PY

python3 -m py_compile argon_core/corpus.py argon_core/neural_longtrain.py argon_core/neural_train.py
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest tests.test_neural_corpus tests.test_neural_source tests.test_neural_rvq_stability -v
