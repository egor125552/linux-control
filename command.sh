#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== V1 MUST STAY ACTIVE ==='
systemctl is-active argon-neural-long.service || true
systemctl stop argon-neural-v2.service || true

cat > argon_neural_v2/tract.py <<'PY'
from __future__ import annotations
import math
import torch
import torch.nn as nn
import torch.nn.functional as F
from .postfilter import Snake1d

class GenerativeBlock(nn.Module):
    def __init__(self,dim=256,speaker_dim=192,dilation=1):
        super().__init__()
        self.dw=nn.Conv1d(dim,dim,7,padding=3*dilation,dilation=dilation,groups=dim)
        self.norm=nn.GroupNorm(1,dim)
        self.film=nn.Linear(speaker_dim,dim*2)
        self.act1=Snake1d(dim)
        self.p1=nn.Conv1d(dim,dim*4,1)
        self.act2=Snake1d(dim*4)
        self.p2=nn.Conv1d(dim*4,dim,1)
        self.gamma=nn.Parameter(torch.ones(1,dim,1)*0.08)

    def forward(self,x,spk):
        h=self.norm(self.dw(x))
        scale,bias=self.film(spk).chunk(2,-1)
        h=h*(1.0+0.75*torch.tanh(scale)[:,:,None])+0.75*bias[:,:,None]
        h=self.p2(self.act2(self.p1(self.act1(h))))
        return x+self.gamma*h

class DeepVocalTract(nn.Module):
    """
    True generative iSTFT decoder.
    It never sees raw source waveform or raw source STFT.
    """
    def __init__(self,dim=256,speaker_dim=192,hop=240,long_taps=129,short_taps=31):
        super().__init__()
        self.dim=int(dim);self.speaker_dim=int(speaker_dim);self.hop=int(hop)
        self.long_taps=int(long_taps);self.short_taps=int(short_taps)
        self.n_fft=1024;self.win_length=960;self.bins=self.n_fft//2+1
        self.speaker_in=nn.Linear(speaker_dim,dim)
        self.control_in=nn.Conv1d(3,dim,3,padding=1)
        self.pilot_in=nn.Conv1d(self.bins,dim,1)
        self.blocks=nn.ModuleList([
            GenerativeBlock(dim,speaker_dim,d)
            for d in (1,2,4,8,1,2,4,8,1,2)
        ])
        # Kept as spec_filter name for checkpoint/test compatibility, but now it is an absolute spectral generator.
        self.spec_filter=nn.Conv1d(dim,self.bins,1)
        self.phase_head=nn.Conv1d(dim,self.bins,1)
        self.gain_head=nn.Conv1d(dim,1,1)
        self.long_head=nn.Conv1d(dim,long_taps,1)
        self.short_head=nn.Conv1d(dim,short_taps,1)
        nn.init.normal_(self.spec_filter.weight,std=.015)
        nn.init.constant_(self.spec_filter.bias,-2.2)
        nn.init.zeros_(self.phase_head.weight);nn.init.zeros_(self.phase_head.bias)
        nn.init.zeros_(self.gain_head.weight);nn.init.zeros_(self.gain_head.bias)
        nn.init.zeros_(self.long_head.weight);nn.init.zeros_(self.long_head.bias)
        nn.init.zeros_(self.short_head.weight);nn.init.zeros_(self.short_head.bias)

    def _align(self,x,frames):
        if x.shape[-1]==frames:return x
        return F.interpolate(x,size=frames,mode='linear',align_corners=False)

    def forward(self,excitation,codes,speaker_embedding,f0,energy,confidence):
        if excitation.ndim==1:excitation=excitation[None]
        frames=codes.shape[-1]
        f0=self._align(f0[:,None],frames)[:,0]
        energy=self._align(energy[:,None],frames)[:,0]
        confidence=self._align(confidence[:,None],frames)[:,0]

        voiced=(f0>20).to(codes.dtype)
        log_f0=torch.where(voiced>0,torch.log(f0.clamp_min(55.0)),torch.zeros_like(f0))
        log_f0=((log_f0-math.log(150.0))/1.15).clamp(-2.5,2.5)
        controls=torch.stack((log_f0,voiced,energy.clamp(0,1)),dim=1)

        win=torch.hann_window(self.win_length,device=excitation.device,dtype=excitation.dtype)
        Z_pilot=torch.stft(
            excitation,n_fft=self.n_fft,hop_length=self.hop,win_length=self.win_length,
            window=win,center=True,return_complex=True
        )
        Z_pilot=Z_pilot[...,:frames]
        pilot_mag=torch.log1p(Z_pilot.abs())
        pilot_phase=torch.angle(Z_pilot)

        h=(codes
           +self.speaker_in(speaker_embedding)[:,:,None]
           +self.control_in(controls)
           +self.pilot_in(pilot_mag))
        for block in self.blocks:
            h=block(h,speaker_embedding)

        # Absolute generated magnitude. Pilot is only a soft frequency/phase landmark.
        raw_log_mag=self.spec_filter(h)
        energy_scale=(0.03+energy[:,None,:]).clamp_min(1e-3)
        log_mag=(raw_log_mag + torch.log(energy_scale)).clamp(-8.0,5.0)
        mag=torch.exp(log_mag)

        # Instantaneous phase increments: harmonic pilot where voiced, free learned phase where unvoiced.
        expected=2*math.pi*self.hop*torch.arange(
            self.bins,device=h.device,dtype=h.dtype
        )[None,:,None]/self.n_fft
        expected=expected.expand(h.shape[0],-1,frames)
        prev=torch.cat((pilot_phase[...,:1],pilot_phase[...,:-1]),dim=-1)
        pilot_inc=torch.atan2(torch.sin(pilot_phase-prev),torch.cos(pilot_phase-prev))
        voiced3=voiced[:,None,:]
        base_inc=voiced3*pilot_inc+(1.0-voiced3)*expected
        residual=0.85*math.pi*torch.tanh(self.phase_head(h))
        inst_freq=base_inc+residual
        phase=torch.cumsum(inst_freq,dim=-1)
        phase=phase + pilot_phase[...,:1]

        Z_out=torch.polar(mag,phase)
        y=torch.istft(
            Z_out,n_fft=self.n_fft,hop_length=self.hop,win_length=self.win_length,
            window=win,length=excitation.shape[-1]
        )
        gain=torch.exp(.55*torch.tanh(self.gain_head(h)))
        gain_s=F.interpolate(gain,size=y.shape[-1],mode='linear',align_corners=False)[:,0]
        y=y*gain_s
        return y,{
            'log_filter':log_mag,
            'generated_log_mag':log_mag,
            'inst_freq':inst_freq,
            'gain':gain,
            'long_ir':self.long_head(h),
            'short_ir':self.short_head(h),
        }
