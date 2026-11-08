#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

python3 - <<'PY'
from pathlib import Path
p=Path('argon_neural_v2/vocos_engine.py')
s=p.read_text()
old="""        self.net.train()
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
"""
new="""        self.net.train()
        opt = torch.optim.AdamW(self.net.parameters(), lr=lr, weight_decay=1e-4)
        batch_chunks = min(16, n_chunks)
        sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=lr, total_steps=max(1, epochs))
        g = torch.Generator(device='cpu')
        g.manual_seed(1337)
        epoch_losses = []

        for ep in range(epochs):
            order = torch.randperm(n_chunks, generator=g)[:batch_chunks].to(self.device)
            opt.zero_grad(set_to_none=True)
            pred_mel = self.net(
                b_w[order], b_k[order], b_f[order],
                b_e[order], b_v[order],
            )
            tgt = b_m[order]
            l1_loss = F.l1_loss(pred_mel, tgt)
            delta_pred = pred_mel[:, :, 1:] - pred_mel[:, :, :-1]
            delta_tgt = tgt[:, :, 1:] - tgt[:, :, :-1]
            loss = l1_loss + 0.8 * F.l1_loss(delta_pred, delta_tgt)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(self.net.parameters(), 2.0)
            opt.step()
            sched.step()
            epoch_losses.append(float(loss.detach().item()))
"""
if old not in s:
    raise SystemExit('training block not found')
p.write_text(s.replace(old,new))
print('patched vectorized training')
PY

cat > /tmp/train_argon_vocos_hd.py <<'PY'
from pathlib import Path
import json, time
import torch
from argon_core.audio import read_audio, write_audio
from argon_neural_v2.vocos_engine import ArgonStudioVC

root=Path('/srv/ARGON-VC')
pub=Path('/srv/era-audio/argon-neural-v2-vocos-hd')
pub.mkdir(parents=True,exist_ok=True)

target=read_audio(root/'data/ARGON uploads/Экспериментальный голос.mp3',24000)
source=read_audio(root/'data/victor_source.wav',24000)[:72000]
clip_len=4*24000
margin=8*24000
starts=torch.linspace(margin,target.numel()-margin-clip_len,steps=24).long().tolist()
clips=[target[s:s+clip_len] for s in starts if s+clip_len<=target.numel()]

t=time.time()
m=ArgonStudioVC('cpu')
print('MODEL_READY',round(time.time()-t,2),flush=True)

t=time.time()
stats=m.fit_target_voice(clips,epochs=35,lr=1e-3)
print('FIT_SECONDS',round(time.time()-t,2),flush=True)

t=time.time()
with torch.inference_mode():
    out=m.convert(source)
print('CONVERT_SECONDS',round(time.time()-t,2),flush=True)

raw_peak=float(out.abs().max())
gain=min(1.0,0.95/max(raw_peak,1e-8))
out=(out*gain).clamp(-0.95,0.95)
sil=torch.zeros(int(.45*24000))

write_audio(pub/'Исходник Виктор фраза.wav',source,24000)
write_audio(pub/'ARGON Vocos HD v1.2 фраза.wav',out,24000)
write_audio(pub/'A-B Виктор и ARGON Vocos HD v1.2.wav',torch.cat([source,sil,out]),24000)

old=Path('/srv/era-audio/argon-neural-v2-vocos-test/ARGON Vocos средняя чистая.wav')
if old.exists():
    old_w=read_audio(old,24000)
    n=min(old_w.numel(),out.numel())
    write_audio(pub/'Сравнение старый Vocos и HD v1.2.wav',torch.cat([old_w[:n],sil,out[:n]]),24000)

torch.save({
    'net':m.net.state_dict(),
    'bank_keys':m.bank_keys.cpu(),
    'bank_mels':m.bank_mels.cpu(),
    'target_f0_median':m.target_f0_median,
    'target_mel_mean':m.target_mel_mean.cpu(),
    'target_mel_std':m.target_mel_std.cpu(),
    'stats':stats,
},pub/'ARGON Vocos HD v1.2.pt')

print(json.dumps({**stats,'target_clips':len(clips),'target_seconds':len(clips)*4,'raw_peak':raw_peak,'gain':gain},ensure_ascii=False),flush=True)
PY

echo '=== CHECK ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python -m py_compile argon_neural_v2/vocos_engine.py /tmp/train_argon_vocos_hd.py
python3 - <<'PY'
from pathlib import Path
s=Path('argon_neural_v2/vocos_engine.py').read_text()
print('instance_norm_removed', 'F.instance_norm' not in s)
print('context_3', "kernel_size=3" in s)
print('top16', 'top_k: int = 16' in s)
print('bank45k', 'max_bank = 45000' in s)
print('crisp', 'crisp_articulation' in s)
print('vectorized_training', 'b_w[order]' in s)
PY

echo '=== TRAIN HD ==='
PYTHONPATH=/srv/ARGON-VC /srv/era-audio/venv/bin/python /tmp/train_argon_vocos_hd.py

echo '=== OUTPUTS ==='
find /srv/era-audio/argon-neural-v2-vocos-hd -maxdepth 1 -type f -printf '%f %s bytes\n' | sort
echo '=== URLS ==='
/srv/era-audio/venv/bin/python - <<'PY'
from pathlib import Path
from urllib.parse import quote
root=Path('/srv/era-audio/argon-neural-v2-vocos-hd')
base='https://169-58-224-216.sslip.io/era-audio/argon-neural-v2-vocos-hd/'
for p in sorted(root.glob('*.wav')):
    print('URL',base+quote(p.name))
PY
echo '=== OLD ARGON ==='
systemctl is-active argon-neural-v2.service || true
