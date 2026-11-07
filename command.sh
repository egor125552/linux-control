#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

cat > argon_core/neural_features.py <<'PY'
from __future__ import annotations
import torch
import torch.nn.functional as F

@torch.no_grad()
def pitch_energy(wav,sample_rate=24000,hop=240,frame=960,fmin=70.,fmax=400.):
    if wav.ndim==1:wav=wav[None]
    pad=frame//2
    x=F.pad(wav.float(),(pad,pad))
    frames=x.unfold(-1,frame,hop)
    frames=frames-frames.mean(-1,keepdim=True)
    energy=frames.square().mean(-1).sqrt()
    win=torch.hann_window(frame,device=wav.device,dtype=wav.dtype)
    nfft=2048
    spec=torch.fft.rfft(frames*win,n=nfft,dim=-1)
    ac=torch.fft.irfft(spec.abs().square(),n=nfft,dim=-1)
    lo=max(1,int(sample_rate/fmax));hi=min(frame-1,int(sample_rate/fmin))
    region=ac[...,lo:hi+1]
    peak,idx=region.max(-1)
    lag=idx+lo
    confidence=peak/ac[...,0].clamp_min(1e-7)
    floor=torch.quantile(energy.flatten(),.20).clamp_min(.0015)
    voiced=(confidence>.24)&(energy>floor*.9)
    f0=sample_rate/lag.float()
    f0=torch.where(voiced,f0,torch.zeros_like(f0))
    return f0,energy

def align_frames(x,frames):
    if x.shape[-1]==frames:return x
    return F.interpolate(x[:,None].float(),size=frames,mode='linear',align_corners=False)[:,0]

def real_aperiodic_carrier(wav):
    """Extract real consonant/breath turbulence from the input waveform, no random noise."""
    if wav.ndim==1:wav=wav[None]
    x=wav.float()
    prev=F.pad(x[...,:-1],(1,0))
    hp=x-.97*prev
    smooth=F.avg_pool1d(F.pad(hp[:,None],(12,12),mode='reflect'),25,stride=1)[:,0]
    hp=hp-smooth
    local=F.avg_pool1d(F.pad(hp.square()[:,None],(120,119),mode='reflect'),240,stride=1)[:,0].sqrt()
    hp=hp/local.clamp_min(1e-4)
    return torch.tanh(hp*.55)
PY

cat > argon_core/source.py <<'PY'
from __future__ import annotations
import math
import torch
import torch.nn as nn
import torch.nn.functional as F

class GlottalExcitationNet(nn.Module):
    """Differentiable glottal pulse source with real aperiodic carrier from input speech."""
    def __init__(self,sample_rate=24000,hop=240,channels=64,kernel=7):
        super().__init__()
        self.sample_rate=int(sample_rate);self.hop=int(hop)
        pad=kernel//2
        self.net=nn.Sequential(
            nn.Conv1d(5,channels,kernel,padding=pad),nn.GELU(),
            nn.Conv1d(channels,channels,kernel,padding=pad),nn.GELU(),
            nn.Conv1d(channels,1,kernel,padding=pad),
        )
        nn.init.zeros_(self.net[-1].weight);nn.init.zeros_(self.net[-1].bias)
        self.aperiodic_gain=nn.Parameter(torch.tensor(-.2))
        self.micro_gain=nn.Parameter(torch.tensor(-2.0))

    def _upsample(self,x,n):
        return F.interpolate(x[:,None].float(),size=n,mode='linear',align_corners=False)[:,0]

    def forward(self,f0,energy,aperiodic=None):
        if f0.ndim!=2 or energy.ndim!=2:raise ValueError('f0 and energy must be [batch, frames]')
        if f0.shape!=energy.shape:raise ValueError('f0 and energy shape mismatch')
        n=f0.shape[-1]*self.hop
        f=self._upsample(f0,n).clamp(0,600)
        e=self._upsample(energy,n).clamp_min(0)
        voiced=(f>20).float()
        phase=torch.cumsum(2*math.pi*f/self.sample_rate,dim=-1)
        cycle=torch.remainder(phase/(2*math.pi),1.0)
        oq=.62
        opened=torch.sin(math.pi*(cycle/oq).clamp(0,1)).square()
        closure=-.35*torch.exp(-10*(cycle-oq).clamp_min(0))
        pulse=torch.where(cycle<oq,opened,closure)*voiced

        if aperiodic is None:
            carrier=torch.zeros_like(pulse)
        else:
            carrier=aperiodic.to(pulse.device,pulse.dtype)
            if carrier.ndim==1:carrier=carrier[None]
            if carrier.shape[-1]!=n:
                carrier=F.interpolate(carrier[:,None],size=n,mode='linear',align_corners=False)[:,0]
            carrier=carrier/carrier.std(-1,keepdim=True).clamp_min(.15)
            carrier=torch.tanh(carrier)
        # Real turbulence dominates unvoiced consonants and is only lightly retained in vowels.
        gate=(.08*voiced+1.0*(1-voiced))*torch.sigmoid(self.aperiodic_gain)
        base=(pulse+gate*carrier)*e

        f_norm=(f/300.).clamp(0,2)
        de=F.pad(torch.diff(e,dim=-1),(1,0))
        x=torch.stack((base,f_norm,e,voiced,de),dim=1)
        micro=torch.tanh(self.net(x)[:,0])
        return base+torch.sigmoid(self.micro_gain)*micro*e