PY

cat > argon_neural_v2/critic.py <<'PY'
from __future__ import annotations
import torch
import torch.nn as nn
import torch.nn.functional as F

class PeriodCritic(nn.Module):
    def __init__(self,period,channels=(1,12,24,48,64)):
        super().__init__();self.period=int(period)
        self.layers=nn.ModuleList([
            nn.Conv2d(channels[i],channels[i+1],(5,1),stride=(3,1),padding=(2,0))
            for i in range(len(channels)-1)
        ])
        self.out=nn.Conv2d(channels[-1],1,(3,1),padding=(1,0))

    def forward(self,x):
        if x.ndim==2:x=x[:,None]
        b,c,t=x.shape
        r=t%self.period
        if r:x=F.pad(x,(0,self.period-r),mode='reflect' if t>self.period else 'constant')
        x=x.view(b,c,-1,self.period)
        feats=[]
        for layer in self.layers:
            x=F.leaky_relu(layer(x),.2);feats.append(x)
        x=self.out(x);feats.append(x)
        return x.flatten(1),feats

class SpectralCrispnessCritic(nn.Module):
    def __init__(self):
        super().__init__()
        chans=(1,8,16,32,48)
        self.layers=nn.ModuleList([
            nn.Conv2d(chans[i],chans[i+1],(5,3),stride=(2,2),padding=(2,1))
            for i in range(len(chans)-1)
        ])
        self.out=nn.Conv2d(chans[-1],1,(3,3),padding=1)

    def forward(self,x):
        if x.ndim==1:x=x[None]
        w=torch.hann_window(512,device=x.device,dtype=x.dtype)
        z=torch.stft(x,n_fft=512,hop_length=128,win_length=512,window=w,center=True,return_complex=True)
        h=torch.log1p(z.abs())[:,None]
        feats=[]
        for layer in self.layers:
            h=F.leaky_relu(layer(h),.2);feats.append(h)
        h=self.out(h);feats.append(h)
        return h.flatten(1),feats

