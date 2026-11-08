#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== KEEP V1 RUNNING ==='
systemctl is-active argon-neural-long.service || true

echo '=== STOP V2 FOR SAFE REPLACEMENT ==='
systemctl stop argon-neural-v2.service || true
mkdir -p 'results/ARGON Neural 2 backup before review fix'
cp -f 'results/ARGON Neural 2 Long.pt' 'results/ARGON Neural 2 backup before review fix/' 2>/dev/null || true
cp -f 'results/ARGON Neural 2 Long Latest.pt' 'results/ARGON Neural 2 backup before review fix/' 2>/dev/null || true
cp -f 'results/ARGON Neural 2 long.log' 'results/ARGON Neural 2 backup before review fix/' 2>/dev/null || true

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
        nn.init.normal_(self.control[-1].weight, std=0.02)
        nn.init.zeros_(self.control[-1].bias)
        self.global_gain=nn.Parameter(torch.tensor(0.0))
        # Фиксированная дисперсия начальных фаз гармоник (убирает эффект электронной пилы)
        k_idx = torch.arange(1, self.harmonics + 1).float()
        self.register_buffer('phase_offset', torch.sin(k_idx * 1.6180339) * math.pi)

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
        # Полнодиапазонное управление гармониками в дБ (вместо зажима 0.35), позволяющее гасить и выделять обертоны
        tilt = k.pow(-0.85)
        amps = tilt * F.softplus(logits + 0.5)
        amps = amps / (amps.sum(1, keepdim=True) + 1e-5)

        f=self._up(f0[:,None],n)[:,0].clamp(0,650)
        e=self._up(energy[:,None],n)[:,0].clamp_min(0)
        conf=self._up(confidence[:,None],n)[:,0].clamp(0,1)

        # Естественный микро-тремор связок (jitter) убирает мёртвую синтетичность
        inst_f = f * (1.0 + 0.004 * torch.sin(torch.cumsum(2 * math.pi * 5.5 / self.sample_rate * torch.ones_like(f), dim=-1)))
        phase=torch.cumsum(2*math.pi*inst_f/self.sample_rate,dim=-1)
        phase_h=phase[:,None,:]*k + self.phase_offset[None,:,None].to(f0.dtype)

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
        aper_gate=ng*(1-conf)+.14*bg*conf
        y=(harmonic+aper_gate*carrier)*e*torch.exp(.35*torch.tanh(self.global_gain))
        return y,{'harmonic_amplitudes':amps,'noise_gate':noise_gate,'breath_gate':breath_gate}
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
        # Нормальный стартовый шаг 0.1 вместо 1e-3, чтобы блоки реально работали
        self.gamma=nn.Parameter(torch.ones(1,dim,1)*0.1)
    def forward(self,x,spk):
        h=self.norm(self.dw(x))
        scale,bias=self.film(spk).chunk(2,-1)
        # Полноценная модуляция тембром диктора (без зажима 0.15)
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
        # Прямой спектрально-формантный фильтр на 513 частот STFT вместо глухого FIR
        self.spec_filter=nn.Conv1d(dim,self.bins,1)
        self.long_head=nn.Conv1d(dim,long_taps,1)
        self.short_head=nn.Conv1d(dim,short_taps,1)
        self.gain_head=nn.Conv1d(dim,1,1)
        nn.init.normal_(self.spec_filter.weight, std=0.01);nn.init.zeros_(self.spec_filter.bias)
        for head in (self.long_head,self.short_head,self.gain_head):
            nn.init.zeros_(head.weight);nn.init.zeros_(head.bias)

    def forward(self,excitation,codes,speaker_embedding,source_wav=None):
        h=codes+self.speaker_in(speaker_embedding)[:,:,None]
        for block in self.blocks:h=block(h,speaker_embedding)

        # Предсказываем логарифмический фильтр формант целевого диктора (диапазон +-18 дБ)
        log_filter = 2.2 * torch.tanh(self.spec_filter(h))
        gain=torch.exp(.60*torch.tanh(self.gain_head(h)))

        win=torch.hann_window(self.win_length,device=excitation.device,dtype=excitation.dtype)
        Z_exc=torch.stft(excitation,n_fft=self.n_fft,hop_length=self.hop,win_length=self.win_length,window=win,center=True,return_complex=True)
        frames=min(Z_exc.shape[-1],log_filter.shape[-1])

        # Если передан исходный сигнал, извлекаем его выбеленную микро-структуру (без формант исходного диктора)
        if source_wav is not None:
            Z_src=torch.stft(source_wav,n_fft=self.n_fft,hop_length=self.hop,win_length=self.win_length,window=win,center=True,return_complex=True)[...,:frames]
            mag_src=Z_src.abs().clamp_min(1e-6)
            # Сглаживаем по частоте (выделяем старые форманты) и делим на них, стирая исходного говорящего
            b,f,t=mag_src.shape
            env_src=F.avg_pool1d(F.pad(mag_src.transpose(1,2).reshape(b*t,1,f),(16,16),mode='reflect'),33,stride=1).reshape(b,t,f).transpose(1,2).clamp_min(1e-5)
            whitened_mag = mag_src / env_src
            # Комбинируем живую микро-структуру с новым гармоническим источником и накладываем форманты целевого голоса
            exc_mag = Z_exc[...,:frames].abs().clamp_min(1e-6)
            exc_env = F.avg_pool1d(F.pad(exc_mag.transpose(1,2).reshape(b*t,1,f),(16,16),mode='reflect'),33,stride=1).reshape(b,t,f).transpose(1,2).clamp_min(1e-5)
            new_mag = (0.55 * whitened_mag * exc_env + 0.45 * exc_mag) * torch.exp(log_filter[...,:frames])
            phase = torch.angle(Z_exc[...,:frames])
            Z_out = torch.polar(new_mag, phase)
        else:
            Z_out = Z_exc[...,:frames] * torch.exp(log_filter[...,:frames])

        y=torch.istft(Z_out,n_fft=self.n_fft,hop_length=self.hop,win_length=self.win_length,window=win,length=excitation.shape[-1])
        gain_s=F.interpolate(gain,size=y.shape[-1],mode='linear',align_corners=False)[:,0]
        y=y*gain_s
        long_ir=self.long_head(h);short_ir=self.short_head(h)
        return y,{'long_ir':long_ir,'short_ir':short_ir,'gain':gain,'log_filter':log_filter}
