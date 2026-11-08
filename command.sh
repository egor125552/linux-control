#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
PUB='/srv/era-audio/argon-neural-v2-ab'
mkdir -p "$PUB"

echo '=== TRAINING MUST REMAIN ACTIVE ==='
systemctl is-active argon-neural-v2.service || true
systemctl is-active argon-neural-long.service || true

cp -f 'results/ARGON Neural 2 Long.pt' /tmp/argon-v2-new-best.pt
cp -f 'results/ARGON Neural 2 backup before-review-fix/ARGON Neural 2 Long.pt' /tmp/argon-v2-old-best.pt

cat > /tmp/render_argon_v2_ab.py <<'PY'
from pathlib import Path
import math,json,torch
import torch.nn as nn
import torch.nn.functional as F
from argon_core.audio import read_audio,write_audio
from argon_neural_v2.content import DeepContentEncoder
from argon_neural_v2.features import pitch_energy,align_frames,real_aperiodic_carrier
from argon_neural_v2.engine import ArgonNeuralV2

class OldHarmonicExcitation(nn.Module):
    def __init__(self,sample_rate=24000,hop=240,harmonics=32,channels=96):
        super().__init__()
        self.sample_rate=int(sample_rate);self.hop=int(hop);self.harmonics=int(harmonics)
        self.control=nn.Sequential(
            nn.Conv1d(3,channels,5,padding=2),nn.GELU(),
            nn.Conv1d(channels,channels,5,padding=2),nn.GELU(),
            nn.Conv1d(channels,self.harmonics+2,3,padding=1),
        )
        nn.init.zeros_(self.control[-1].weight);nn.init.zeros_(self.control[-1].bias)
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
        harmonic=(torch.sin(phase_h)*amp_s*mask).sum(1)*conf
        if aperiodic is None:
            carrier=torch.zeros_like(harmonic)
        else:
            carrier=aperiodic.to(harmonic.device,harmonic.dtype)
            if carrier.ndim==1:carrier=carrier[None]
            if carrier.shape[-1]!=n:
                carrier=F.interpolate(carrier[:,None],size=n,mode='linear',align_corners=False)[:,0]
        ng=self._up(noise_gate,n)[:,0];bg=self._up(breath_gate,n)[:,0]
        aper_gate=ng*(1-conf)+.10*bg*conf
        y=(harmonic+aper_gate*carrier)*e*torch.exp(.15*torch.tanh(self.global_gain))
        return y,{}

class OldConditionedBlock(nn.Module):
    def __init__(self,dim=256,speaker_dim=192,dilation=1):
        super().__init__()
        self.dw=nn.Conv1d(dim,dim,7,padding=3*dilation,dilation=dilation,groups=dim)
        self.norm=nn.GroupNorm(1,dim);self.film=nn.Linear(speaker_dim,dim*2)
        self.p1=nn.Conv1d(dim,dim*4,1);self.p2=nn.Conv1d(dim*4,dim,1)
        self.gamma=nn.Parameter(torch.ones(1,dim,1)*1e-3)
    def forward(self,x,spk):
        h=self.norm(self.dw(x));scale,bias=self.film(spk).chunk(2,-1)
        h=h*(1+.15*torch.tanh(scale)[:,:,None])+.15*bias[:,:,None]
        h=self.p2(F.gelu(self.p1(h)))
        return x+self.gamma*h

def old_dynamic_fir(x,ir):
    n=x.shape[-1];taps=ir.shape[1]
    ir_s=F.interpolate(ir,size=n,mode='linear',align_corners=False)
    pad=taps//2
    win=F.pad(x,(pad,pad)).unfold(-1,taps,1)
    return (win*ir_s.transpose(1,2)).sum(-1)

class OldDeepVocalTract(nn.Module):
    def __init__(self,dim=256,speaker_dim=192,hop=240,long_taps=129,short_taps=31):
        super().__init__()
        self.dim=int(dim);self.speaker_dim=int(speaker_dim);self.hop=int(hop)
        self.long_taps=int(long_taps);self.short_taps=int(short_taps)
        self.speaker_in=nn.Linear(speaker_dim,dim)
        self.blocks=nn.ModuleList([OldConditionedBlock(dim,speaker_dim,d) for d in (1,2,4,8,1,2,4,8,1,2)])
        self.long_head=nn.Conv1d(dim,long_taps,1);self.short_head=nn.Conv1d(dim,short_taps,1)
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
        y=old_dynamic_fir(excitation,long_ir);y=old_dynamic_fir(y,short_ir)
        gain_s=F.interpolate(gain,size=y.shape[-1],mode='linear',align_corners=False)[:,0]
        return y*gain_s,{}