class MicroVoiceCritic(nn.Module):
    def __init__(self,periods=(2,3,5,7)):
        super().__init__()
        self.periods=tuple(periods)
        self.period_critics=nn.ModuleList([PeriodCritic(p) for p in self.periods])
        self.spectral=SpectralCrispnessCritic()

    def forward(self,x):
        logits=[];features=[]
        for c in self.period_critics:
            l,f=c(x);logits.append(l);features.append(f)
        l,f=self.spectral(x);logits.append(l);features.append(f)
        return logits,features

# Compatibility alias for older imports.
MultiPeriodCritic=MicroVoiceCritic

def critic_hinge_loss(real_logits,fake_logits):
    loss=real_logits[0].new_tensor(0.)
    for r,f in zip(real_logits,fake_logits):
        loss=loss+F.relu(1-r).mean()+F.relu(1+f).mean()
    return loss/len(real_logits)

def generator_hinge_loss(fake_logits):
    return sum((-x.mean()) for x in fake_logits)/len(fake_logits)

def feature_matching_loss(real_features,fake_features):
    vals=[]
    for rr,ff in zip(real_features,fake_features):
        for r,f in zip(rr,ff):
            vals.append(F.l1_loss(f,r.detach()))
    return sum(vals)/max(1,len(vals))
PY

cat > argon_neural_v2/engine.py <<'PY'
from __future__ import annotations
from pathlib import Path
import torch
import torch.nn as nn
import torch.nn.functional as F
from .features import pitch_energy,align_frames
from .source import HarmonicExcitation
from .content import DeepContentEncoder
from .tract import DeepVocalTract
from .postfilter import WaveformRefiner

FORMAT='ARGON-NEURAL-2.1-GENERATIVE'

