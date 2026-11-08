#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

cat > argon_core/neural_continue.py <<'PY'
from __future__ import annotations
import argparse,copy,json,math,random,time
from pathlib import Path
import torch
from .audio import read_audio
from .neural_engine import ArgonSourceFilter
from .neural_pretrain import build_windows
from .neural_longtrain import split_validation,_crop,validate,_save

def restore_speaker_table(meta,speakers,dim=128):
    sid={s:i for i,s in enumerate(speakers)}
    table=torch.nn.Embedding(len(speakers),dim)
    torch.nn.init.normal_(table.weight,std=.08)
    saved=meta.get('speaker_table') or {}
    with torch.no_grad():
        for name,i in sid.items():
            v=saved.get(name)
            if isinstance(v,list) and len(v)==dim:
                table.weight[i].copy_(torch.tensor(v,dtype=table.weight.dtype))
    return table,sid

def latest_checkpoint(output: Path, seed_checkpoint: Path):
    latest=output.with_name(output.stem+' Latest'+output.suffix)
    if latest.exists():
        try:
            _,meta=ArgonSourceFilter.load(latest,'cpu')
            if int(meta.get('epoch',0))>=1:
                return latest
        except Exception:
            pass
    return seed_checkpoint

def train(manifest,seed_checkpoint,output,max_epoch=50000,steps_per_epoch=96,threads=4,
          crop_seconds=.75,lr=3e-5,val_every=5,checkpoint_every=10,seed=6501):
    torch.manual_seed(seed)
    torch.set_num_threads(max(1,int(threads)))
    manifest=Path(manifest);output=Path(output);seed_checkpoint=Path(seed_checkpoint)
    start_path=latest_checkpoint(output,seed_checkpoint)
    model,meta=ArgonSourceFilter.load(start_path,'cpu')
    start_epoch=int(meta.get('epoch',0))
    previous_best=float(meta.get('best_val',float('inf')))
    previous_best_epoch=int(meta.get('best_epoch',start_epoch if math.isfinite(previous_best) else 0))

    paths=[Path(x.strip()) for x in manifest.read_text().splitlines() if x.strip()]
    corpus,target_holdout=build_windows(paths,model.sample_rate,crop_seconds)
    train_groups,valid_groups=split_validation(corpus,2)
    speakers=sorted(k for k,v in train_groups.items() if v)
    table,sid=restore_speaker_table(meta,speakers,model.speaker_dim)
    model.train()
    params=list(model.parameters())+list(table.parameters())
    opt=torch.optim.AdamW(params,lr=float(lr),weight_decay=1e-4)
    sched=torch.optim.lr_scheduler.ReduceLROnPlateau(
        opt,mode='min',factor=.6,patience=10,min_lr=3e-6)
    n=round(crop_seconds*model.sample_rate)
    best=previous_best;best_epoch=previous_best_epoch
    history=[];started=time.monotonic()
    latest=output.with_name(output.stem+' Latest'+output.suffix)

    for epoch in range(start_epoch+1,int(max_epoch)+1):
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
            from .losses import anti_robot_loss
            losses=anti_robot_loss(pred,y,model.sample_rate)
            pr=pred.square().mean().sqrt().clamp_min(1e-5)
            tr=y.square().mean().sqrt().clamp_min(1e-5)
            loud=(torch.log(pr)-torch.log(tr)).abs()
            total=losses['total']+.02*aux['vq_loss']+.08*loud
            if not torch.isfinite(total):
                raise RuntimeError('non-finite continuation loss')
            opt.zero_grad(set_to_none=True)
            total.backward()
            torch.nn.utils.clip_grad_norm_(params,2.0)
            opt.step()
            sums['total']+=float(total.detach())
            sums['vq']+=float(aux['vq_loss'].detach())
            for k in ('spectral','subband','envelope'):
                sums[k]+=float(losses[k].detach())

        row={'epoch':epoch,'lr':opt.param_groups[0]['lr'],
             **{k:v/max(1,steps_per_epoch) for k,v in sums.items()},
             'seconds_this_run':time.monotonic()-started}

        if epoch%int(val_every)==0:
            val,per=validate(model,table,sid,corpus,valid_groups,n,'cpu')
            row['val']=val;row['val_by_speaker']=per
            sched.step(val)
            if math.isfinite(val) and val<best:
                best=val;best_epoch=epoch
                best_meta={'stage':'continuous_long_best','epoch':epoch,
                           'best_epoch':best_epoch,'best_val':best,
                           'max_epoch':max_epoch,'speakers':speakers,
                           'unique_files':len(corpus),
                           'target_holdout_ranges_seconds':target_holdout,
                           'seed_checkpoint':str(seed_checkpoint),
                           'resumed_from':str(start_path),
                           'history_tail':history[-99:]+[row],
                           'no_random_source_noise':True}
                _save(model,table,sid,output,best_meta)

        history.append(row)
        print('ARGON_CONTINUE_EPOCH',json.dumps(row,ensure_ascii=False),flush=True)

        if epoch%int(checkpoint_every)==0:
            latest_meta={'stage':'continuous_long_latest','epoch':epoch,
                         'best_epoch':best_epoch,'best_val':best,
                         'max_epoch':max_epoch,'speakers':speakers,
                         'unique_files':len(corpus),
                         'target_holdout_ranges_seconds':target_holdout,
                         'seed_checkpoint':str(seed_checkpoint),
                         'resumed_from':str(start_path),
                         'history_tail':history[-100:],
                         'no_random_source_noise':True}
            _save(model,table,sid,latest,latest_meta)

    final_meta={'stage':'continuous_long_final','epoch':max_epoch,
                'best_epoch':best_epoch,'best_val':best,'max_epoch':max_epoch,
                'speakers':speakers,'unique_files':len(corpus),
                'target_holdout_ranges_seconds':target_holdout,
                'seed_checkpoint':str(seed_checkpoint),'resumed_from':str(start_path),
                'history_tail':history[-100:],'no_random_source_noise':True}
    _save(model,table,sid,latest,final_meta)

