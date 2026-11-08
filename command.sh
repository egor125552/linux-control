#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
STAMP=$(date +%Y%m%d-%H%M%S)
PUB=/srv/era-audio/argon-neural-v2-vocos-hd
mkdir -p "$PUB" backups
cp -f argon_neural_v2/vocos_engine.py "backups/vocos_engine-pre-hd-$STAMP.py"

cat > argon_neural_v2/vocos_engine.py <<'PY'
from __future__ import annotations
import math
import torch
import torch.nn as nn
import torch.nn.functional as F
import torchaudio
from vocos import Vocos
from .features import pitch_energy, align_frames

class ConvNeXtMelBlock(nn.Module):
    def __init__(self, dim: int = 256, dilation: int = 1):
        super().__init__()
        self.dw = nn.Conv1d(dim, dim, kernel_size=7, padding=3 * dilation, dilation=dilation, groups=dim)
        self.norm = nn.GroupNorm(1, dim)
        self.pw1 = nn.Conv1d(dim, dim * 3, 1)
        self.pw2 = nn.Conv1d(dim * 3, dim, 1)
        self.gamma = nn.Parameter(torch.ones(1, dim, 1) * 0.15)

    def forward(self, x: torch.Tensor, f0_cond: torch.Tensor) -> torch.Tensor:
        h = self.norm(self.dw(x)) + f0_cond
        h = self.pw2(F.gelu(self.pw1(h)))
        return x + self.gamma * h

class ArgonMelNetwork(nn.Module):
    def __init__(self, wavlm_dim: int = 768, mel_bins: int = 100, hidden_dim: int = 256):
        super().__init__()
        self.in_wavlm = nn.Conv1d(wavlm_dim, hidden_dim, 1)
        self.in_knn = nn.Conv1d(mel_bins, hidden_dim, 1)
        self.f0_encoder = nn.Sequential(
            nn.Conv1d(3, hidden_dim, 3, padding=1),
            nn.GELU(),
            nn.Conv1d(hidden_dim, hidden_dim, 1),
        )
        self.blocks = nn.ModuleList([
            ConvNeXtMelBlock(hidden_dim, d) for d in (1, 2, 4, 8, 1, 2, 4, 8)
        ])
        self.out_proj = nn.Conv1d(hidden_dim, mel_bins, 3, padding=1)
        nn.init.zeros_(self.out_proj.weight)
        nn.init.zeros_(self.out_proj.bias)

    def forward(self, wavlm_feats, knn_mel, f0, energy, voiced):
        log_f0 = torch.where(
            voiced > 0.5,
            torch.log(f0.clamp_min(50.0)) / 6.0,
            torch.zeros_like(f0),
        )
        ctrl = torch.stack((log_f0, energy, voiced), dim=1)
        f0_cond = self.f0_encoder(ctrl)
        h = self.in_wavlm(wavlm_feats) + self.in_knn(knn_mel) + f0_cond
        for block in self.blocks:
            h = block(h, f0_cond)
        return knn_mel + self.out_proj(h)

# Compatibility with the first Vocos experiment.
MelNet = ArgonMelNetwork

