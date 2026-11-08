#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC

echo '=== KEEP V1 ==='
systemctl is-active argon-neural-long.service || true

echo '=== STOP ONLY V2 AT SAFE CHECKPOINT ==='
systemctl stop argon-neural-v2.service || true
systemctl is-active argon-neural-v2.service || true

PUB='/srv/era-audio/argon-neural-v2-phase-fix'
mkdir -p "$PUB"

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
    v=spk.get(name)
    if not v: raise RuntimeError('missing speaker '+name)
    return torch.tensor(v,dtype=torch.float32)[None]

victor=read_audio(root/'data/victor_source.wav',24000)[:72000]
with torch.inference_mode():
    old_v,_=model(victor[None],speaker_embedding=emb('alexander'),shift_pitch=True)
write_audio(pub/'До исправления фазы Виктор в Александр.wav',old_v[0],24000)
write_audio(pub/'Исходник Виктор.wav',victor,24000)

exp=read_audio(root/'data/ARGON uploads/Экспериментальный голос.mp3',24000)
start=int(173.07*24000); exp=exp[start:start+72000]
with torch.inference_mode():
    old_e,_=model(exp[None],speaker_embedding=emb('experimental'),shift_pitch=True)
write_audio(pub/'До исправления фазы Экспериментальный.wav',old_e[0],24000)
write_audio(pub/'Исходник Экспериментальный.wav',exp,24000)

print(json.dumps({'epoch':meta.get('epoch'),'best_epoch':meta.get('best_epoch'),'best_val':meta.get('best_val')},ensure_ascii=False))
PY

find "$PUB" -maxdepth 1 -type f -printf '%f %s\n' | sort
