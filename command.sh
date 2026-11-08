#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="/srv/ARGON-VC/backups/argon-vocos-$STAMP"
PUB="/srv/era-audio/argon-neural-v2-vocos-test"
mkdir -p "$BACKUP" "$PUB"
cp -a argon_neural_v2 "$BACKUP/"

echo "=== INSTALL ==="
/srv/era-audio/venv/bin/python -m pip install -q "vocos>=0.1.0" huggingface_hub

cat > argon_neural_v2/vocos_engine.py <<'PY'
from __future__ import annotations
import torch
import torch.nn as nn
import torch.nn.functional as F
import torchaudio
from vocos import Vocos

SR=24000
HOP=256

def align(x,t):
    if x.ndim==2: x=x[:,None,:]
    return F.interpolate(x,size=t,mode="linear",align_corners=False)

def pitch_energy(w):
    if w.ndim==1: w=w[None]
    frame=1024
    frames=w.unfold(-1,frame,HOP)
    en=frames.square().mean(-1).sqrt()
    # Lightweight autocorrelation F0. It is only a control signal, never an audio path.
    x=frames-frames.mean(-1,keepdim=True)
    n=torch.fft.rfft(x,n=2048)
    ac=torch.fft.irfft(n.conj()*n,n=2048)[...,:frame]
    lo=max(1,SR//450); hi=min(frame-1,SR//55)
    seg=ac[...,lo:hi+1]
    lag=seg.argmax(-1)+lo
    f0=SR/lag.float()
    conf=seg.max(-1).values/(ac[...,0].abs()+1e-6)
    voiced=(conf>0.18).float()*(en>0.005).float()
    f0=f0*voiced
    return f0,en,voiced

class Block(nn.Module):
    def __init__(self,d=256,dilation=1):
        super().__init__()
        self.dw=nn.Conv1d(d,d,7,padding=3*dilation,dilation=dilation,groups=d)
        self.norm=nn.GroupNorm(1,d)
        self.p1=nn.Conv1d(d,d*3,1)
        self.p2=nn.Conv1d(d*3,d,1)
        self.g=nn.Parameter(torch.ones(1,d,1)*0.15)
    def forward(self,x,c):
        h=self.norm(self.dw(x))+c
        return x+self.g*self.p2(F.gelu(self.p1(h)))

class MelNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.w=nn.Conv1d(768,256,1)
        self.k=nn.Conv1d(100,256,1)
        self.c=nn.Sequential(nn.Conv1d(3,256,3,padding=1),nn.GELU(),nn.Conv1d(256,256,1))
        self.blocks=nn.ModuleList([Block(256,d) for d in (1,2,4,8,1,2,4,8)])
        self.out=nn.Conv1d(256,100,3,padding=1)
        nn.init.zeros_(self.out.weight); nn.init.zeros_(self.out.bias)
    def forward(self,w,k,f0,en,v):
        lf=torch.where(v>.5,torch.log(f0.clamp_min(50))/6,torch.zeros_like(f0))
        c=self.c(torch.stack((lf,en,v),1))
        h=self.w(w)+self.k(k)+c
        for b in self.blocks: h=b(h,c)
        return k+self.out(h)

class ArgonStudioVC:
    def __init__(self,device="cpu"):
        self.device=torch.device(device)
        self.vocos=Vocos.from_pretrained("charactr/vocos-mel-24khz").to(self.device).eval()
        for p in self.vocos.parameters(): p.requires_grad_(False)
        bundle=torchaudio.pipelines.WAVLM_BASE
        self.wavlm=bundle.get_model().to(self.device).eval()
        for p in self.wavlm.parameters(): p.requires_grad_(False)
        self.net=MelNet().to(self.device)
        self.bank_keys=None; self.bank_mels=None; self.target_f0_median=100.0

    @torch.inference_mode()
    def features(self,w):
        if w.ndim==1: w=w[None]
        w=w.to(self.device)
        mel=self.vocos.feature_extractor(w); t=mel.shape[-1]
        w16=torchaudio.functional.resample(w,24000,16000)
        fs,_=self.wavlm.extract_features(w16,num_layers=6)
        z=F.instance_norm(fs[-1].transpose(1,2))
        z=align(z,t)
        f0,en,v=pitch_energy(w)
        return dict(mel=mel,wavlm=z,f0=align(f0,t)[:,0],energy=align(en,t)[:,0],voiced=align(v,t)[:,0])

    @torch.inference_mode()
    def knn(self,z,k=4,temp=.05):
        q=F.normalize(z.transpose(1,2).reshape(-1,768),dim=-1)
        s=q@self.bank_keys.T
        val,idx=s.topk(min(k,self.bank_keys.shape[0]),dim=-1)
        ww=F.softmax(val/temp,dim=-1).unsqueeze(-1)
        m=(self.bank_mels[idx]*ww).sum(1)
        return m.reshape(z.shape[0],z.shape[-1],100).transpose(1,2)

    def fit(self,clips,epochs=35,lr=1e-3):
        W=[];M=[];F0=[];EN=[];V=[]
        for clip in clips:
            d=self.features(clip)
            W.append(d["wavlm"][0]);M.append(d["mel"][0]);F0.append(d["f0"][0]);EN.append(d["energy"][0]);V.append(d["voiced"][0])
        W=torch.cat(W,-1);M=torch.cat(M,-1);F0=torch.cat(F0);EN=torch.cat(EN);V=torch.cat(V)
        vf=F0[V>.5]
        if vf.numel()>10:self.target_f0_median=float(vf.median())
        keys=F.normalize(W.T,dim=-1); mels=M.T
        if keys.shape[0]>6000:
            ix=torch.randperm(keys.shape[0],device=self.device)[:6000]
            self.bank_keys=keys[ix].contiguous();self.bank_mels=mels[ix].contiguous()
        else:self.bank_keys=keys.contiguous();self.bank_mels=mels.contiguous()
        with torch.no_grad():
            s=keys@self.bank_keys.T
            val,idx=s.topk(min(5,self.bank_keys.shape[0]),dim=-1)
            if self.bank_keys.shape[0]==keys.shape[0] and idx.shape[1]>1:
                val,idx=val[:,1:],idx[:,1:]
            ww=F.softmax(val/.05,dim=-1).unsqueeze(-1)
            K=(self.bank_mels[idx]*ww).sum(1).T
        chunk=128;n=W.shape[-1]//chunk;size=n*chunk
        assert n>0
        bw=W[:,:size].reshape(768,n,chunk).permute(1,0,2)
        bm=M[:,:size].reshape(100,n,chunk).permute(1,0,2)
        bk=K[:,:size].reshape(100,n,chunk).permute(1,0,2)
        bf=F0[:size].reshape(n,chunk);be=EN[:size].reshape(n,chunk);bv=V[:size].reshape(n,chunk)
        opt=torch.optim.AdamW(self.net.parameters(),lr=lr,weight_decay=1e-4)
        sch=torch.optim.lr_scheduler.OneCycleLR(opt,max_lr=lr,total_steps=epochs)
        losses=[]
        self.net.train()
        for _ in range(epochs):
            opt.zero_grad(set_to_none=True)
            p=self.net(bw,bk,bf,be,bv)
            l=F.l1_loss(p,bm)+.5*F.l1_loss(p[:,:,1:]-p[:,:,:-1],bm[:,:,1:]-bm[:,:,:-1])
            l.backward();torch.nn.utils.clip_grad_norm_(self.net.parameters(),2);opt.step();sch.step();losses.append(float(l))
        self.net.eval()
        return {"start_loss":losses[0],"end_loss":losses[-1],"frames":int(W.shape[-1]),"f0_med":self.target_f0_median}

    @torch.inference_mode()
    def convert(self,w,blend=.65):
        d=self.features(w);f0=d["f0"].clone();v=d["voiced"]>.5
        if v.any():
            src=f0[v].median().clamp_min(50)
            r=(torch.as_tensor(self.target_f0_median,device=f0.device)/src).clamp(.5,2)
            f0[v]=(f0[v]*r).clamp(55,450)
        k=self.knn(d["wavlm"])
        r=self.net(d["wavlm"],k,f0,d["energy"],d["voiced"])
        mel=blend*r+(1-blend)*k
        return self.vocos.decode(mel).squeeze(0)
PY

cat > /tmp/run_argon_vocos.py <<'PY'
from pathlib import Path
import json,torch
from argon_core.audio import read_audio,write_audio
from argon_neural_v2.vocos_engine import ArgonStudioVC
root=Path("/srv/ARGON-VC");pub=Path("/srv/era-audio/argon-neural-v2-vocos-test")
target=read_audio(root/"data/ARGON uploads/Экспериментальный голос.mp3",24000)
source=read_audio(root/"data/victor_source.wav",24000)[:72000]
clips=[]
for sec in (12,55,104,173,225):
    s=int(sec*24000)
    if s+96000<=target.numel():clips.append(target[s:s+96000])
m=ArgonStudioVC("cpu")
stats=m.fit(clips,epochs=35,lr=1e-3)
out=m.convert(source,.65)
sil=torch.zeros(int(.55*24000))
write_audio(pub/"Исходник Виктор.wav",source,24000)
write_audio(pub/"ARGON Vocos эксперимент.wav",out,24000)
write_audio(pub/"A-B Виктор и ARGON Vocos.wav",torch.cat([source,sil,out]),24000)
torch.save({"net":m.net.state_dict(),"bank_keys":m.bank_keys.cpu(),"bank_mels":m.bank_mels.cpu(),"target_f0_median":m.target_f0_median,"stats":stats},pub/"ARGON Vocos эксперимент.pt")
print(json.dumps(stats,ensure_ascii=False))
PY

echo "=== CHECK ==="
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m py_compile argon_neural_v2/vocos_engine.py /tmp/run_argon_vocos.py
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
import torch
from argon_neural_v2.vocos_engine import MelNet
m=MelNet();B,T=2,24
o=m(torch.randn(B,768,T),torch.randn(B,100,T),torch.full((B,T),120.),torch.rand(B,T),torch.ones(B,T))
assert o.shape==(B,100,T) and torch.isfinite(o).all()
print("shape test ok",tuple(o.shape))
PY

echo "=== REAL A/B ==="
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python /tmp/run_argon_vocos.py

echo "=== LINKS ==="
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
from urllib.parse import quote
import subprocess
root=Path("/srv/era-audio/argon-neural-v2-vocos-test")
base="https://169-58-224-216.sslip.io/era-audio/argon-neural-v2-vocos-test/"
for p in sorted(root.glob("*.wav")):
    u=base+quote(p.name)
    r=subprocess.run(["curl","-ksS","-o","/dev/null","-w","%{http_code} %{size_download}",u],capture_output=True,text=True)
    print(r.stdout,p.name);print("URL",u)
PY

echo "=== OLD ARGON UNTOUCHED ==="
systemctl is-active argon-neural-v2.service || true