class OldWaveBlock(nn.Module):
    def __init__(self,channels=64,dilation=1):
        super().__init__()
        self.dw=nn.Conv1d(channels,channels,5,padding=2*dilation,dilation=dilation,groups=channels)
        self.norm=nn.GroupNorm(8,channels)
        self.p1=nn.Conv1d(channels,channels*2,1);self.p2=nn.Conv1d(channels*2,channels,1)
        self.gamma=nn.Parameter(torch.ones(1,channels,1)*1e-3)
    def forward(self,x):
        h=self.dw(x);h=self.norm(h);h=self.p2(F.gelu(self.p1(h)))
        return x+self.gamma*h

class OldWaveformRefiner(nn.Module):
    def __init__(self,content_dim=256,speaker_dim=192,channels=64,hop=240):
        super().__init__();self.hop=int(hop)
        self.audio_in=nn.Conv1d(3,channels,7,padding=3)
        self.content=nn.Conv1d(content_dim,channels,1);self.speaker=nn.Linear(speaker_dim,channels)
        self.blocks=nn.ModuleList([OldWaveBlock(channels,d) for d in (1,3,9,27,1,3,9,27)])
        self.out=nn.Conv1d(channels,1,7,padding=3)
        nn.init.zeros_(self.out.weight);nn.init.zeros_(self.out.bias)
        self.residual_scale=nn.Parameter(torch.tensor(-1.4))
    def forward(self,coarse,excitation,carrier,codes,speaker_embedding):
        n=coarse.shape[-1]
        def fit(x):
            if x.shape[-1]==n:return x
            return F.interpolate(x[:,None],size=n,mode='linear',align_corners=False)[:,0]
        excitation=fit(excitation);carrier=fit(carrier)
        h=self.audio_in(torch.stack((coarse,excitation,carrier),dim=1))
        h=h+F.interpolate(self.content(codes),size=n,mode='linear',align_corners=False)+self.speaker(speaker_embedding)[:,:,None]
        for block in self.blocks:h=block(h)
        residual=torch.tanh(self.out(h)[:,0])
        return coarse+torch.sigmoid(self.residual_scale)*residual

class OldArgonNeuralV2(nn.Module):
    def __init__(self,sample_rate=24000,hop=240,content_dim=256,speaker_dim=192,
                 harmonics=32,books=6,book_size=1024,long_taps=129,short_taps=31):
        super().__init__()
        self.sample_rate=int(sample_rate);self.hop=int(hop)
        self.content_dim=int(content_dim);self.speaker_dim=int(speaker_dim)
        self.harmonics=int(harmonics);self.books=int(books);self.book_size=int(book_size)
        self.long_taps=int(long_taps);self.short_taps=int(short_taps)
        self.content=DeepContentEncoder(self.sample_rate,self.hop,self.content_dim,self.books,self.book_size)
        self.source=OldHarmonicExcitation(self.sample_rate,self.hop,self.harmonics)
        self.tract=OldDeepVocalTract(self.content_dim,self.speaker_dim,self.hop,self.long_taps,self.short_taps)
        self.refiner=OldWaveformRefiner(self.content_dim,self.speaker_dim,64,self.hop)
        self.voice=nn.Parameter(torch.randn(1,self.speaker_dim)*.04)
    def forward(self,wav,speaker_embedding=None):
        if wav.ndim==1:wav=wav[None]
        codes,indices,vq_loss,vq_stats=self.content(wav)
        f0,energy,confidence=pitch_energy(wav,self.sample_rate,self.hop)
        f0=align_frames(f0,codes.shape[-1]);energy=align_frames(energy,codes.shape[-1]);confidence=align_frames(confidence,codes.shape[-1])
        carrier=real_aperiodic_carrier(wav)
        excitation,_=self.source(f0,energy,carrier,confidence)
        if speaker_embedding is None:speaker_embedding=self.voice.expand(wav.shape[0],-1)
        elif speaker_embedding.ndim==1:speaker_embedding=speaker_embedding[None].expand(wav.shape[0],-1)
        coarse,_=self.tract(excitation,codes,speaker_embedding)
        y=self.refiner(coarse,excitation,carrier,codes,speaker_embedding)
        n=wav.shape[-1]
        if y.shape[-1]<n:y=F.pad(y,(0,n-y.shape[-1]))
        return y[...,:n]

