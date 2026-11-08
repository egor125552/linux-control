#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
rm -rf argon_neural_v2
mkdir -p argon_neural_v2

for f in tests/test_argon_v2_source.py tests/test_argon_v2_content.py tests/test_argon_v2_tract.py tests/test_argon_v2_losses.py tests/test_argon_v2_engine.py; do
  sed -i 's/from argon_v2\./from argon_neural_v2\./g' "$f"
done

cat > argon_neural_v2/__init__.py <<'PY'
from .engine import ArgonNeuralV2
__all__=['ArgonNeuralV2']
PY

cat > argon_neural_v2/features.py <<'PY'
from __future__ import annotations
import torch
import torch.nn.functional as F

@torch.no_grad()
def pitch_energy(wav,sample_rate=24000,hop=240,frame=960,fmin=65.,fmax=430.):
    if wav.ndim==1: wav=wav[None]
    pad=frame//2
    x=F.pad(wav.float(),(pad,pad))
    frames=x.unfold(-1,frame,hop)
    frames=frames-frames.mean(-1,keepdim=True)
    energy=frames.square().mean(-1).sqrt()
    win=torch.hann_window(frame,device=wav.device,dtype=wav.dtype)
    nfft=2048
    spec=torch.fft.rfft(frames*win,n=nfft,dim=-1)
    ac=torch.fft.irfft(spec.abs().square(),n=nfft,dim=-1)
    lo=max(1,int(sample_rate/fmax));hi=min(frame-2,int(sample_rate/fmin))
    region=ac[...,lo:hi+1]
    peak,idx=region.max(-1)
    lag=(idx+lo).float()
    # Small parabolic refinement around the autocorrelation peak.
    idx0=(idx+lo).clamp(1,ac.shape[-1]-2)
    ym=ac.gather(-1,(idx0-1).unsqueeze(-1)).squeeze(-1)
    y0=ac.gather(-1,idx0.unsqueeze(-1)).squeeze(-1)
    yp=ac.gather(-1,(idx0+1).unsqueeze(-1)).squeeze(-1)
    denom=(ym-2*y0+yp)
    delta=.5*(ym-yp)/(denom.abs().clamp_min(1e-6))*denom.sign()
    lag=(lag+delta.clamp(-.5,.5)).clamp_min(1.)
    confidence=peak/ac[...,0].clamp_min(1e-7)
    floor=torch.quantile(energy.flatten(),.18).clamp_min(.0015)
    voiced=(confidence>.22)&(energy>floor*.85)
    f0=sample_rate/lag
    return torch.where(voiced,f0,torch.zeros_like(f0)),energy,confidence.clamp(0,1)

def align_frames(x,frames):
    if x.shape[-1]==frames:return x
    return F.interpolate(x[:,None].float(),size=frames,mode='linear',align_corners=False)[:,0]

def real_aperiodic_carrier(wav):
    if wav.ndim==1:wav=wav[None]
    x=wav.float()
    prev=F.pad(x[...,:-1],(1,0))
    hp=x-.97*prev
    smooth=F.avg_pool1d(F.pad(hp[:,None],(12,12),mode='reflect'),25,stride=1)[:,0]
    hp=hp-smooth
    local=F.avg_pool1d(F.pad(hp.square()[:,None],(120,119),mode='reflect'),240,stride=1)[:,0].sqrt()
    return torch.tanh((hp/local.clamp_min(1e-4))*.55)
PY

cat > argon_neural_v2/source.py <<'PY'
from __future__ import annotations
import math
import torch
import torch.nn as nn
import torch.nn.functional as F