class ArgonNeuralV2(nn.Module):
    def __init__(self,sample_rate=24000,hop=240,content_dim=256,speaker_dim=192,
                 harmonics=32,books=6,book_size=1024,long_taps=129,short_taps=31):
        super().__init__()
        self.sample_rate=int(sample_rate);self.hop=int(hop)
        self.content_dim=int(content_dim);self.speaker_dim=int(speaker_dim)
        self.harmonics=int(harmonics);self.books=int(books);self.book_size=int(book_size)
        self.long_taps=int(long_taps);self.short_taps=int(short_taps)
        self.content=DeepContentEncoder(self.sample_rate,self.hop,self.content_dim,self.books,self.book_size)
        self.source=HarmonicExcitation(self.sample_rate,self.hop,self.harmonics)
        self.tract=DeepVocalTract(self.content_dim,self.speaker_dim,self.hop,self.long_taps,self.short_taps)
        self.refiner=WaveformRefiner(self.content_dim,self.speaker_dim,64,self.hop)
        self.voice=nn.Parameter(torch.randn(1,self.speaker_dim)*.04)
        self.f0_proj=nn.Linear(self.speaker_dim,1)
        nn.init.zeros_(self.f0_proj.weight);nn.init.constant_(self.f0_proj.bias,4.55)

    def forward(self,wav,speaker_embedding=None,shift_pitch=False,content_wav=None):
        if wav.ndim==1:wav=wav[None]
        if content_wav is None:content_wav=wav
        if content_wav.ndim==1:content_wav=content_wav[None]

        codes,indices,vq_loss,vq_stats=self.content(content_wav)
        f0,energy,confidence=pitch_energy(wav,self.sample_rate,self.hop)
        f0=align_frames(f0,codes.shape[-1])
        energy=align_frames(energy,codes.shape[-1])
        confidence=align_frames(confidence,codes.shape[-1])

        if speaker_embedding is None:
            speaker_embedding=self.voice.expand(wav.shape[0],-1)
        elif speaker_embedding.ndim==1:
            speaker_embedding=speaker_embedding[None].expand(wav.shape[0],-1)

        voiced=f0>20.0
        pred_log_f0=self.f0_proj(speaker_embedding).clamp(4.0,5.8)
        if self.training and voiced.any():
            real_meds=[]
            for b in range(f0.shape[0]):
                v=voiced[b]
                med=f0[b,v].median().clamp_min(50.0) if v.any() else torch.tensor(100.0,device=f0.device,dtype=f0.dtype)
                real_meds.append(torch.log(med))
            target_log_f0=torch.stack(real_meds)[:,None]
            vq_loss=vq_loss+.25*F.mse_loss(pred_log_f0,target_log_f0.detach())

        if shift_pitch:
            target_f0_med=torch.exp(pred_log_f0)
            shifted=f0.clone()
            for b in range(f0.shape[0]):
                v=voiced[b]
                if v.any():
                    src_med=f0[b,v].median().clamp_min(50.0)
                    ratio=(target_f0_med[b,0]/src_med).clamp(.55,1.85)
                    shifted[b,v]=(f0[b,v]*ratio).clamp(55.0,450.0)
            f0=shifted

        # No raw source carrier. Harmonic excitation is only a timing/frequency pilot.
        excitation,source_aux=self.source(f0,energy,aperiodic=None,confidence=confidence)
        coarse,tract_aux=self.tract(
            excitation,codes,speaker_embedding,f0=f0,energy=energy,confidence=confidence
        )
        zero_carrier=torch.zeros_like(excitation)
        y=self.refiner(coarse,excitation,zero_carrier,codes,speaker_embedding)
        n=wav.shape[-1]
        if y.shape[-1]<n:y=F.pad(y,(0,n-y.shape[-1]))
        y=y[...,:n]
        aux={
            'indices':indices,'vq_loss':vq_loss,'vq_stats':vq_stats,'codes':codes,
            'f0':f0,'energy':energy,'confidence':confidence,
            'excitation':excitation,'coarse':coarse,
            **source_aux,**tract_aux
        }
        return y,aux

    @torch.inference_mode()
    def convert(self,wav):
        was=self.training;self.eval()
        y,_=self(wav,shift_pitch=True,content_wav=wav)
        if was:self.train()
        return y

    def save(self,path,metadata=None):
        obj={'format':FORMAT,'config':{
             'sample_rate':self.sample_rate,'hop':self.hop,
             'content_dim':self.content_dim,'speaker_dim':self.speaker_dim,
             'harmonics':self.harmonics,'books':self.books,'book_size':self.book_size,
             'long_taps':self.long_taps,'short_taps':self.short_taps},
             'state':{k:v.detach().cpu() for k,v in self.state_dict().items()},
             'metadata':dict(metadata or {})}
        p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);torch.save(obj,p);return p

    @classmethod
    def load(cls,path,device='cpu'):
        obj=torch.load(path,map_location='cpu',weights_only=True)
        if obj.get('format')!=FORMAT:
            raise ValueError('unsupported ARGON Neural 2 generative checkpoint')
        model=cls(**obj['config']).to(device)
        model.load_state_dict(obj['state'],strict=True);model.eval()
        return model,obj.get('metadata',{})
PY

cat > argon_neural_v2/train.py <<'PY'
from __future__ import annotations
import argparse,json,math,random,time
from pathlib import Path
import torch
import torch.nn.functional as F
from .engine import ArgonNeuralV2
from .critic import MicroVoiceCritic,critic_hinge_loss,generator_hinge_loss,feature_matching_loss
from .losses import naturalness_loss
from argon_core.neural_pretrain import build_windows
from argon_core.neural_longtrain import split_validation,_crop

def safe_backward_step(loss,optimizer,params,max_norm):
    params=list(params)
    if not torch.isfinite(loss):
        optimizer.zero_grad(set_to_none=True);return False,float('nan')
    optimizer.zero_grad(set_to_none=True);loss.backward()
    norm=torch.nn.utils.clip_grad_norm_(params,max_norm,error_if_nonfinite=False)
    if not torch.isfinite(norm):
        optimizer.zero_grad(set_to_none=True);return False,float(norm)
    optimizer.step();return True,float(norm)