class ArgonStudioVC:
    """ARGON Vocos v1.2 Anti-8kbps HD."""
    def __init__(self, device: str = 'cpu'):
        self.device = torch.device(device)
        self.sample_rate = 24000
        self.hop = 256

        self.vocos = Vocos.from_pretrained("charactr/vocos-mel-24khz").to(self.device).eval()
        for p in self.vocos.parameters():
            p.requires_grad_(False)

        bundle = torchaudio.pipelines.WAVLM_BASE
        self.wavlm = bundle.get_model().to(self.device).eval()
        for p in self.wavlm.parameters():
            p.requires_grad_(False)

        self.net = ArgonMelNetwork(wavlm_dim=768, mel_bins=100, hidden_dim=256).to(self.device)
        self.bank_keys = None
        self.bank_mels = None
        self.target_f0_median = 120.0
        self.target_mel_mean = None
        self.target_mel_std = None

    @torch.inference_mode()
    def extract_features(self, wav_24k: torch.Tensor) -> dict[str, torch.Tensor]:
        if wav_24k.ndim == 1:
            wav_24k = wav_24k[None, :]
        wav_24k = wav_24k.to(self.device)

        mel = self.vocos.feature_extractor(wav_24k)
        t_mel = mel.shape[-1]

        wav_16k = torchaudio.functional.resample(wav_24k, 24000, 16000)
        feats_list, _ = self.wavlm.extract_features(wav_16k, num_layers=7)
        w_feat = (feats_list[4] + feats_list[5] + feats_list[6]) / 3.0
        w_feat = w_feat.transpose(1, 2)
        w_feat = align_frames(w_feat, t_mel)

        w_smooth = F.avg_pool1d(
            F.pad(w_feat, (1, 1), mode='replicate'),
            kernel_size=3,
            stride=1,
        )
        w_norm = F.normalize(w_smooth, dim=1)

        f0, energy, conf = pitch_energy(wav_24k, sample_rate=24000, hop=self.hop)
        f0 = align_frames(f0, t_mel)
        energy = align_frames(energy, t_mel)
        voiced = (f0 > 20.0).float()
        return {
            'mel': mel,
            'wavlm': w_norm,
            'f0': f0,
            'energy': energy,
            'voiced': voiced,
        }

    # Compatibility aliases.
    features = extract_features

    @torch.inference_mode()
    def kNN_match(self, wavlm_feats: torch.Tensor, top_k: int = 16, temp: float = 0.12) -> torch.Tensor:
        if self.bank_keys is None or self.bank_mels is None:
            raise RuntimeError('target voice bank is not fitted')
        b, c, t = wavlm_feats.shape
        q = F.normalize(wavlm_feats.transpose(1, 2).reshape(-1, c), dim=-1)
        out = []
        # Chunk source queries too, so long phrases do not allocate one huge similarity matrix.
        for i in range(0, q.shape[0], 1024):
            qs = q[i:i + 1024]
            sim = torch.matmul(qs, self.bank_keys.T)
            top_vals, top_idx = sim.topk(min(top_k, self.bank_keys.shape[0]), dim=-1)
            weights = F.softmax(top_vals / temp, dim=-1).unsqueeze(-1)
            out.append((self.bank_mels[top_idx] * weights).sum(dim=1))
        matched = torch.cat(out, dim=0)
        mel_knn = matched.reshape(b, t, 100).transpose(1, 2)
        mel_knn = F.avg_pool1d(
            F.pad(mel_knn, (1, 1), mode='replicate'),
            kernel_size=3,
            stride=1,
        )
        return mel_knn

    def knn(self, z, k=16, temp=0.12):
        return self.kNN_match(z, top_k=k, temp=temp)

    def fit_target_voice(self, target_clips: list[torch.Tensor], epochs: int = 35, lr: float = 1e-3) -> dict:
        all_w, all_m, all_f0, all_en, all_v = [], [], [], [], []
        for clip in target_clips:
            if clip.shape[-1] < 16000:
                continue
            d = self.extract_features(clip)
            all_w.append(d['wavlm'][0].cpu())
            all_m.append(d['mel'][0].cpu())
            all_f0.append(d['f0'][0].cpu())
            all_en.append(d['energy'][0].cpu())
            all_v.append(d['voiced'][0].cpu())

        if not all_w:
            raise RuntimeError('no usable target clips')

        W = torch.cat(all_w, dim=-1).to(self.device)
        M = torch.cat(all_m, dim=-1).to(self.device)
        F0 = torch.cat(all_f0, dim=-1).to(self.device)
        EN = torch.cat(all_en, dim=-1).to(self.device)
        V = torch.cat(all_v, dim=-1).to(self.device)

        voiced_f0 = F0[V > 0.5]
        if voiced_f0.numel() > 10:
            self.target_f0_median = float(voiced_f0.median().item())

        self.target_mel_mean = M.mean(dim=-1, keepdim=True)
        self.target_mel_std = M.std(dim=-1, keepdim=True).clamp_min(1e-4)

        keys = F.normalize(W.T, dim=-1)
        mels = M.T
        max_bank = 45000
        if keys.shape[0] > max_bank:
            step = keys.shape[0] / max_bank
            idx = torch.arange(0, max_bank, device=self.device).float().mul(step).long().clamp_max(keys.shape[0] - 1)
            self.bank_keys = keys[idx].contiguous()
            self.bank_mels = mels[idx].contiguous()
        else:
            self.bank_keys = keys.contiguous()
            self.bank_mels = mels.contiguous()

        with torch.no_grad():
            knn_chunks = []
            full_bank = self.bank_keys.shape[0] == keys.shape[0]
            for i in range(0, keys.shape[0], 1024):
                q_slice = keys[i:i + 1024]
                sim = torch.matmul(q_slice, self.bank_keys.T)
                want = min(17 if full_bank else 16, self.bank_keys.shape[0])
                top_vals, top_idx = sim.topk(want, dim=-1)
                if full_bank and want > 1:
                    top_vals, top_idx = top_vals[:, 1:], top_idx[:, 1:]
                w_knn = F.softmax(top_vals / 0.12, dim=-1).unsqueeze(-1)
                knn_chunks.append((self.bank_mels[top_idx] * w_knn).sum(dim=1))
            knn_mel_all = torch.cat(knn_chunks, dim=0).T
            knn_mel_all = F.avg_pool1d(
                F.pad(knn_mel_all[None], (1, 1), mode='replicate'),
                kernel_size=3,
                stride=1,
            )[0]

        chunk = 128
        n_chunks = W.shape[-1] // chunk
        if n_chunks < 1:
            raise RuntimeError('target material is too short')
        size = n_chunks * chunk
        b_w = W[:, :size].reshape(768, n_chunks, chunk).permute(1, 0, 2).contiguous()
        b_m = M[:, :size].reshape(100, n_chunks, chunk).permute(1, 0, 2).contiguous()
        b_k = knn_mel_all[:, :size].reshape(100, n_chunks, chunk).permute(1, 0, 2).contiguous()
        b_f = F0[:size].reshape(n_chunks, chunk).contiguous()
        b_e = EN[:size].reshape(n_chunks, chunk).contiguous()
        b_v = V[:size].reshape(n_chunks, chunk).contiguous()

        self.net.train()
        opt = torch.optim.AdamW(self.net.parameters(), lr=lr, weight_decay=1e-4)
        steps_per_epoch = min(16, n_chunks)
        total_steps = max(1, epochs * steps_per_epoch)
        sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=lr, total_steps=total_steps)
        g = torch.Generator(device='cpu')
        g.manual_seed(1337)
        epoch_losses = []

        for ep in range(epochs):
            order = torch.randperm(n_chunks, generator=g)[:steps_per_epoch].to(self.device)
            step_losses = []
            for ix in order:
                ix = int(ix.item())
                opt.zero_grad(set_to_none=True)
                pred_mel = self.net(
                    b_w[ix:ix+1], b_k[ix:ix+1], b_f[ix:ix+1],
                    b_e[ix:ix+1], b_v[ix:ix+1],
                )
                tgt = b_m[ix:ix+1]
                l1_loss = F.l1_loss(pred_mel, tgt)
                delta_pred = pred_mel[:, :, 1:] - pred_mel[:, :, :-1]
                delta_tgt = tgt[:, :, 1:] - tgt[:, :, :-1]
                loss = l1_loss + 0.8 * F.l1_loss(delta_pred, delta_tgt)
                loss.backward()
                torch.nn.utils.clip_grad_norm_(self.net.parameters(), 2.0)
                opt.step()
                sched.step()
                step_losses.append(float(loss.detach().item()))
            epoch_losses.append(sum(step_losses) / len(step_losses))

        self.net.eval()
        return {
            'start_loss': epoch_losses[0],
            'end_loss': epoch_losses[-1],
            'frames': int(W.shape[-1]),
            'bank_frames': int(self.bank_keys.shape[0]),
            'f0_med': self.target_f0_median,
        }

    def fit(self, clips, epochs=35, lr=1e-3):
        return self.fit_target_voice(clips, epochs=epochs, lr=lr)

    @torch.inference_mode()
    def convert(self, source_wav_24k: torch.Tensor) -> torch.Tensor:
        self.net.eval()
        if self.target_mel_mean is None or self.target_mel_std is None:
            raise RuntimeError('target mel statistics are not fitted')

        d = self.extract_features(source_wav_24k)
        f0 = d['f0'].clone()
        v = d['voiced'] > 0.5
        if v.any():
            src_med = f0[v].median().clamp_min(50.0)
            ratio = (torch.as_tensor(self.target_f0_median, device=f0.device) / src_med).clamp(0.55, 1.85)
            f0[v] = (f0[v] * ratio).clamp(55.0, 450.0)

        knn_mel = self.kNN_match(d['wavlm'], top_k=16, temp=0.12)
        net_mel = self.net(d['wavlm'], knn_mel, f0, d['energy'], d['voiced'])
        target_base = 0.65 * net_mel + 0.35 * knn_mel

        src_mel = d['mel']
        src_norm = (
            (src_mel - src_mel.mean(dim=-1, keepdim=True))
            / src_mel.std(dim=-1, keepdim=True).clamp_min(1e-4)
        )
        src_aligned = src_norm * self.target_mel_std[None] + self.target_mel_mean[None]
        src_smooth = F.avg_pool1d(
            F.pad(src_aligned, (2, 2), mode='replicate'),
            kernel_size=5,
            stride=1,
        )
        crisp_articulation = src_aligned - src_smooth

        final_mel = target_base + 0.45 * crisp_articulation
        wav_out = self.vocos.decode(final_mel)
        return wav_out.squeeze(0)
