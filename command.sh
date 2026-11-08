#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

cat > argon_neural_v2/train.py <<'PY'
from __future__ import annotations
import argparse,json,math,random,time
from pathlib import Path
import torch
from .engine import ArgonNeuralV2
from .critic import MultiPeriodCritic,critic_hinge_loss,generator_hinge_loss,feature_matching_loss
from .losses import naturalness_loss
from argon_core.neural_pretrain import build_windows
from argon_core.neural_longtrain import split_validation,_crop

def init_speaker_table(speakers,dim=192,seed_checkpoint=None):
    sid={s:i for i,s in enumerate(speakers)}
    table=torch.nn.Embedding(len(speakers),dim)
    torch.nn.init.normal_(table.weight,std=.06)
    if seed_checkpoint and Path(seed_checkpoint).exists():
        try:
            obj=torch.load(seed_checkpoint,map_location='cpu',weights_only=True)
            saved=obj.get('metadata',{}).get('speaker_table') or {}
            with torch.no_grad():
                for name,i in sid.items():
                    vec=saved.get(name)
                    if isinstance(vec,list) and vec:
                        v=torch.tensor(vec,dtype=table.weight.dtype)
                        n=min(dim,v.numel())
                        table.weight[i,:n].copy_(v[:n])
        except Exception:
            pass
    return table,sid

def save_model(model,table,sid,path,meta):
    with torch.no_grad():
        if 'experimental' in sid:
            model.voice.copy_(table.weight[sid['experimental']:sid['experimental']+1])
        else:
            model.voice.copy_(table.weight.mean(0,keepdim=True))
    m=dict(meta)
    m['speaker_table']={name:table.weight[i].detach().cpu().tolist() for name,i in sid.items()}
    model.save(path,m)

@torch.no_grad()
def validate(model,table,sid,corpus,valid,n,max_per_speaker=2):
    model.eval();vals=[];per={}
    for speaker,items in valid.items():
        if speaker not in sid or not items:continue
        one=[]
        for item in items[:max_per_speaker]:
            y=_crop(corpus,item,n)[None]
            emb=table(torch.tensor([sid[speaker]]))
            pred,aux=model(y,speaker_embedding=emb)
            l=naturalness_loss(pred,y,model.sample_rate)['total']+.015*aux['vq_loss']
            one.append(float(l))
        if one:
            per[speaker]=sum(one)/len(one);vals.extend(one)
    model.train()
    return (sum(vals)/len(vals) if vals else float('inf')),per