def _warp_freq(x,ratio):
    b,c,f,t=x.shape
    base=torch.linspace(-1,1,f,device=x.device,dtype=x.dtype)[None,:,None].expand(b,f,t)
    src=((base+1.0)/ratio)-1.0
    tg=torch.linspace(-1,1,t,device=x.device,dtype=x.dtype)[None,None,:].expand(b,f,t)
    grid=torch.stack((tg,src),dim=-1)
    return F.grid_sample(x,grid,mode='bilinear',padding_mode='border',align_corners=True)

@torch.no_grad()
def perturb_timbre(wav,sample_rate=24000,seed=None):
    if wav.ndim==1:wav=wav[None]
    rng=random.Random(seed)
    b,n=wav.shape
    nfft=1024;hop=240;win_len=960
    win=torch.hann_window(win_len,device=wav.device,dtype=wav.dtype)
    Z=torch.stft(wav,n_fft=nfft,hop_length=hop,win_length=win_len,window=win,center=True,return_complex=True)
    mag=Z.abs().clamp_min(1e-6);phase=torch.angle(Z)
    bb,ff,tt=mag.shape
    env=F.avg_pool1d(
        F.pad(mag.transpose(1,2).reshape(bb*tt,1,ff),(18,18),mode='reflect'),
        37,stride=1
    ).reshape(bb,tt,ff).transpose(1,2).clamp_min(1e-5)
    fine=mag/env

    formant_ratio=torch.tensor(rng.uniform(.78,1.24),device=wav.device,dtype=wav.dtype).view(1,1,1)
    pitch_ratio=torch.tensor(rng.uniform(.88,1.12),device=wav.device,dtype=wav.dtype).view(1,1,1)
    warped_env=_warp_freq(env[:,None],formant_ratio)[:,0]
    shifted_fine=_warp_freq(fine[:,None],pitch_ratio)[:,0]

    # Smooth random spectral tilt so the content encoder cannot rely on a fixed vocal colour.
    freqs=torch.linspace(0,1,ff,device=wav.device,dtype=wav.dtype)[None,:,None]
    tilt=rng.uniform(-.55,.55)
    colour=torch.exp(tilt*(freqs-.5))
    new_mag=(warped_env*shifted_fine*colour).clamp_min(1e-7)

    dphi=torch.diff(phase,dim=-1,prepend=phase[...,:1])
    dphi=torch.atan2(torch.sin(dphi),torch.cos(dphi))
    new_phase=torch.cumsum(dphi*pitch_ratio,dim=-1)+phase[...,:1]
    out=torch.istft(torch.polar(new_mag,new_phase),n_fft=nfft,hop_length=hop,win_length=win_len,window=win,length=n)
    rms_in=wav.square().mean(-1,keepdim=True).sqrt().clamp_min(1e-5)
    rms_out=out.square().mean(-1,keepdim=True).sqrt().clamp_min(1e-5)
    out=out*(rms_in/rms_out).clamp(.5,2.0)
    return out.clamp(-1,1)

def micro_slice(real,fake,length=8192,seed=0):
    n=min(real.shape[-1],fake.shape[-1])
    if n<=length:return real[...,:n],fake[...,:n]
    rng=random.Random(seed);start=rng.randrange(0,n-length+1)
    return real[...,start:start+length],fake[...,start:start+length]

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
                    if isinstance(vec,list) and len(vec)==dim:
                        table.weight[i].copy_(torch.tensor(vec,dtype=table.weight.dtype))
        except Exception:pass
    return table,sid

def load_seed_model(path):
    model=ArgonNeuralV2()
    if not path or not Path(path).exists():return model,{'loaded':0,'skipped':0}
    obj=torch.load(path,map_location='cpu',weights_only=True)
    old=obj.get('state',{})
    current=model.state_dict()
    allowed=('content.','source.','f0_proj.','voice')
    compatible={k:v for k,v in old.items()
                if k.startswith(allowed) and k in current and tuple(v.shape)==tuple(current[k].shape)}
    missing=len(current)-len(compatible)
    model.load_state_dict(compatible,strict=False)
    return model,{'loaded':len(compatible),'skipped':missing}