PY

cat > /tmp/train_argon_vocos_hd.py <<'PY'
from pathlib import Path
import json
import torch
from argon_core.audio import read_audio, write_audio
from argon_neural_v2.vocos_engine import ArgonStudioVC

root = Path('/srv/ARGON-VC')
pub = Path('/srv/era-audio/argon-neural-v2-vocos-hd')
target = read_audio(root/'data/ARGON uploads/Экспериментальный голос.mp3', 24000)
source_full = read_audio(root/'data/victor_source.wav', 24000)
source = source_full[:72000]

# 24 x 4 seconds, spread over the whole 21-minute target recording.
clip_len = 4 * 24000
margin = 8 * 24000
usable_start = margin
usable_end = max(usable_start + clip_len, target.numel() - margin - clip_len)
starts = torch.linspace(usable_start, usable_end, steps=24).long().tolist()
clips = [target[s:s+clip_len] for s in starts if s + clip_len <= target.numel()]

m = ArgonStudioVC('cpu')
stats = m.fit_target_voice(clips, epochs=35, lr=1e-3)

with torch.inference_mode():
    out = m.convert(source)

raw_peak = float(out.abs().max())
gain = min(1.0, 0.95 / max(raw_peak, 1e-8))
out = (out * gain).clamp(-0.95, 0.95)