def train(manifest,output,epochs=10000,steps=48,threads=2,crop=.5,lr=8e-5,
          critic_start=20,val_every=2,checkpoint_every=5,seed=7711,
          seed_speaker_checkpoint=None):
    torch.manual_seed(seed);torch.set_num_threads(max(1,int(threads)))
    paths=[Path(x.strip()) for x in Path(manifest).read_text().splitlines() if x.strip()]
    corpus,target_holdout=build_windows(paths,24000,crop)
    train_groups,valid_groups=split_validation(corpus,2)
    speakers=sorted(k for k,v in train_groups.items() if v)
    if not speakers:raise RuntimeError('no speakers for ARGON Neural 2')

    out=Path(output);latest=out.with_name(out.stem+' Latest'+out.suffix)
    if latest.exists():
        model,old_meta=ArgonNeuralV2.load(latest,'cpu')
        start_epoch=int(old_meta.get('epoch',0))
        table,sid=init_speaker_table(speakers,model.speaker_dim,None)
        saved=old_meta.get('speaker_table') or {}
        with torch.no_grad():
            for name,i in sid.items():
                v=saved.get(name)
                if isinstance(v,list) and len(v)==model.speaker_dim:
                    table.weight[i].copy_(torch.tensor(v,dtype=table.weight.dtype))
        best=float(old_meta.get('best_val',float('inf')))
        best_epoch=int(old_meta.get('best_epoch',0))
    else:
        model=ArgonNeuralV2();start_epoch=0
        table,sid=init_speaker_table(speakers,model.speaker_dim,seed_speaker_checkpoint)
        best=float('inf');best_epoch=0

    critic=MultiPeriodCritic(periods=(2,3,5,7))
    gen_params=list(model.parameters())+list(table.parameters())
    gopt=torch.optim.AdamW(gen_params,lr=lr,betas=(.8,.99),weight_decay=1e-4)
    dopt=torch.optim.AdamW(critic.parameters(),lr=lr*.6,betas=(.8,.99),weight_decay=1e-5)
    gsched=torch.optim.lr_scheduler.ReduceLROnPlateau(gopt,mode='min',factor=.7,patience=12,min_lr=4e-6)
    dsched=torch.optim.lr_scheduler.ReduceLROnPlateau(dopt,mode='min',factor=.8,patience=18,min_lr=3e-6)

    n=round(crop*24000);history=[];started=time.monotonic()
    for epoch in range(start_epoch+1,int(epochs)+1):
        rng=random.Random(seed+epoch*1009);order=speakers[:];rng.shuffle(order)
        sums={'g':0.,'natural':0.,'vq':0.,'d':0.,'adv':0.,'fm':0.}
        for step in range(int(steps)):
            speaker=order[step%len(order)]
            if step%len(order)==len(order)-1:rng.shuffle(order)
            y=_crop(corpus,rng.choice(train_groups[speaker]),n)[None]
            emb=table(torch.tensor([sid[speaker]]))
            pred,aux=model(y,speaker_embedding=emb)
            nat=naturalness_loss(pred,y,24000)
            gen=nat['total']+.015*aux['vq_loss']

            if epoch>=critic_start:
                dopt.zero_grad(set_to_none=True)
                real_logits,_=critic(y);fake_logits,_=critic(pred.detach())
                dl=critic_hinge_loss(real_logits,fake_logits)
                dl.backward();torch.nn.utils.clip_grad_norm_(critic.parameters(),1.5);dopt.step()
                for p in critic.parameters():p.requires_grad_(False)
                with torch.no_grad():_,real_features=critic(y)
                fake_logits,fake_features=critic(pred)
                adv=generator_hinge_loss(fake_logits);fm=feature_matching_loss(real_features,fake_features)
                gen=gen+.035*adv+.12*fm
                for p in critic.parameters():p.requires_grad_(True)
                sums['d']+=float(dl.detach());sums['adv']+=float(adv.detach());sums['fm']+=float(fm.detach())

            gopt.zero_grad(set_to_none=True);gen.backward()
            torch.nn.utils.clip_grad_norm_(gen_params,1.5);gopt.step()
            sums['g']+=float(gen.detach());sums['natural']+=float(nat['total'].detach());sums['vq']+=float(aux['vq_loss'].detach())

        row={'epoch':epoch,'g_lr':gopt.param_groups[0]['lr'],'d_lr':dopt.param_groups[0]['lr'],
             **{k:v/max(1,steps) for k,v in sums.items()},'seconds':time.monotonic()-started}
        if epoch%val_every==0 or epoch==1:
            val,per=validate(model,table,sid,corpus,valid_groups,n)
            row['val']=val;row['val_by_speaker']=per;gsched.step(val);dsched.step(val)
            if math.isfinite(val) and val<best:
                best=val;best_epoch=epoch
                save_model(model,table,sid,out,{'stage':'argon_neural_2_best','epoch':epoch,
                    'best_epoch':best_epoch,'best_val':best,'speakers':speakers,'files':len(corpus),
                    'target_holdout_ranges_seconds':target_holdout,'critic_start':critic_start,
                    'architecture':'ARGON Neural 2'})
        history.append(row);print('ARGON_V2_EPOCH',json.dumps(row,ensure_ascii=False),flush=True)
        if epoch%checkpoint_every==0:
            save_model(model,table,sid,latest,{'stage':'argon_neural_2_latest','epoch':epoch,
                'best_epoch':best_epoch,'best_val':best,'speakers':speakers,'files':len(corpus),
                'target_holdout_ranges_seconds':target_holdout,'critic_start':critic_start,
                'history_tail':history[-100:],'architecture':'ARGON Neural 2'})

def main():
    p=argparse.ArgumentParser();p.add_argument('manifest');p.add_argument('output')
    p.add_argument('--epochs',type=int,default=10000);p.add_argument('--steps',type=int,default=48)
    p.add_argument('--threads',type=int,default=2);p.add_argument('--crop',type=float,default=.5)
    p.add_argument('--lr',type=float,default=8e-5);p.add_argument('--critic-start',type=int,default=20)
    p.add_argument('--val-every',type=int,default=2);p.add_argument('--checkpoint-every',type=int,default=5)
    p.add_argument('--seed-speaker-checkpoint')
    a=p.parse_args()
    train(a.manifest,a.output,a.epochs,a.steps,a.threads,a.crop,a.lr,a.critic_start,
          a.val_every,a.checkpoint_every,seed_speaker_checkpoint=a.seed_speaker_checkpoint)
if __name__=='__main__':main()
PY

python3 -m py_compile argon_neural_v2/train.py

PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
from argon_core.corpus import classify_speaker,duration
src=Path('models/ARGON Neural all voices.txt');picked=[];seen=set()
for line in src.read_text().splitlines():
    p=Path(line);s=classify_speaker(p)
    if s in ('experimental',None) or s in seen:continue
    d=duration(p)
    if .8<=d<=5:picked.append(p);seen.add(s)
    if len(picked)>=2:break
Path('models/ARGON Neural 2 smoke.txt').write_text('\n'.join(str(x) for x in picked)+'\n')
print('SMOKE',len(picked),[str(x) for x in picked])
PY

rm -f 'results/ARGON Neural 2 Smoke.pt' 'results/ARGON Neural 2 Smoke Latest.pt'
echo '=== V2 TRAIN SMOKE ==='
OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -u -m argon_neural_v2.train  'models/ARGON Neural 2 smoke.txt' 'results/ARGON Neural 2 Smoke.pt'  --epochs 1 --steps 2 --threads 1 --crop .35 --lr 0.00008 --critic-start 999  --val-every 1 --checkpoint-every 1

echo '=== V1 STILL ACTIVE ==='
systemctl is-active argon-neural-long.service || true
ps -eo pid,etime,%cpu,%mem,args | grep 'argon_core.neural_continue' | grep -v grep || true
ls -lh 'results/ARGON Neural 2 Smoke.pt' 'results/ARGON Neural 2 Smoke Latest.pt'