class HarmonicExcitation(nn.Module):
    def __init__(self,sample_rate=24000,hop=240,harmonics=32,channels=96):
        super().__init__()
        self.sample_rate=int(sample_rate);self.hop=int(hop);self.harmonics=int(harmonics)
        self.control=nn.Sequential(
            nn.Conv1d(3,channels,5,padding=2),nn.GELU(),
            nn.Conv1d(channels,channels,5,padding=2),nn.GELU(),
            nn.Conv1d(channels,self.harmonics+2,3,padding=1),
        )
        nn.init.zeros_(self.control[-1].weight)
        nn.init.zeros_(self.control[-1].bias)
        self.global_gain=nn.Parameter(torch.tensor(0.0))

    def _up(self,x,n):
        return F.interpolate(x,size=n,mode='linear',align_corners=False)

    def forward(self,f0,energy,aperiodic=None,confidence=None):
        if f0.ndim!=2 or energy.ndim!=2: raise ValueError('controls must be [batch,frames]')
        frames=f0.shape[-1];n=frames*self.hop
        if confidence is None: confidence=(f0>20).float()
        ctrl=torch.stack(((f0/320.).clamp(0,2),energy.clamp(0,1),confidence.clamp(0,1)),dim=1)
        raw=self.control(ctrl)
        logits=raw[:,:self.harmonics]
        noise_gate=torch.sigmoid(raw[:,self.harmonics:self.harmonics+1])
        breath_gate=torch.sigmoid(raw[:,self.harmonics+1:self.harmonics+2])

        k=torch.arange(1,self.harmonics+1,device=f0.device,dtype=f0.dtype)[None,:,None]
        tilt=(1.0/k)
        amps=tilt*(1+.35*torch.tanh(logits))
        amps=amps/amps.abs().sum(1,keepdim=True).clamp_min(1e-5)

        f=self._up(f0[:,None],n)[:,0].clamp(0,650)
        e=self._up(energy[:,None],n)[:,0].clamp_min(0)
        conf=self._up(confidence[:,None],n)[:,0].clamp(0,1)
        phase=torch.cumsum(2*math.pi*f/self.sample_rate,dim=-1)
        phase_h=phase[:,None,:]*k
        amp_s=self._up(amps,n)
        mask=(k*f[:,None,:] <= self.sample_rate*.48).to(f0.dtype)
        harmonic=(torch.sin(phase_h)*amp_s*mask).sum(1)
        harmonic=harmonic*conf

        if aperiodic is None:
            carrier=torch.zeros_like(harmonic)
        else:
            carrier=aperiodic.to(harmonic.device,harmonic.dtype)
            if carrier.ndim==1: carrier=carrier[None]
            if carrier.shape[-1]!=n:
                carrier=F.interpolate(carrier[:,None],size=n,mode='linear',align_corners=False)[:,0]
        ng=self._up(noise_gate,n)[:,0]
        bg=self._up(breath_gate,n)[:,0]
        # Real turbulence is strongest in unvoiced regions, but a little breath remains in vowels.
        aper_gate=ng*(1-conf)+.10*bg*conf
        y=(harmonic+aper_gate*carrier)*e*torch.exp(.15*torch.tanh(self.global_gain))
        return y,{'harmonic_amplitudes':amps,'noise_gate':noise_gate,'breath_gate':breath_gate}
PY

cat > argon_neural_v2/content.py <<'PY'
from __future__ import annotations
import torch
import torch.nn as nn
import torch.nn.functional as F

class FrameBlock(nn.Module):
    def __init__(self,dim=256,dilation=1):
        super().__init__()
        self.dw=nn.Conv1d(dim,dim,7,padding=3*dilation,dilation=dilation,groups=dim)
        self.norm=nn.GroupNorm(1,dim)
        self.p1=nn.Conv1d(dim,dim*4,1);self.p2=nn.Conv1d(dim*4,dim,1)
        self.gamma=nn.Parameter(torch.ones(1,dim,1)*1e-3)
    def forward(self,x):
        h=self.dw(x);h=self.norm(h);h=self.p2(F.gelu(self.p1(h)))
        return x+self.gamma*h