def save_model(model,table,sid,path,meta):
    with torch.no_grad():
        if 'experimental' in sid:model.voice.copy_(table.weight[sid['experimental']:sid['experimental']+1])
        else:model.voice.copy_(table.weight.mean(0,keepdim=True))
    m=dict(meta)
    m['speaker_table']={name:table.weight[i].detach().cpu().tolist() for name,i in sid.items()}
    model.save(path,m)

@torch.no_grad()
def validate(model,table,sid,corpus,valid,n,max_per_speaker=2):
    model.eval();vals=[];per={}
    for speaker,items in valid.items():
        if speaker not in sid or not items:continue
        one=[]
        for j,item in enumerate(items[:max_per_speaker]):
            y=_crop(corpus,item,n)[None]
            content=perturb_timbre(y,model.sample_rate,seed=9000+sid[speaker]*101+j)
            emb=table(torch.tensor([sid[speaker]]))
            pred,aux=model(y,speaker_embedding=emb,content_wav=content)
            l=naturalness_loss(pred,y,model.sample_rate)['total']+.015*aux['vq_loss']
            one.append(float(l))
        if one:per[speaker]=sum(one)/len(one);vals.extend(one)
    model.train()
    return (sum(vals)/len(vals) if vals else float('inf')),per

def train(manifest,output,epochs=50000,steps=48,threads=3,crop=.5,lr=6e-5,
          critic_start=25,val_every=2,checkpoint_every=5,seed=7711,
          seed_speaker_checkpoint=None,seed_model_checkpoint=None):
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
        best=float(old_meta.get('best_val',float('inf')));best_epoch=int(old_meta.get('best_epoch',0))
        seed_stats=old_meta.get('seed_stats',{})
    else:
        model,seed_stats=load_seed_model(seed_model_checkpoint);start_epoch=0
        speaker_seed=seed_speaker_checkpoint or seed_model_checkpoint
        table,sid=init_speaker_table(speakers,model.speaker_dim,speaker_seed)
        best=float('inf');best_epoch=0

    critic=MicroVoiceCritic(periods=(2,3,5,7))
    gen_params=list(model.parameters())+list(table.parameters())
    gopt=torch.optim.AdamW(gen_params,lr=lr,betas=(.8,.99),weight_decay=1e-4)
    dopt=torch.optim.AdamW(critic.parameters(),lr=lr*.3,betas=(.8,.99),weight_decay=1e-5)
    gsched=torch.optim.lr_scheduler.ReduceLROnPlateau(gopt,mode='min',factor=.7,patience=12,min_lr=3e-6)
    dsched=torch.optim.lr_scheduler.ReduceLROnPlateau(dopt,mode='min',factor=.8,patience=18,min_lr=2e-6)

    n=round(crop*24000);history=[];started=time.monotonic()
    for epoch in range(start_epoch+1,int(epochs)+1):
        rng=random.Random(seed+epoch*1009);order=speakers[:];rng.shuffle(order)
        sums={'g':0.,'natural':0.,'vq':0.,'d':0.,'adv':0.,'fm':0.}
        for step in range(int(steps)):
            speaker=order[step%len(order)]
            if step%len(order)==len(order)-1:rng.shuffle(order)
            y=_crop(corpus,rng.choice(train_groups[speaker]),n)[None]
            content=perturb_timbre(y,24000,seed=seed+epoch*100000+step*97+sid[speaker])
            emb=table(torch.tensor([sid[speaker]]))
            pred,aux=model(y,speaker_embedding=emb,content_wav=content)
            nat=naturalness_loss(pred,y,24000)
            gen=nat['total']+.015*aux['vq_loss']

            if epoch>=critic_start:
                real_micro,fake_micro=micro_slice(y,pred,8192,seed+epoch*1000+step)
                real_logits,_=critic(real_micro);fake_logits,_=critic(fake_micro.detach())
                dl=critic_hinge_loss(real_logits,fake_logits)
                d_ok,d_norm=safe_backward_step(dl,dopt,critic.parameters(),1.0)
                for p in critic.parameters():p.requires_grad_(False)
                with torch.no_grad():_,real_features=critic(real_micro)
                fake_logits,fake_features=critic(fake_micro)
                adv=generator_hinge_loss(fake_logits)
                fm=feature_matching_loss(real_features,fake_features)
                gen=gen+.02*adv+.10*fm
                for p in critic.parameters():p.requires_grad_(True)
                sums['d']+=float(dl.detach()) if torch.isfinite(dl) else 0.0
                sums['adv']+=float(adv.detach()) if torch.isfinite(adv) else 0.0
                sums['fm']+=float(fm.detach()) if torch.isfinite(fm) else 0.0

            g_ok,g_norm=safe_backward_step(gen,gopt,gen_params,1.2)
            if not g_ok:
                print('ARGON_V2_SKIP_NONFINITE',json.dumps({
                    'epoch':epoch,'step':step,'g':float(gen.detach()) if torch.isfinite(gen) else 'nan',
                    'grad_norm':g_norm},ensure_ascii=False),flush=True)
            sums['g']+=float(gen.detach()) if torch.isfinite(gen) else 0.0
            sums['natural']+=float(nat['total'].detach()) if torch.isfinite(nat['total']) else 0.0
            sums['vq']+=float(aux['vq_loss'].detach()) if torch.isfinite(aux['vq_loss']) else 0.0

        row={'epoch':epoch,'g_lr':gopt.param_groups[0]['lr'],'d_lr':dopt.param_groups[0]['lr'],
             **{k:v/max(1,steps) for k,v in sums.items()},'seconds':time.monotonic()-started}
        if epoch%val_every==0 or epoch==1:
            val,per=validate(model,table,sid,corpus,valid_groups,n)
            row['val']=val;row['val_by_speaker']=per
            if math.isfinite(val):
                gsched.step(val);dsched.step(val)
                if val<best:
                    best=val;best_epoch=epoch
                    save_model(model,table,sid,out,{
                        'stage':'argon_neural_2_generative_best','epoch':epoch,
                        'best_epoch':best_epoch,'best_val':best,'speakers':speakers,'files':len(corpus),
                        'target_holdout_ranges_seconds':target_holdout,'critic_start':critic_start,
                        'architecture':'ARGON Neural 2.1 Generative','seed_stats':seed_stats})
        history.append(row)
        print('ARGON_V2_GEN_EPOCH',json.dumps(row,ensure_ascii=False),flush=True)
        if epoch%checkpoint_every==0:
            save_model(model,table,sid,latest,{
                'stage':'argon_neural_2_generative_latest','epoch':epoch,
                'best_epoch':best_epoch,'best_val':best,'speakers':speakers,'files':len(corpus),
                'target_holdout_ranges_seconds':target_holdout,'critic_start':critic_start,
                'history_tail':history[-100:],'architecture':'ARGON Neural 2.1 Generative',
                'seed_stats':seed_stats})

