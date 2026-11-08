#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

cat > argon_neural_v2/features.py <<'PY'
from __future__ import annotations
import torch
import torch.nn.functional as F

def align_frames(x: torch.Tensor, frames: int) -> torch.Tensor:
    if x.shape[-1] == frames:
        return x
    if x.ndim == 2:
        return F.interpolate(x[:, None, :], size=frames, mode='linear', align_corners=False)[:, 0, :]
    if x.ndim == 3:
        return F.interpolate(x, size=frames, mode='linear', align_corners=False)
    raise ValueError('expected 2D or 3D tensor')

def pitch_energy(wav: torch.Tensor, sample_rate: int = 24000, hop: int = 240,
                 fmin: float = 65.0, fmax: float = 400.0) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    if wav.ndim == 1:
        wav = wav[None, :]
    win = hop * 4
    pad = win // 2
    padded = F.pad(wav, (pad, pad), mode='reflect')
    framed = padded.unfold(-1, win, hop)
    window = torch.hann_window(win, device=wav.device, dtype=wav.dtype)
    framed = (framed - framed.mean(dim=-1, keepdim=True)) * window
    rms = framed.square().mean(dim=-1).clamp_min(1e-8).sqrt()
    energy = (rms / rms.amax(dim=-1, keepdim=True).clamp_min(1e-4)).clamp(0.0, 1.0)

    min_lag = max(2, int(sample_rate / fmax))
    max_lag = min(win - 2, int(sample_rate / fmin))
    spec = torch.fft.rfft(framed, dim=-1)
    ac = torch.fft.irfft(spec * spec.conj(), n=win, dim=-1)[..., :max_lag + 2]
    ac0 = ac[..., :1].clamp_min(1e-6)
    norm = ac / ac0
    search = norm[..., min_lag:max_lag + 1]
    peak, idx = search.max(dim=-1)

    lag_int = idx + min_lag
    lag_prev = (lag_int - 1).clamp(min_lag, max_lag)
    lag_next = (lag_int + 1).clamp(min_lag, max_lag)
    y_m1 = norm.gather(-1, lag_prev.unsqueeze(-1)).squeeze(-1)
    y_0 = peak
    y_p1 = norm.gather(-1, lag_next.unsqueeze(-1)).squeeze(-1)
    denom = (y_m1 - 2.0 * y_0 + y_p1)
    delta = torch.where(
        denom.abs() > 1e-5,
        0.5 * (y_m1 - y_p1) / denom,
        torch.zeros_like(denom)
    ).clamp(-0.5, 0.5)
    lag = lag_int.float() + delta

    voiced = (peak > 0.32) & (rms > 0.012)
    raw_f0 = float(sample_rate) / lag.clamp_min(1.0)

    f0_clean = raw_f0.clone()
    if raw_f0.shape[-1] >= 3:
        p = F.pad(raw_f0[:, None, :], (1, 1), mode='replicate')[:, 0, :]
        s0, s1, s2 = p[:, :-2], p[:, 1:-1], p[:, 2:]
        f0_clean = torch.stack((s0, s1, s2), dim=-1).median(dim=-1).values

    f0 = torch.where(voiced, f0_clean, torch.zeros_like(f0_clean))
    confidence = torch.where(voiced, peak.clamp(0.0, 1.0), torch.zeros_like(peak))
    return f0, energy, confidence

def log_mel_spectrogram(wav: torch.Tensor, sample_rate: int = 24000, n_fft: int = 1024,
                        hop: int = 240, win: int = 960, n_mels: int = 80) -> torch.Tensor:
    if wav.ndim == 1:
        wav = wav[None, :]
    window = torch.hann_window(win, device=wav.device, dtype=wav.dtype)
    spec = torch.stft(wav, n_fft=n_fft, hop_length=hop, win_length=win, window=window, center=True, return_complex=True)
    mag = spec.abs().clamp_min(1e-5)
    freqs = torch.linspace(0.0, sample_rate / 2.0, mag.shape[1], device=wav.device, dtype=wav.dtype)
    m_min = 2595.0 * torch.log10(torch.tensor(1.0 + 40.0 / 700.0, device=wav.device, dtype=wav.dtype))
    m_max = 2595.0 * torch.log10(torch.tensor(1.0 + (sample_rate / 2.0) / 700.0, device=wav.device, dtype=wav.dtype))
    m_pts = torch.linspace(m_min, m_max, n_mels + 2, device=wav.device, dtype=wav.dtype)
    hz_pts = 700.0 * (10.0 ** (m_pts / 2595.0) - 1.0)
    fb = torch.zeros(n_mels, mag.shape[1], device=wav.device, dtype=wav.dtype)
    for m in range(n_mels):
        l, c, r = hz_pts[m], hz_pts[m + 1], hz_pts[m + 2]
        left = (freqs - l) / (c - l + 1e-6)
        right = (r - freqs) / (r - c + 1e-6)
        fb[m] = torch.minimum(left, right).clamp_min(0.0)
    fb = fb / fb.sum(dim=-1, keepdim=True).clamp_min(1e-6)
    mel = torch.einsum('mf,bft->bmt', fb, mag)
    return torch.log(mel.clamp_min(1e-5))