def load_old(path):
    obj=torch.load(path,map_location='cpu',weights_only=True)
    m=OldArgonNeuralV2(**obj['config'])
    m.load_state_dict(obj['state'],strict=True);m.eval()
    return m,obj.get('metadata',{})

def speaker_emb(meta,name):
    vals=(meta.get('speaker_table') or {}).get(name)
    if not vals: raise RuntimeError(f'missing speaker {name}')
    return torch.tensor(vals,dtype=torch.float32)[None]

def choose_experimental_segment(path,sr=24000,seconds=3.0):
    x=read_audio(path,sr)
    n=int(seconds*sr);step=sr
    best=(0.0,0)
    limit=min(len(x)-n,int(300*sr))
    for s in range(0,max(1,limit),step):
        w=x[s:s+n]
        if len(w)<n:break
        rms=float(w.square().mean().sqrt())
        if rms>best[0]:best=(rms,s)
    return x[best[1]:best[1]+n],best

torch.set_num_threads(1)
root=Path('/srv/ARGON-VC');pub=Path('/srv/era-audio/argon-neural-v2-ab')
new,newmeta=ArgonNeuralV2.load('/tmp/argon-v2-new-best.pt','cpu')
old,oldmeta=load_old('/tmp/argon-v2-old-best.pt')

victor=root/'data/victor_source.wav'
vx=read_audio(victor,24000)[:int(3.0*24000)]
if len(vx)<24000:
    raise RuntimeError('victor source too short')

new_alex=speaker_emb(newmeta,'alexander');old_alex=speaker_emb(oldmeta,'alexander')
with torch.inference_mode():
    y_new,_=new(vx[None],speaker_embedding=new_alex,shift_pitch=True)
    y_old=old(vx[None],speaker_embedding=old_alex)
y_new=y_new[0];y_old=y_old[0]

exp,seg=choose_experimental_segment(root/'data/ARGON uploads/Экспериментальный голос.mp3')
new_exp=speaker_emb(newmeta,'experimental');old_exp=speaker_emb(oldmeta,'experimental')
with torch.inference_mode():
    e_new,_=new(exp[None],speaker_embedding=new_exp,shift_pitch=True)
    e_old=old(exp[None],speaker_embedding=old_exp)
e_new=e_new[0];e_old=e_old[0]

sil=torch.zeros(int(.55*24000))
files={
 'victor_src':'Виктор исходник.wav',
 'victor_old':f'Виктор в Александр старый пластик эпоха {oldmeta.get("epoch")}.wav',
 'victor_new':f'Виктор в Александр новая v2 эпоха {newmeta.get("epoch")}.wav',
 'victor_ab':f'A B Виктор в Александр старый {oldmeta.get("epoch")} новая {newmeta.get("epoch")}.wav',
 'exp_src':'Экспериментальный исходный фрагмент.wav',
 'exp_old':f'Экспериментальный старый пластик эпоха {oldmeta.get("epoch")}.wav',
 'exp_new':f'Экспериментальный новая v2 эпоха {newmeta.get("epoch")}.wav',
 'exp_ab':f'A B Экспериментальный старый {oldmeta.get("epoch")} новая {newmeta.get("epoch")}.wav'
}
write_audio(pub/files['victor_src'],vx,24000)
write_audio(pub/files['victor_old'],y_old,24000)
write_audio(pub/files['victor_new'],y_new,24000)
write_audio(pub/files['victor_ab'],torch.cat([vx,sil,y_old,sil,y_new]),24000)
write_audio(pub/files['exp_src'],exp,24000)
write_audio(pub/files['exp_old'],e_old,24000)
write_audio(pub/files['exp_new'],e_new,24000)
write_audio(pub/files['exp_ab'],torch.cat([exp,sil,e_old,sil,e_new]),24000)
print(json.dumps({
 'new_epoch':newmeta.get('epoch'),'new_best_val':newmeta.get('best_val'),
 'old_epoch':oldmeta.get('epoch'),'old_best_val':oldmeta.get('best_val'),
 'experimental_segment_start_seconds':seg[1]/24000,
 'files':files
},ensure_ascii=False))
PY

PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python /tmp/render_argon_v2_ab.py

echo '=== FILES ==='
find "$PUB" -maxdepth 1 -type f -printf '%f %s\n' | sort

echo '=== TRAINING AFTER RENDER ==='
systemctl is-active argon-neural-v2.service || true
tail -5 'results/ARGON Neural 2 long.log' || true