PY

cat > argon_core/bottleneck.py <<'PY'
from __future__ import annotations
import torch
import torch.nn as nn
import torch.nn.functional as F

class ResidualVectorQuantizer(nn.Module):
    def __init__(self,dim=192,num_quantizers=4,codebook_size=1024,beta=.18):
        super().__init__()
        self.dim=int(dim);self.num_quantizers=int(num_quantizers)
        self.codebook_size=int(codebook_size);self.beta=float(beta)
        # Match the GroupNorm encoder scale instead of tiny 1/sqrt(dim) vectors.
        self.codebooks=nn.Parameter(torch.randn(self.num_quantizers,self.codebook_size,self.dim)*.45)

    def forward(self,x):
        if x.ndim!=3 or x.shape[1]!=self.dim:raise ValueError('RVQ input must be [batch, dim, frames]')
        flat=x.transpose(1,2).contiguous()
        flat=F.layer_norm(flat,(self.dim,))
        residual=flat
        total=torch.zeros_like(flat);ids=[];loss=x.new_tensor(0.)
        for book_raw in self.codebooks:
            # Bound codebook scale so it cannot explode during long training.
            scale=book_raw.square().mean(-1,keepdim=True).sqrt().clamp_min(.15)
            book=book_raw/scale.clamp_min(1.0)
            r2=residual.square().sum(-1,keepdim=True);b2=book.square().sum(-1)[None,None]
            dist=r2+b2-2*torch.matmul(residual,book.T)
            idx=dist.argmin(-1);q=F.embedding(idx,book)
            loss=loss+F.mse_loss(residual.detach(),q)+self.beta*F.mse_loss(residual,q.detach())
            total=total+q;residual=residual-q.detach();ids.append(idx)
        out=flat+(total-flat).detach()
        return out.transpose(1,2),torch.stack(ids,1),loss/self.num_quantizers

class AcousticBottleneck(nn.Module):
    def __init__(self,sample_rate=24000,hop=240,dim=192,frame_dropout=.18,
                 num_quantizers=4,codebook_size=1024):
        super().__init__()
        self.sample_rate=int(sample_rate);self.hop=int(hop);self.dim=int(dim)
        self.n_fft=512;self.win_length=480;self.frame_dropout=float(frame_dropout)
        bins=self.n_fft//2+1
        self.encoder=nn.Sequential(
            nn.Conv1d(bins,256,5,padding=2),nn.GroupNorm(8,256),nn.GELU(),
            nn.Conv1d(256,dim,5,padding=2),nn.GroupNorm(8,dim),nn.GELU(),
            nn.Conv1d(dim,dim,3,padding=1),
        )
        self.rvq=ResidualVectorQuantizer(dim,num_quantizers,codebook_size)

    def features(self,wav):
        if wav.ndim==1:wav=wav[None]
        window=torch.hann_window(self.win_length,device=wav.device,dtype=wav.dtype)
        z=torch.stft(wav,n_fft=self.n_fft,hop_length=self.hop,win_length=self.win_length,
                     window=window,center=True,return_complex=True)
        mag=torch.log1p(z.abs())
        mag=mag-mag.mean(1,keepdim=True)
        mag=mag/(mag.std(1,keepdim=True).clamp_min(.15))
        return mag

    def forward(self,wav):
        h=self.encoder(self.features(wav))
        if self.training and self.frame_dropout>0:
            keep=(torch.rand(h.shape[0],1,h.shape[-1],device=h.device)>=self.frame_dropout).to(h.dtype)
            h=h*keep
        return self.rvq(h)