def real_aperiodic_carrier(wav: torch.Tensor, smooth: int = 15) -> torch.Tensor:
    if wav.ndim == 1:
        wav = wav[None, :]
    pad = smooth // 2
    low = F.avg_pool1d(F.pad(wav[:, None, :], (pad, pad), mode='reflect'), kernel_size=smooth, stride=1)[:, 0, :]
    high = wav - low
    scale = high.square().mean(dim=-1, keepdim=True).clamp_min(1e-6).sqrt()
    return (high / scale).clamp(-4.0, 4.0)
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
        self.gamma=nn.Parameter(torch.ones(1,dim,1)*0.1)
    def forward(self,x,spk):
        h=self.norm(self.dw(x))
        scale,bias=self.film(spk).chunk(2,-1)
        h=h*(1.0 + 0.8*torch.tanh(scale)[:,:,None]) + 0.8*bias[:,:,None]
        h=self.p2(F.gelu(self.p1(h)))
        return x+self.gamma*h

class DeepVocalTract(nn.Module):
    def __init__(self,dim=256,speaker_dim=192,hop=240,long_taps=129,short_taps=31):
        super().__init__()
        self.dim=int(dim);self.speaker_dim=int(speaker_dim);self.hop=int(hop)
        self.long_taps=int(long_taps);self.short_taps=int(short_taps)
        self.n_fft=1024;self.win_length=960;self.bins=self.n_fft//2+1
        self.speaker_in=nn.Linear(speaker_dim,dim)
        self.blocks=nn.ModuleList([ConditionedBlock(dim,speaker_dim,d) for d in (1,2,4,8,1,2,4,8,1,2)])
        self.spec_filter=nn.Conv1d(dim,self.bins,1)
        self.long_head=nn.Conv1d(dim,long_taps,1)
        self.short_head=nn.Conv1d(dim,short_taps,1)
        self.gain_head=nn.Conv1d(dim,1,1)
        nn.init.normal_(self.spec_filter.weight, std=0.01);nn.init.zeros_(self.spec_filter.bias)
        for head in (self.long_head,self.short_head,self.gain_head):
            nn.init.zeros_(head.weight);nn.init.zeros_(head.bias)

    def _shift_spectrum(self, mag: torch.Tensor, phase: torch.Tensor, pitch_ratio: torch.Tensor | None) -> tuple[torch.Tensor, torch.Tensor]:
        if pitch_ratio is None:
            return mag, phase
        b, f, t = mag.shape
        device, dtype = mag.device, mag.dtype
        base_grid = torch.linspace(-1.0, 1.0, f, device=device, dtype=dtype)[None, :, None].expand(b, f, t)
        ratio = pitch_ratio.view(b, 1, 1).clamp(0.5, 2.0)
        src_freq_grid = ((base_grid + 1.0) / ratio) - 1.0
        time_grid = torch.linspace(-1.0, 1.0, t, device=device, dtype=dtype)[None, None, :].expand(b, f, t)
        grid = torch.stack((time_grid, src_freq_grid), dim=-1)
        shifted_mag = F.grid_sample(mag[:, None], grid, mode='bilinear', padding_mode='border', align_corners=True)[:, 0]

        dphi = torch.diff(phase, dim=-1, prepend=phase[..., :1])
        dphi_wrapped = torch.atan2(torch.sin(dphi), torch.cos(dphi))
        shifted_phase = torch.cumsum(dphi_wrapped * ratio, dim=-1)
        return shifted_mag, shifted_phase

    def forward(self,excitation,codes,speaker_embedding,source_wav=None,pitch_ratio=None):
        h=codes+self.speaker_in(speaker_embedding)[:,:,None]
        for block in self.blocks:h=block(h,speaker_embedding)

        log_filter = 2.5 * torch.tanh(self.spec_filter(h))
        gain=torch.exp(.60*torch.tanh(self.gain_head(h)))

        win=torch.hann_window(self.win_length,device=excitation.device,dtype=excitation.dtype)
        Z_exc=torch.stft(excitation,n_fft=self.n_fft,hop_length=self.hop,win_length=self.win_length,window=win,center=True,return_complex=True)
        frames=min(Z_exc.shape[-1],log_filter.shape[-1])

        if source_wav is not None:
            Z_src=torch.stft(source_wav,n_fft=self.n_fft,hop_length=self.hop,win_length=self.win_length,window=win,center=True,return_complex=True)[...,:frames]
            mag_src=Z_src.abs().clamp_min(1e-6)
            phase_src=torch.angle(Z_src)

            b,f,t=mag_src.shape
            env_src=F.avg_pool1d(
                F.pad(mag_src.transpose(1,2).reshape(b*t,1,f),(12,12),mode='reflect'),
                25,stride=1
            ).reshape(b,t,f).transpose(1,2).clamp_min(1e-5)
            fine_harmonic_structure = mag_src / env_src

            shifted_fine, live_phase = self._shift_spectrum(fine_harmonic_structure, phase_src, pitch_ratio)

            exc_mag = Z_exc[...,:frames].abs().clamp_min(1e-6)
            new_mag = (shifted_fine * env_src * torch.exp(log_filter[...,:frames])) + 0.03 * exc_mag
            Z_out = torch.polar(new_mag, live_phase)
        else:
            Z_out = Z_exc[...,:frames] * torch.exp(log_filter[...,:frames])

        y=torch.istft(Z_out,n_fft=self.n_fft,hop_length=self.hop,win_length=self.win_length,window=win,length=excitation.shape[-1])
        gain_s=F.interpolate(gain,size=y.shape[-1],mode='linear',align_corners=False)[:,0]
        y=y*gain_s
        long_ir=self.long_head(h);short_ir=self.short_head(h)
        return y,{'long_ir':long_ir,'short_ir':short_ir,'gain':gain,'log_filter':log_filter}
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
        self.f0_proj=nn.Linear(self.speaker_dim, 1)
        nn.init.zeros_(self.f0_proj.weight);nn.init.constant_(self.f0_proj.bias, 4.55)

    def forward(self,wav,speaker_embedding=None,shift_pitch=False):
        if wav.ndim==1:wav=wav[None]
        codes,indices,vq_loss,vq_stats=self.content(wav)
        f0,energy,confidence=pitch_energy(wav,self.sample_rate,self.hop)
        f0=align_frames(f0,codes.shape[-1]);energy=align_frames(energy,codes.shape[-1])
        confidence=align_frames(confidence,codes.shape[-1])

        if speaker_embedding is None:
            speaker_embedding=self.voice.expand(wav.shape[0],-1)
        elif speaker_embedding.ndim==1:
            speaker_embedding=speaker_embedding[None].expand(wav.shape[0],-1)

        voiced = f0 > 20.0
        pred_log_f0 = self.f0_proj(speaker_embedding).clamp(4.0, 5.8)
        if self.training and voiced.any():
            real_meds = []
            for b in range(f0.shape[0]):
                v = voiced[b]
                med = f0[b, v].median().clamp_min(50.0) if v.any() else torch.tensor(100.0, device=f0.device, dtype=f0.dtype)
                real_meds.append(torch.log(med))
            target_log_f0 = torch.stack(real_meds)[:, None]
            vq_loss = vq_loss + 0.25 * F.mse_loss(pred_log_f0, target_log_f0.detach())

        pitch_ratio = None
        if shift_pitch:
            target_f0_med = torch.exp(pred_log_f0)
            f0_shifted = f0.clone()
            ratios = []
            for b in range(f0.shape[0]):
                v = voiced[b]
                if v.any():
                    src_med = f0[b, v].median().clamp_min(50.0)
                    r = (target_f0_med[b, 0] / src_med).clamp(0.55, 1.85)
                    f0_shifted[b, v] = (f0[b, v] * r).clamp(55.0, 450.0)
                    ratios.append(r)
                else:
                    ratios.append(torch.tensor(1.0, device=f0.device, dtype=f0.dtype))
            f0 = f0_shifted
            pitch_ratio = torch.stack(ratios)

        carrier=real_aperiodic_carrier(wav)
        excitation,source_aux=self.source(f0,energy,carrier,confidence)
        coarse,tract_aux=self.tract(excitation,codes,speaker_embedding,source_wav=wav,pitch_ratio=pitch_ratio)
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
        was=self.training;self.eval();y,_=self(wav, shift_pitch=True)
        if was:self.train()
        return y

    def save(self,path,metadata=None):
        obj={'format':FORMAT,'config':{'sample_rate':self.sample_rate,'hop':self.hop,
             'content_dim':self.content_dim,'speaker_dim':self.speaker_dim,
             'harmonics':self.harmonics,'books':self.books,'book_size':1024 if not hasattr(self,'book_size') else self.book_size,
             'long_taps':self.long_taps,'short_taps':self.short_taps},
             'state':{k:v.detach().cpu() for k,v in self.state_dict().items()},
             'metadata':dict(metadata or {})}
        p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);torch.save(obj,p);return p

    @classmethod
    def load(cls,path,device='cpu'):
        obj=torch.load(path,map_location='cpu',weights_only=True)
        if obj.get('format')!=FORMAT:raise ValueError('unsupported ARGON Neural 2 checkpoint')
        model=cls(**obj['config']).to(device);model.load_state_dict(obj['state'],strict=False);model.eval()
        return model,obj.get('metadata',{})