def main():
    p=argparse.ArgumentParser()
    p.add_argument('manifest');p.add_argument('seed_checkpoint');p.add_argument('output')
    p.add_argument('--max-epoch',type=int,default=50000)
    p.add_argument('--steps',type=int,default=96)
    p.add_argument('--threads',type=int,default=4)
    p.add_argument('--crop',type=float,default=.75)
    p.add_argument('--lr',type=float,default=3e-5)
    p.add_argument('--val-every',type=int,default=5)
    p.add_argument('--checkpoint-every',type=int,default=10)
    a=p.parse_args()
    train(a.manifest,a.seed_checkpoint,a.output,a.max_epoch,a.steps,a.threads,
          a.crop,a.lr,a.val_every,a.checkpoint_every)
if __name__=='__main__':
    main()
PY

cat > tests/test_neural_continue.py <<'PY'
import tempfile,unittest,torch
from pathlib import Path
from argon_core.neural_continue import restore_speaker_table,latest_checkpoint
from argon_core.neural_engine import ArgonSourceFilter

class ContinueTests(unittest.TestCase):
    def test_restores_saved_speaker_vectors(self):
        vec=[0.25]*128
        table,sid=restore_speaker_table({'speaker_table':{'a':vec}},['a','b'],128)
        self.assertTrue(torch.allclose(table.weight[sid['a']],torch.tensor(vec)))
        self.assertFalse(torch.allclose(table.weight[sid['b']],torch.tensor(vec)))

    def test_prefers_newer_latest_checkpoint(self):
        with tempfile.TemporaryDirectory() as d:
            d=Path(d);seed=d/'seed.pt';out=d/'long.pt'
            m=ArgonSourceFilter()
            m.save(seed,{'epoch':60})
            m.save(d/'long Latest.pt',{'epoch':70})
            self.assertEqual(latest_checkpoint(out,seed),d/'long Latest.pt')

if __name__=='__main__':unittest.main()
PY

PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest tests.test_neural_continue -v
python3 -m py_compile argon_core/neural_continue.py

systemctl stop argon-neural-long.service 2>/dev/null || true
pkill -TERM -f 'argon_core.neural_(longtrain|continue)' 2>/dev/null || true
sleep 1

cat > /srv/ARGON-VC/run-argon-neural-long.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
exec /srv/era-audio/venv/bin/python -u -m argon_core.neural_continue   'models/ARGON Neural all voices.txt'   'results/ARGON Neural Long 1000 Latest.pt'   'results/ARGON Neural Continuous 50000.pt'   --max-epoch 50000   --steps 96   --threads 4   --crop .75   --lr 0.00003   --val-every 5   --checkpoint-every 10   > 'results/ARGON Neural continuous.log' 2>&1
SH
chmod 755 /srv/ARGON-VC/run-argon-neural-long.sh

cat > /etc/systemd/system/argon-neural-long.service <<'UNIT'
[Unit]
Description=ARGON Neural continuous training to 50000 epochs
After=network.target

[Service]
Type=simple
WorkingDirectory=/srv/ARGON-VC
ExecStart=/srv/ARGON-VC/run-argon-neural-long.sh
User=root
Nice=5
Restart=on-failure
RestartSec=5
Environment=PYTHONPATH=/srv/ARGON-VC
Environment=OMP_NUM_THREADS=4
Environment=MKL_NUM_THREADS=4
Environment=OPENBLAS_NUM_THREADS=1

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable argon-neural-long.service >/dev/null
systemctl start argon-neural-long.service
sleep 4

echo '=== STATUS ==='
systemctl --no-pager --full status argon-neural-long.service | sed -n '1,70p' || true
echo '=== COUNT ==='
ps -eo args | grep 'argon_core.neural_continue' | grep -v grep | wc -l
echo '=== LOG ==='
tail -30 'results/ARGON Neural continuous.log' 2>/dev/null || true