PY

cat > argon_core/neural_engine.py <<'PY'
from __future__ import annotations
from pathlib import Path
import torch
import torch.nn as nn
from .source import GlottalExcitationNet
from .bottleneck import AcousticBottleneck
from .filter import NeuralVocalTract
from .neural_features import pitch_energy,align_frames,real_aperiodic_carrier

FORMAT='ARGON-NEURAL-SOURCE-FILTER-1.1'

class ArgonSourceFilter(nn.Module):
    def __init__(self,sample_rate=24000,hop=240,dim=192,speaker_dim=128,fir_taps=63):
        super().__init__()
        self.sample_rate=int(sample_rate);self.hop=int(hop)
        self.dim=int(dim);self.speaker_dim=int(speaker_dim);self.fir_taps=int(fir_taps)
        self.bottleneck=AcousticBottleneck(self.sample_rate,self.hop,self.dim)
        self.source=GlottalExcitationNet(self.sample_rate,self.hop)
        self.tract=NeuralVocalTract(self.dim,self.speaker_dim,self.fir_taps,self.hop)
        self.voice=nn.Parameter(torch.randn(1,self.speaker_dim)*.02)

    def forward(self,wav,speaker_embedding=None):
        if wav.ndim==1:wav=wav[None]
        codes,indices,vq_loss=self.bottleneck(wav)
        f0,energy=pitch_energy(wav,self.sample_rate,self.hop)
        f0=align_frames(f0,codes.shape[-1]);energy=align_frames(energy,codes.shape[-1])
        carrier=real_aperiodic_carrier(wav)
        excitation=self.source(f0,energy,aperiodic=carrier)
        if speaker_embedding is None:
            speaker_embedding=self.voice.expand(wav.shape[0],-1)
        elif speaker_embedding.ndim==1:
            speaker_embedding=speaker_embedding[None].expand(wav.shape[0],-1)
        out,ir=self.tract(excitation,codes,speaker_embedding)
        n=wav.shape[-1]
        if out.shape[-1]<n:out=torch.nn.functional.pad(out,(0,n-out.shape[-1]))
        out=out[...,:n]
        return out,{'codes':codes,'indices':indices,'vq_loss':vq_loss,'f0':f0,'energy':energy,
                    'excitation':excitation,'ir':ir,'aperiodic':carrier}

    @torch.inference_mode()
    def convert(self,wav,seed=2026):
        was=self.training;self.eval();y,_=self(wav)
        if was:self.train()
        return y

    def save(self,path,metadata=None):
        obj={'format':FORMAT,'config':{'sample_rate':self.sample_rate,'hop':self.hop,'dim':self.dim,
             'speaker_dim':self.speaker_dim,'fir_taps':self.fir_taps},
             'state':{k:v.detach().cpu() for k,v in self.state_dict().items()},
             'metadata':dict(metadata or {})}
        p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);torch.save(obj,p);return p

    @classmethod
    def load(cls,path,device='cpu'):
        obj=torch.load(path,map_location='cpu',weights_only=True)
        fmt=obj.get('format')
        if fmt not in (FORMAT,'ARGON-NEURAL-SOURCE-FILTER-1.0'):raise ValueError('unsupported ARGON Neural checkpoint')
        model=cls(**obj['config']).to(device)
        model.load_state_dict(obj['state'],strict=False);model.eval()
        return model,obj.get('metadata',{})
PY

cat > argon_core/neural_pretrain.py <<'PY'
from __future__ import annotations
import argparse,hashlib,json,random,time
from pathlib import Path
import torch
import torch.nn as nn
from .audio import read_audio
from .neural_engine import ArgonSourceFilter
from .neural_train import find_speech_phrases,choose_holdout,overlaps,_normalize
from .losses import anti_robot_loss

TARGET_NAME='Экспериментальный голос.mp3'

def speaker_name(path):
    s=str(path).lower()
    if 'экспериментальный голос' in s:return 'experimental'
    if 'александр' in s or 'alexander' in s:return 'alexander'
    if 'учёный' in s or 'учен' in s or 'scientist' in s:return 'scientist'
    if 'виктор' in s or 'victor' in s:return 'victor'
    return path.parent.name+' :: '+path.stem.split(' ')[0]