PY

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

    def test_same_checkpoint_forward_is_finite_with_live_phase(self):
        m,_=ArgonNeuralV2.load('/srv/ARGON-VC/results/ARGON Neural 2 Long.pt','cpu')
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

echo '=== COMPILE ==='
python3 -m py_compile argon_neural_v2/features.py argon_neural_v2/tract.py argon_neural_v2/engine.py

echo '=== TESTS ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest   tests.test_neural_v2_live_phase   tests.test_neural_v2_f0_learning   tests.test_neural_v2_review_fix   tests.test_neural_v2_safe_step -v

echo '=== RENDER NEW ON SAME EPOCH 30 ==='
PUB='/srv/era-audio/argon-neural-v2-phase-fix'
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
import json,torch
from argon_core.audio import read_audio,write_audio
from argon_neural_v2.engine import ArgonNeuralV2

root=Path('/srv/ARGON-VC')
pub=Path('/srv/era-audio/argon-neural-v2-phase-fix')
model,meta=ArgonNeuralV2.load(root/'results/ARGON Neural 2 Long.pt','cpu')
spk=meta.get('speaker_table') or {}
def emb(name):
    return torch.tensor(spk[name],dtype=torch.float32)[None]

victor=read_audio(root/'data/victor_source.wav',24000)[:72000]
with torch.inference_mode():
    new_v,_=model(victor[None],speaker_embedding=emb('alexander'),shift_pitch=True)