sil = torch.zeros(int(0.45 * 24000))
write_audio(pub/'Исходник Виктор фраза.wav', source, 24000)
write_audio(pub/'ARGON Vocos HD v1.2 фраза.wav', out, 24000)
write_audio(pub/'A-B Виктор и ARGON Vocos HD v1.2.wav', torch.cat([source, sil, out]), 24000)

old = Path('/srv/era-audio/argon-neural-v2-vocos-test/ARGON Vocos средняя чистая.wav')
if old.exists():
    old_w = read_audio(old, 24000)
    n = min(source.numel(), old_w.numel(), out.numel())
    write_audio(
        pub/'Сравнение старый Vocos и HD v1.2.wav',
        torch.cat([old_w[:n], sil, out[:n]]),
        24000,
    )

torch.save({
    'net': m.net.state_dict(),
    'bank_keys': m.bank_keys.cpu(),
    'bank_mels': m.bank_mels.cpu(),
    'target_f0_median': m.target_f0_median,
    'target_mel_mean': m.target_mel_mean.cpu(),
    'target_mel_std': m.target_mel_std.cpu(),
    'stats': stats,
}, pub/'ARGON Vocos HD v1.2.pt')

print(json.dumps({
    **stats,
    'target_clips': len(clips),
    'target_seconds': len(clips) * 4,
    'raw_peak': raw_peak,
    'gain': gain,
}, ensure_ascii=False))
PY

echo '=== STATIC CHECK ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m py_compile argon_neural_v2/vocos_engine.py /tmp/train_argon_vocos_hd.py
python3 - <<'PY'
from pathlib import Path
s=Path('argon_neural_v2/vocos_engine.py').read_text()
print('instance_norm', 'instance_norm' in s)
print('top_k_16', 'top_k: int = 16' in s)
print('bank_45000', 'max_bank = 45000' in s)
print('crisp_articulation', 'crisp_articulation' in s)
print('source_wav_literal', 'source_wav' in s)
PY

echo '=== TRAIN + SAME PHRASE ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python /tmp/train_argon_vocos_hd.py

echo '=== OUTPUTS ==='
find "$PUB" -maxdepth 1 -type f -printf '%f %s bytes\n' | sort
for f in "$PUB"/*.wav; do
  printf '%s ' "$(basename "$f")"
  ffprobe -v error -show_entries format=duration,size -of csv=p=0 "$f"
done

echo '=== URLS ==='
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
from urllib.parse import quote
root=Path('/srv/era-audio/argon-neural-v2-vocos-hd')
base='https://169-58-224-216.sslip.io/era-audio/argon-neural-v2-vocos-hd/'
for p in sorted(root.glob('*.wav')):
    print('URL', base + quote(p.name))
PY

echo '=== OLD SERVICE ==='
systemctl is-active argon-neural-v2.service || true