def main():
    p=argparse.ArgumentParser();p.add_argument('manifest');p.add_argument('output')
    p.add_argument('--epochs',type=int,default=50000);p.add_argument('--steps',type=int,default=48)
    p.add_argument('--threads',type=int,default=3);p.add_argument('--crop',type=float,default=.5)
    p.add_argument('--lr',type=float,default=6e-5);p.add_argument('--critic-start',type=int,default=25)
    p.add_argument('--val-every',type=int,default=2);p.add_argument('--checkpoint-every',type=int,default=5)
    p.add_argument('--seed-speaker-checkpoint');p.add_argument('--seed-model-checkpoint')
    a=p.parse_args()
    train(a.manifest,a.output,a.epochs,a.steps,a.threads,a.crop,a.lr,a.critic_start,
          a.val_every,a.checkpoint_every,seed_speaker_checkpoint=a.seed_speaker_checkpoint,
          seed_model_checkpoint=a.seed_model_checkpoint)
if __name__=='__main__':main()
PY

# Update the old live-phase test so it no longer depends on an incompatible 2.0 checkpoint.
cat > tests/test_neural_v2_live_phase.py <<'PY'
import unittest,torch
from argon_neural_v2.features import pitch_energy
from argon_neural_v2.engine import ArgonNeuralV2