write_audio(pub/'После исправления живой фазы Виктор в Александр.wav',new_v[0],24000)

exp=read_audio(root/'data/ARGON uploads/Экспериментальный голос.mp3',24000)
start=int(173.07*24000);exp=exp[start:start+72000]
with torch.inference_mode():
    new_e,_=model(exp[None],speaker_embedding=emb('experimental'),shift_pitch=True)
write_audio(pub/'После исправления живой фазы Экспериментальный.wav',new_e[0],24000)

sil=torch.zeros(int(.55*24000))
old_v=read_audio(pub/'До исправления фазы Виктор в Александр.wav',24000)
old_e=read_audio(pub/'До исправления фазы Экспериментальный.wav',24000)
write_audio(pub/'A-B Виктор в Александр до и после живой фазы.wav',torch.cat([old_v,sil,new_v[0]]),24000)
write_audio(pub/'A-B Экспериментальный до и после живой фазы.wav',torch.cat([old_e,sil,new_e[0]]),24000)
print(json.dumps({'epoch':meta.get('epoch'),'best_val':meta.get('best_val')},ensure_ascii=False))
PY

echo '=== RESTART V2 FROM SAME CLEAN CHECKPOINT ==='
systemctl start argon-neural-v2.service
sleep 5
systemctl is-active argon-neural-v2.service || true
systemctl is-active argon-neural-long.service || true

echo '=== FILES ==='
find "$PUB" -maxdepth 1 -type f -printf '%f %s\n' | sort

echo '=== HTTP CHECK ==='
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
from urllib.parse import quote
import subprocess
root=Path('/srv/era-audio/argon-neural-v2-phase-fix')
base='https://169-58-224-216.sslip.io/era-audio/argon-neural-v2-phase-fix/'
for p in sorted(root.glob('*.wav')):
    url=base+quote(p.name)
    r=subprocess.run(['curl','-ksS','-o','/dev/null','-w','%{http_code} %{size_download}',url],capture_output=True,text=True)
    print(r.stdout,p.name)
    print('URL',url)
PY