class ResidualVectorQuantizerV2(nn.Module):
    def __init__(self,dim=256,books=6,book_size=1024,beta=.15):
        super().__init__()
        self.dim=int(dim);self.books=int(books);self.book_size=int(book_size);self.beta=float(beta)
        self.codebooks=nn.Parameter(torch.randn(self.books,self.book_size,self.dim)*.35)

    def forward(self,x):
        flat=F.layer_norm(x.transpose(1,2).contiguous(),(self.dim,))
        residual=flat;total=torch.zeros_like(flat);ids=[];loss=x.new_tensor(0.);usages=[]
        for raw in self.codebooks:
            rms=raw.square().mean(-1,keepdim=True).sqrt().clamp_min(.2)
            book=raw/rms.clamp_min(1.)
            dist=residual.square().sum(-1,keepdim=True)+book.square().sum(-1)[None,None]-2*residual@book.T
            idx=dist.argmin(-1);q=F.embedding(idx,book)
            loss=loss+F.mse_loss(residual.detach(),q)+self.beta*F.mse_loss(residual,q.detach())
            total=total+q;residual=residual-q.detach();ids.append(idx)
            usages.append(x.new_tensor(idx.unique().numel()/self.book_size))
        out=flat+(total-flat).detach()
        stats={'usage':torch.stack(usages).mean(),'usage_per_book':torch.stack(usages)}
        return out.transpose(1,2),torch.stack(ids,1),loss/self.books,stats