PY

cat > argon_neural_v2/postfilter.py <<'PY'
from __future__ import annotations
import torch
import torch.nn as nn
import torch.nn.functional as F

class Snake1d(nn.Module):
    """Периодическая активация Snake из BigVGAN/DAC — полностью убирает металлический звон на волне."""
    def __init__(self, channels):
        super().__init__()
        self.alpha = nn.Parameter(torch.ones(1, channels, 1))
    def forward(self, x):
        a = self.alpha.clamp_min(0.05)
        return x + (1.0 / a) * torch.sin(a * x).square()

class WaveBlock(nn.Module):
    def __init__(self,channels=64,dilation=1):
        super().__init__()
        self.dw=nn.Conv1d(channels,channels,7,padding=3*dilation,dilation=dilation,groups=channels)
        self.norm=nn.GroupNorm(8,channels)
        self.act1=Snake1d(channels)
        self.p1=nn.Conv1d(channels,channels*2,1)
        self.act2=Snake1d(channels*2)
        self.p2=nn.Conv1d(channels*2,channels,1)
        self.gamma=nn.Parameter(torch.ones(1,channels,1)*0.05)
    def forward(self,x):
        h=self.dw(x);h=self.norm(h);h=self.act1(h)
        h=self.p2(self.act2(self.p1(h)))
        return x+self.gamma*h

class WaveformRefiner(nn.Module):
    def __init__(self,content_dim=256,speaker_dim=192,channels=64,hop=240):
        super().__init__();self.hop=int(hop)
        self.audio_in=nn.Conv1d(3,channels,7,padding=3)
        self.content=nn.Conv1d(content_dim,channels,1)
        self.speaker=nn.Linear(speaker_dim,channels)
        # Плавная шкала дилатаций (1,2,4,8) вместо (1,3,9,27), создававшей гребенчатый звон
        self.blocks=nn.ModuleList([WaveBlock(channels,d) for d in (1,2,4,8,1,2,4,8)])
        self.out=nn.Conv1d(channels,1,7,padding=3)
        nn.init.zeros_(self.out.weight);nn.init.zeros_(self.out.bias)
        self.residual_scale=nn.Parameter(torch.tensor(-0.5))

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
        return coarse+0.35*torch.sigmoid(self.residual_scale)*residual
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
        # Предсказатель целевой базовой частоты голоса (log F0) из вектора диктора
        self.f0_proj=nn.Linear(self.speaker_dim, 1)
        nn.init.zeros_(self.f0_proj.weight);nn.init.constant_(self.f0_proj.bias, 4.55) # ~95 Hz base

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

        # При конверсии переносим среднюю высоту голоса в регистр целевого диктора, сохраняя интонацию
        if shift_pitch:
            voiced = f0 > 20.0
            target_f0_med = torch.exp(self.f0_proj(speaker_embedding).clamp(4.1, 5.6)) # 60..270 Hz
            f0_shifted = f0.clone()
            for b in range(f0.shape[0]):
                v = voiced[b]
                if v.any():
                    src_med = f0[b, v].median().clamp_min(50.0)
                    ratio = (target_f0_med[b, 0] / src_med).clamp(0.45, 2.2)
                    f0_shifted[b, v] = (f0[b, v] * ratio).clamp(55.0, 450.0)
            f0 = f0_shifted

        carrier=real_aperiodic_carrier(wav)
        excitation,source_aux=self.source(f0,energy,carrier,confidence)
        coarse,tract_aux=self.tract(excitation,codes,speaker_embedding,source_wav=wav)
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
             'harmonics':self.harmonics,'books':self.books,'book_size':self.book_size,
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