class LivePhaseTests(unittest.TestCase):
    def test_pitch_boundary_does_not_collapse_into_sub_fmin_bass(self):
        sr=24000
        t=torch.arange(sr,dtype=torch.float32)/sr
        tone=.08*torch.sin(2*torch.pi*145*t)
        x=torch.cat([torch.zeros(sr//5),tone[:sr*3//5],torch.zeros(sr//5)])[None]
        f0,energy,conf=pitch_energy(x,sr,240)
        voiced=f0[f0>20]
        self.assertTrue(voiced.numel()>5)
        self.assertGreaterEqual(float(voiced.min()),60.0)
        self.assertLessEqual(float(voiced.max()),410.0)

    def test_generative_forward_is_finite(self):
        m=ArgonNeuralV2().eval()
        sr=24000
        t=torch.arange(sr//2,dtype=torch.float32)/sr
        x=(.07*torch.sin(2*torch.pi*150*t))[None]
        with torch.inference_mode():
            y,aux=m(x,shift_pitch=True)
        self.assertEqual(y.shape,x.shape)
        self.assertTrue(torch.isfinite(y).all())
        self.assertTrue(torch.isfinite(aux['f0']).all())

if __name__=='__main__':unittest.main()
PY

cat > run-argon-neural-v2.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
exec /srv/era-audio/venv/bin/python -u -m argon_neural_v2.train   'models/ARGON Neural all voices.txt'   'results/ARGON Neural 2 Generative.pt'   --epochs 50000   --steps 48   --threads 3   --crop .5   --lr 0.00006   --critic-start 25   --val-every 2   --checkpoint-every 5   --seed-model-checkpoint 'results/ARGON Neural 2 shortcut branch backup/ARGON Neural 2 Long.pt'   --seed-speaker-checkpoint 'results/ARGON Neural 2 shortcut branch backup/ARGON Neural 2 Long.pt'   > 'results/ARGON Neural 2 generative.log' 2>&1
SH
chmod 755 run-argon-neural-v2.sh

echo '=== COMPILE ==='
python3 -m py_compile argon_neural_v2/tract.py argon_neural_v2/critic.py argon_neural_v2/engine.py argon_neural_v2/train.py

echo '=== GREEN REQUIREMENTS ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest  tests.test_neural_v2_generative  tests.test_neural_v2_live_phase  tests.test_neural_v2_f0_learning  tests.test_neural_v2_review_fix  tests.test_neural_v2_safe_step -v

echo '=== ONE REAL GENERATIVE TRAIN STEP ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
import torch
from argon_core.audio import read_audio
from argon_neural_v2.engine import ArgonNeuralV2
from argon_neural_v2.train import perturb_timbre
from argon_neural_v2.losses import naturalness_loss

torch.set_num_threads(1)
x=read_audio('/srv/ARGON-VC/data/victor_source.wav',24000)[:12000][None]
content=perturb_timbre(x,24000,seed=42)
m=ArgonNeuralV2().train()
emb=torch.randn(1,m.speaker_dim,requires_grad=True)
opt=torch.optim.AdamW(list(m.parameters())+[emb],lr=3e-5)
y,aux=m(x,speaker_embedding=emb,content_wav=content)
loss=naturalness_loss(y,x,24000)['total']+.015*aux['vq_loss']
assert torch.isfinite(loss)
opt.zero_grad(set_to_none=True);loss.backward()
gn=torch.nn.utils.clip_grad_norm_(list(m.parameters())+[emb],1.2)
assert torch.isfinite(torch.as_tensor(gn))
opt.step()
print('GEN_STEP_OK',float(loss.detach()),float(gn))
print('INPUT_DELTA',float((x-content).abs().mean()))
print('OUT_RMS',float(y.detach().square().mean().sqrt()))
print('PARAMS',sum(p.numel() for p in m.parameters()))
PY

echo '=== START GENERATIVE V2 ==='
rm -f 'results/ARGON Neural 2 Generative.pt' 'results/ARGON Neural 2 Generative Latest.pt' 'results/ARGON Neural 2 generative.log'
systemctl start argon-neural-v2.service
sleep 5
systemctl is-active argon-neural-v2.service || true
systemctl --no-pager --full status argon-neural-v2.service | sed -n '1,65p' || true

echo '=== V1 FINAL ==='
systemctl is-active argon-neural-long.service || true