class DeepContentEncoder(nn.Module):
    def __init__(self,sample_rate=24000,hop=240,dim=256,books=6,book_size=1024,frame_dropout=.12):
        super().__init__()
        self.sample_rate=int(sample_rate);self.hop=int(hop);self.dim=int(dim);self.frame_dropout=float(frame_dropout)
        self.specs=((512,480),(1024,960))
        bins=sum(n//2+1 for n,w in self.specs)
        self.in_proj=nn.Conv1d(bins,dim,1)
        self.blocks=nn.ModuleList([FrameBlock(dim,d) for d in (1,2,4,8,1,2,4,8,1,2)])
        self.out_norm=nn.GroupNorm(1,dim)
        self.rvq=ResidualVectorQuantizerV2(dim,books,book_size)

    def _spec(self,wav,nfft,win):
        window=torch.hann_window(win,device=wav.device,dtype=wav.dtype)
        z=torch.stft(wav,n_fft=nfft,hop_length=self.hop,win_length=win,window=window,center=True,return_complex=True)
        m=torch.log1p(z.abs())
        m=m-m.mean(1,keepdim=True)
        return m/m.std(1,keepdim=True).clamp_min(.12)

    def forward(self,wav):
        if wav.ndim==1:wav=wav[None]
        feats=[self._spec(wav,n,w) for n,w in self.specs]
        frames=min(x.shape[-1] for x in feats)
        h=self.in_proj(torch.cat([x[...,:frames] for x in feats],dim=1))
        for block in self.blocks:h=block(h)
        h=self.out_norm(h)
        if self.training and self.frame_dropout>0:
            keep=(torch.rand(h.shape[0],1,h.shape[-1],device=h.device)>=self.frame_dropout).to(h.dtype)
            h=h*keep
        return self.rvq(h)
PY

cat > argon_neural_v2/tract.py <<'PY'
from __future__ import annotations
import torch
import torch.nn as nn
import torch.nn.functional as F

class ConditionedBlock(nn.Module):
    def __init__(self,dim=256,speaker_dim=192,dilation=1):
        super().__init__()
        self.dw=nn.Conv1d(dim,dim,7,padding=3*dilation,dilation=dilation,groups=dim)
        self.norm=nn.GroupNorm(1,dim)
        self.film=nn.Linear(speaker_dim,dim*2)
        self.p1=nn.Conv1d(dim,dim*4,1);self.p2=nn.Conv1d(dim*4,dim,1)
        self.gamma=nn.Parameter(torch.ones(1,dim,1)*1e-3)
    def forward(self,x,spk):
        h=self.norm(self.dw(x))
        scale,bias=self.film(spk).chunk(2,-1)
        h=h*(1+.15*torch.tanh(scale)[:,:,None])+.15*bias[:,:,None]
        h=self.p2(F.gelu(self.p1(h)))
        return x+self.gamma*h

def dynamic_fir(x,ir):
    n=x.shape[-1];taps=ir.shape[1]
    ir_s=F.interpolate(ir,size=n,mode='linear',align_corners=False)
    pad=taps//2
    win=F.pad(x,(pad,pad)).unfold(-1,taps,1)
    return (win*ir_s.transpose(1,2)).sum(-1)

class DeepVocalTract(nn.Module):
    def __init__(self,dim=256,speaker_dim=192,hop=240,long_taps=129,short_taps=31):
        super().__init__()
        self.dim=int(dim);self.speaker_dim=int(speaker_dim);self.hop=int(hop)
        self.long_taps=int(long_taps);self.short_taps=int(short_taps)
        self.speaker_in=nn.Linear(speaker_dim,dim)
        self.blocks=nn.ModuleList([ConditionedBlock(dim,speaker_dim,d) for d in (1,2,4,8,1,2,4,8,1,2)])
        self.long_head=nn.Conv1d(dim,long_taps,1)
        self.short_head=nn.Conv1d(dim,short_taps,1)
        self.gain_head=nn.Conv1d(dim,1,1)
        for head in (self.long_head,self.short_head,self.gain_head):
            nn.init.zeros_(head.weight);nn.init.zeros_(head.bias)

    def _make_ir(self,raw,taps,strength):
        raw=torch.tanh(raw);center=taps//2
        delta=torch.zeros_like(raw);delta[:,center:center+1]=1
        ir=delta+strength*raw
        return ir/ir.abs().sum(1,keepdim=True).clamp_min(.35)

    def forward(self,excitation,codes,speaker_embedding):
        h=codes+self.speaker_in(speaker_embedding)[:,:,None]
        for block in self.blocks:h=block(h,speaker_embedding)
        long_ir=self._make_ir(self.long_head(h),self.long_taps,.22)
        short_ir=self._make_ir(self.short_head(h),self.short_taps,.14)
        gain=torch.exp(.40*torch.tanh(self.gain_head(h)))
        y=dynamic_fir(excitation,long_ir)
        y=dynamic_fir(y,short_ir)
        gain_s=F.interpolate(gain,size=y.shape[-1],mode='linear',align_corners=False)[:,0]
        y=y*gain_s
        return y,{'long_ir':long_ir,'short_ir':short_ir,'gain':gain}
PY

cat > argon_neural_v2/postfilter.py <<'PY'
from __future__ import annotations
import torch
import torch.nn as nn
import torch.nn.functional as F

class WaveBlock(nn.Module):
    def __init__(self,channels=64,dilation=1):
        super().__init__()
        self.dw=nn.Conv1d(channels,channels,5,padding=2*dilation,dilation=dilation,groups=channels)
        self.norm=nn.GroupNorm(8,channels)
        self.p1=nn.Conv1d(channels,channels*2,1);self.p2=nn.Conv1d(channels*2,channels,1)
        self.gamma=nn.Parameter(torch.ones(1,channels,1)*1e-3)
    def forward(self,x):
        h=self.dw(x);h=self.norm(h);h=self.p2(F.gelu(self.p1(h)))
        return x+self.gamma*h

class WaveformRefiner(nn.Module):
    def __init__(self,content_dim=256,speaker_dim=192,channels=64,hop=240):
        super().__init__();self.hop=int(hop)
        self.audio_in=nn.Conv1d(3,channels,7,padding=3)
        self.content=nn.Conv1d(content_dim,channels,1)
        self.speaker=nn.Linear(speaker_dim,channels)
        self.blocks=nn.ModuleList([WaveBlock(channels,d) for d in (1,3,9,27,1,3,9,27)])
        self.out=nn.Conv1d(channels,1,7,padding=3)
        nn.init.zeros_(self.out.weight);nn.init.zeros_(self.out.bias)
        self.residual_scale=nn.Parameter(torch.tensor(-1.4))

    def forward(self,coarse,excitation,carrier,codes,speaker_embedding):
        n=coarse.shape[-1]
        def fit(x):
            if x.shape[-1]==n:return x
            return F.interpolate(x[:,None],size=n,mode='linear',align_corners=False)[:,0]
        excitation=fit(excitation);carrier=fit(carrier)
        audio=torch.stack((coarse,excitation,carrier),dim=1)
        h=self.audio_in(audio)
        cond=F.interpolate(self.content(codes),size=n,mode='linear',align_corners=False)
        h=h+cond+self.speaker(speaker_embedding)[:,:,None]
        for block in self.blocks:h=block(h)
        residual=torch.tanh(self.out(h)[:,0])
        return coarse+torch.sigmoid(self.residual_scale)*residual
PY

cat > argon_neural_v2/critic.py <<'PY'
from __future__ import annotations
import torch
import torch.nn as nn
import torch.nn.functional as F

class PeriodCritic(nn.Module):
    def __init__(self,period):
        super().__init__();self.period=int(period)
        chans=(1,16,32,64,128)
        self.layers=nn.ModuleList([
            nn.Conv2d(chans[i],chans[i+1],(5,1),stride=(3,1),padding=(2,0))
            for i in range(len(chans)-1)
        ])
        self.out=nn.Conv2d(chans[-1],1,(3,1),padding=(1,0))
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

class MultiPeriodCritic(nn.Module):
    def __init__(self,periods=(2,3,5,7,11)):
        super().__init__();self.periods=tuple(periods)
        self.critics=nn.ModuleList([PeriodCritic(p) for p in self.periods])
    def forward(self,x):
        logits=[];features=[]
        for c in self.critics:
            l,f=c(x);logits.append(l);features.append(f)
        return logits,features

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
        for r,f in zip(rr,ff):vals.append(F.l1_loss(f,r.detach()))
    return sum(vals)/max(1,len(vals))
PY

cat > argon_neural_v2/losses.py <<'PY'
from __future__ import annotations
import torch
import torch.nn.functional as F

def _stft(x,nfft,hop,win):
    if x.ndim==1:x=x[None]
    w=torch.hann_window(win,device=x.device,dtype=x.dtype)
    return torch.stft(x,n_fft=nfft,hop_length=hop,win_length=win,window=w,center=True,return_complex=True)

def multi_resolution_spectral(pred,target):
    vals=[];logs=[];phases=[]
    for nfft,hop,win in ((256,60,240),(512,120,480),(1024,240,960),(2048,480,1920)):
        p=_stft(pred,nfft,hop,win);t=_stft(target,nfft,hop,win)
        pm=p.abs().clamp_min(1e-6);tm=t.abs().clamp_min(1e-6)
        vals.append((pm-tm).norm(p='fro')/tm.norm(p='fro').clamp_min(1e-6))
        logs.append(F.l1_loss(torch.log(pm),torch.log(tm)))
        cos=(p*t.conj()).real/(pm*tm)
        weight=(tm/tm.mean().clamp_min(1e-6)).clamp(max=4)
        phases.append(((1-cos.clamp(-1,1))*weight).mean())
    return sum(vals)/4+0.35*sum(logs)/4+0.04*sum(phases)/4

def envelope_loss(pred,target,sr=24000):
    p=torch.log1p(_stft(pred,1024,240,960).abs())
    t=torch.log1p(_stft(target,1024,240,960).abs())
    def smooth(m):
        b,f,n=m.shape
        z=m.transpose(1,2).reshape(b*n,1,f)
        z=F.avg_pool1d(F.pad(z,(12,12),mode='reflect'),25,stride=1)
        return z.reshape(b,n,f)
    return (1-F.cosine_similarity(smooth(p),smooth(t),dim=-1)).mean()

def highband_loss(pred,target,sr=24000):
    p=_stft(pred,1024,240,960).abs().square();t=_stft(target,1024,240,960).abs().square()
    freqs=torch.linspace(0,sr/2,p.shape[-2],device=p.device)
    vals=[]
    for lo,hi in ((3500,6000),(6000,9000),(9000,min(12000,sr/2))):
        m=(freqs>=lo)&(freqs<=hi)
        pe=torch.log(p[:,m].mean((-2,-1)).clamp_min(1e-8))
        te=torch.log(t[:,m].mean((-2,-1)).clamp_min(1e-8))
        vals.append(F.l1_loss(pe,te))
    return sum(vals)/len(vals)

def transient_loss(pred,target):
    dp=torch.diff(pred,dim=-1);dt=torch.diff(target,dim=-1)
    d2p=torch.diff(dp,dim=-1);d2t=torch.diff(dt,dim=-1)
    return F.l1_loss(dp,dt)+.5*F.l1_loss(d2p,d2t)

def naturalness_loss(pred,target,sr=24000):
    n=min(pred.shape[-1],target.shape[-1]);pred=pred[...,:n];target=target[...,:n]
    spectral=multi_resolution_spectral(pred,target)
    envelope=envelope_loss(pred,target,sr)
    highband=highband_loss(pred,target,sr)
    transient=transient_loss(pred,target)
    loud=(torch.log(pred.square().mean().sqrt().clamp_min(1e-6))-
          torch.log(target.square().mean().sqrt().clamp_min(1e-6))).abs()
    total=spectral+.55*envelope+.18*highband+1.5*transient+.08*loud
    return {'total':total,'spectral':spectral,'envelope':envelope,'highband':highband,
            'transient':transient,'loudness':loud}
PY

cat > argon_neural_v2/engine.py <<'PY'
from __future__ import annotations
from pathlib import Path
import torch
import torch.nn as nn
import torch.nn.functional as F
from .features import pitch_energy,align_frames,real_aperiodic_carrier
from .source import HarmonicExcitation
from .content import DeepContentEncoder
from .tract import DeepVocalTract
from .postfilter import WaveformRefiner

FORMAT='ARGON-NEURAL-2.0'

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

    def forward(self,wav,speaker_embedding=None):
        if wav.ndim==1:wav=wav[None]
        codes,indices,vq_loss,vq_stats=self.content(wav)
        f0,energy,confidence=pitch_energy(wav,self.sample_rate,self.hop)
        f0=align_frames(f0,codes.shape[-1]);energy=align_frames(energy,codes.shape[-1])
        confidence=align_frames(confidence,codes.shape[-1])
        carrier=real_aperiodic_carrier(wav)
        excitation,source_aux=self.source(f0,energy,carrier,confidence)
        if speaker_embedding is None:
            speaker_embedding=self.voice.expand(wav.shape[0],-1)
        elif speaker_embedding.ndim==1:
            speaker_embedding=speaker_embedding[None].expand(wav.shape[0],-1)
        coarse,tract_aux=self.tract(excitation,codes,speaker_embedding)
        y=self.refiner(coarse,excitation,carrier,codes,speaker_embedding)
        n=wav.shape[-1]
        if y.shape[-1]<n:y=F.pad(y,(0,n-y.shape[-1]))
        y=y[...,:n]
        aux={'indices':indices,'vq_loss':vq_loss,'vq_stats':vq_stats,'codes':codes,
             'f0':f0,'energy':energy,'confidence':confidence,'carrier':carrier,
             'excitation':excitation,'coarse':coarse,**source_aux,**tract_aux}
        return y,aux

    @torch.inference_mode()
    def convert(self,wav):
        was=self.training;self.eval();y,_=self(wav)
        if was:self.train()
        return y

    def save(self,path,metadata=None):
        obj={'format':FORMAT,'config':{'sample_rate':self.sample_rate,'hop':self.hop,
             'content_dim':self.content_dim,'speaker_dim':self.speaker_dim,
             'harmonics':self.harmonics,'books':self.books,'book_size':self.book_size,
             'long_taps':self.long_taps,'short_taps':self.short_taps},
             'state':{k:v.detach().cpu() for k,v in self.state_dict().items()},
             'metadata':dict(metadata or {})}
        p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);torch.save(obj,p);return p

    @classmethod
    def load(cls,path,device='cpu'):
        obj=torch.load(path,map_location='cpu',weights_only=True)
        if obj.get('format')!=FORMAT:raise ValueError('unsupported ARGON Neural 2 checkpoint')
        model=cls(**obj['config']).to(device);model.load_state_dict(obj['state']);model.eval()
        return model,obj.get('metadata',{})
PY

python3 -m py_compile argon_neural_v2/*.py

echo '=== GREEN TESTS ==='
OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest  tests.test_argon_v2_source tests.test_argon_v2_content tests.test_argon_v2_tract  tests.test_argon_v2_losses tests.test_argon_v2_engine -v

echo '=== MODEL SIZE ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
from argon_neural_v2.engine import ArgonNeuralV2
m=ArgonNeuralV2()
print('PARAMETERS',sum(p.numel() for p in m.parameters()))
print('TRAINING_V1_ACTIVE_CHECK_FOLLOWS')
PY

systemctl is-active argon-neural-long.service || true
ps -eo pid,etime,%cpu,%mem,args | grep 'argon_core.neural_continue' | grep -v grep || true