def dedupe_paths(paths):
    out=[];seen=set()
    for p in paths:
        p=Path(p)
        if not p.exists():continue
        st=p.stat();h=hashlib.sha1()
        with p.open('rb') as f:
            for _ in range(4):
                b=f.read(1024*1024)
                if not b:break
                h.update(b)
        key=(st.st_size,h.hexdigest())
        if key in seen:continue
        seen.add(key);out.append(p)
    return out

def build_windows(paths,sr=24000,crop_seconds=.75,stride_seconds=1.5):
    corpus=[];target_holdout=None
    for p in dedupe_paths(paths):
        audio=read_audio(p,sr)
        phrases=find_speech_phrases(audio,sr,min_seconds=.8,max_seconds=8)
        hold=[]
        if p.name==TARGET_NAME:
            hold=choose_holdout(phrases,4);target_holdout=hold
        usable=[r for r in phrases if not any(overlaps(r,h,.35) for h in hold)]
        n=round(crop_seconds*sr);stride=max(n,round(stride_seconds*sr))
        windows=[]
        for a,b in usable:
            lo=round(a*sr);hi=round(b*sr)
            pos=lo
            while pos+n<=hi:
                windows.append(pos);pos+=stride
        if not windows and len(audio)>=n:windows=[0]
        corpus.append({'path':p,'speaker':speaker_name(p),'audio':audio,'windows':windows})
    return corpus,target_holdout

def pretrain(paths,output,epochs=2,device='cpu',threads=4,crop_seconds=.75,lr=1.5e-4):
    torch.manual_seed(4401);torch.set_num_threads(max(1,int(threads)))
    sr=24000;corpus,holdout=build_windows(paths,sr,crop_seconds)
    speakers=sorted({x['speaker'] for x in corpus});sid={s:i for i,s in enumerate(speakers)}
    table=nn.Embedding(len(speakers),128).to(device)
    nn.init.normal_(table.weight,std=.08)
    model=ArgonSourceFilter(sr,240).to(device).train()
    opt=torch.optim.AdamW(list(model.parameters())+list(table.parameters()),lr=lr,weight_decay=1e-4)
    items=[(ci,pos) for ci,c in enumerate(corpus) for pos in c['windows']]
    if not items:raise RuntimeError('no speech windows for pretraining')
    n=round(crop_seconds*sr);history=[];started=time.monotonic()
    for epoch in range(1,int(epochs)+1):
        rnd=random.Random(4401+epoch);rnd.shuffle(items)
        sums={'total':0.,'spectral':0.,'subband':0.,'envelope':0.,'vq':0.};steps=0
        for ci,pos in items:
            c=corpus[ci];y=_normalize(c['audio'][pos:pos+n])[None].to(device)
            spk=table(torch.tensor([sid[c['speaker']]],device=device))
            pred,aux=model(y,speaker_embedding=spk)
            losses=anti_robot_loss(pred,y,sr)
            total=losses['total']+.02*aux['vq_loss']
            if not torch.isfinite(total):raise RuntimeError('non-finite pretrain loss')
            opt.zero_grad(set_to_none=True);total.backward()
            torch.nn.utils.clip_grad_norm_(list(model.parameters())+list(table.parameters()),2.0)
            opt.step()
            sums['total']+=float(total.detach());sums['vq']+=float(aux['vq_loss'].detach())
            for k in ('spectral','subband','envelope'):sums[k]+=float(losses[k].detach())
            steps+=1
        row={'epoch':epoch,'steps':steps,**{k:v/max(1,steps) for k,v in sums.items()},
             'seconds':time.monotonic()-started}
        history.append(row);print('ARGON_BASE_EPOCH',json.dumps(row,ensure_ascii=False),flush=True)
    target_id=sid.get('experimental')
    with torch.no_grad():
        if target_id is not None:model.voice.copy_(table.weight[target_id:target_id+1])
        else:model.voice.copy_(table.weight.mean(0,keepdim=True))
    meta={'architecture':'ARGON Source-Filter Neural Net pure PyTorch','stage':'base_pretraining',
          'files':[str(c['path']) for c in corpus],'speakers':speakers,'unique_files':len(corpus),
          'speech_windows':len(items),'crop_seconds':crop_seconds,'target_holdout_ranges_seconds':holdout,
          'history':history,'no_random_source_noise':True}
    model.save(output,meta);return model,meta