cat > tests/test_neural_v2_review_fix.py <<'PY'
import tempfile,unittest,torch
from pathlib import Path
from argon_neural_v2.source import HarmonicExcitation
from argon_neural_v2.tract import ConditionedBlock,DeepVocalTract
from argon_neural_v2.postfilter import WaveBlock,Snake1d
from argon_neural_v2.engine import ArgonNeuralV2

class ReviewFixTests(unittest.TestCase):
    def test_source_has_phase_offsets_and_full_harmonic_control(self):
        m=HarmonicExcitation(harmonics=32)
        self.assertEqual(tuple(m.phase_offset.shape),(32,))
        self.assertGreater(float(m.phase_offset.std()),.1)
        self.assertGreater(float(m.control[-1].weight.std()),.001)

    def test_deep_blocks_start_active(self):
        self.assertAlmostEqual(float(ConditionedBlock().gamma.mean()),.1,places=5)
        self.assertAlmostEqual(float(WaveBlock().gamma.mean()),.05,places=5)

    def test_tract_has_formant_filter(self):
        m=DeepVocalTract()
        self.assertEqual(m.spec_filter.out_channels,513)

    def test_engine_forward_convert_and_roundtrip(self):
        torch.manual_seed(3)
        m=ArgonNeuralV2()
        x=torch.randn(1,4800)*.02
        y,aux=m(x)
        self.assertEqual(y.shape,x.shape)
        self.assertTrue(torch.isfinite(y).all())
        self.assertIn('log_filter',aux)
        z=m.convert(x)
        self.assertEqual(z.shape,x.shape)
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'v2.pt';m.save(p,{'epoch':1})
            n,meta=ArgonNeuralV2.load(p)
            self.assertEqual(meta['epoch'],1)
            self.assertEqual(n.harmonics,32)

if __name__=='__main__':unittest.main()
PY

echo '=== COMPILE ==='
python3 -m py_compile argon_neural_v2/source.py argon_neural_v2/tract.py argon_neural_v2/postfilter.py argon_neural_v2/engine.py

echo '=== TESTS ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m unittest   tests.test_neural_v2_review_fix   tests.test_neural_v2_architecture -v

echo '=== ONE REAL TRAINING STEP ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python - <<'PY'
import torch
from argon_core.audio import read_audio
from argon_neural_v2.engine import ArgonNeuralV2
from argon_neural_v2.losses import natural_voice_loss

torch.set_num_threads(1)
x=read_audio('/srv/ARGON-VC/data/victor_source.wav',24000)[:12000][None]
m=ArgonNeuralV2().train()
opt=torch.optim.AdamW(m.parameters(),lr=8e-5)
y,aux=m(x)
loss=natural_voice_loss(y,x,24000)['total']+.015*aux['vq_loss']
assert torch.isfinite(loss)
opt.zero_grad(set_to_none=True);loss.backward()
gn=torch.nn.utils.clip_grad_norm_(m.parameters(),2.0)
opt.step()
print('TRAIN_STEP_OK',float(loss.detach()),float(gn))
PY

echo '=== TRAIN.PY INITIALIZATION CONTRACT ==='
grep -nE 'ArgonNeuralV2\(|load\(|output|checkpoint|seed_speaker' argon_neural_v2/train.py | head -120 || true

echo '=== V1 STILL ACTIVE ==='
systemctl is-active argon-neural-long.service || true