def main():
    p=argparse.ArgumentParser();p.add_argument('manifest');p.add_argument('output')
    p.add_argument('--epochs',type=int,default=2);p.add_argument('--threads',type=int,default=4)
    p.add_argument('--crop',type=float,default=.75);p.add_argument('--lr',type=float,default=1.5e-4)
    a=p.parse_args()
    paths=[Path(x.strip()) for x in Path(a.manifest).read_text().splitlines() if x.strip()]
    pretrain(paths,a.output,a.epochs,'cpu',a.threads,a.crop,a.lr)
if __name__=='__main__':main()
PY

python3 - <<'PY'
from pathlib import Path
p=Path('argon_core/neural_train.py')
s=p.read_text()
s=s.replace("def train(target,output,epochs=8,steps_per_epoch=28,device='cpu',threads=4,\n          crop_seconds=.5,lr=2e-4,seed=3407):",
"def train(target,output,epochs=8,steps_per_epoch=28,device='cpu',threads=4,\n          crop_seconds=.5,lr=2e-4,seed=3407,base_checkpoint=None):")
s=s.replace("    model=ArgonSourceFilter(sr,240).to(device).train()",
"    if base_checkpoint:\n        model,base_meta=ArgonSourceFilter.load(base_checkpoint,device)\n        model.train()\n    else:\n        model=ArgonSourceFilter(sr,240).to(device).train()")
s=s.replace("          'history':history,'architecture':'ARGON Source-Filter Neural Net, pure PyTorch'}",
"          'history':history,'architecture':'ARGON Source-Filter Neural Net, pure PyTorch',\n          'base_checkpoint':str(base_checkpoint) if base_checkpoint else None}")
s=s.replace("    p.add_argument('--crop',type=float,default=.5);p.add_argument('--lr',type=float,default=2e-4)",
"    p.add_argument('--crop',type=float,default=.5);p.add_argument('--lr',type=float,default=2e-4);p.add_argument('--base')")
s=s.replace("    train(a.target,a.output,a.epochs,a.steps,a.device,a.threads,a.crop,a.lr)",
"    train(a.target,a.output,a.epochs,a.steps,a.device,a.threads,a.crop,a.lr,base_checkpoint=a.base)")
p.write_text(s)
PY

cat > tests/test_neural_real_aperiodic.py <<'PY'
import unittest,torch
from argon_core.source import GlottalExcitationNet
from argon_core.neural_features import real_aperiodic_carrier
from argon_core.neural_engine import ArgonSourceFilter

class RealAperiodicTests(unittest.TestCase):
    def test_source_has_no_random_noise_when_carrier_missing(self):
        m=GlottalExcitationNet();m.eval()
        f0=torch.zeros(1,8);e=torch.ones(1,8)*.5
        a=m(f0,e);b=m(f0,e)
        self.assertTrue(torch.equal(a,b))
        self.assertLess(float(a.abs().max()),1e-7)

    def test_real_carrier_is_deterministic_and_highpass(self):
        x=torch.sin(torch.linspace(0,100,4800))[None]
        a=real_aperiodic_carrier(x);b=real_aperiodic_carrier(x)
        self.assertTrue(torch.equal(a,b))
        self.assertEqual(a.shape,x.shape)

    def test_engine_conversion_is_repeatable(self):
        torch.manual_seed(2);m=ArgonSourceFilter();m.eval()
        x=torch.randn(1,4800)*.02
        a=m.convert(x);b=m.convert(x)
        self.assertTrue(torch.equal(a,b))

if __name__=='__main__':unittest.main()
PY

cat > tests/test_neural_rvq_stability.py <<'PY'
import unittest,torch
from argon_core.bottleneck import ResidualVectorQuantizer

class RVQStabilityTests(unittest.TestCase):
    def test_initial_loss_is_bounded_on_unit_scale_features(self):
        torch.manual_seed(9)
        q=ResidualVectorQuantizer()
        x=torch.randn(2,192,24)
        y,idx,loss=q(x)
        self.assertTrue(torch.isfinite(loss))
        self.assertLess(float(loss),2.0)
        self.assertTrue(torch.isfinite(y).all())

if __name__=='__main__':unittest.main()
PY

/srv/era-audio/venv/bin/python -m py_compile argon_core/neural_features.py argon_core/source.py argon_core/bottleneck.py argon_core/neural_engine.py argon_core/neural_pretrain.py argon_core/neural_train.py
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest  tests.test_neural_source tests.test_neural_bottleneck tests.test_neural_filter tests.test_neural_losses  tests.test_neural_engine tests.test_neural_split tests.test_neural_real_aperiodic tests.test_neural_rvq_stability -v
