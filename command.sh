#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
echo '=== TRAINING ==='
systemctl is-active argon-neural-long.service || true
ps -eo pid,etime,%cpu,%mem,args | grep 'argon_core.neural_continue' | grep -v grep || true

echo '=== TTS BINARIES ==='
command -v edge-tts || true
command -v piper || true
command -v espeak-ng || true
command -v espeak || true

echo '=== PYTHON TTS PACKAGES ==='
/srv/era-audio/venv/bin/python - <<'PY'
mods=['edge_tts','google.cloud.texttospeech','gtts','TTS','piper']
for m in mods:
    try:
        __import__(m)
        print('YES',m)
    except Exception as e:
        print('NO',m,type(e).__name__)
PY

echo '=== PROJECT TTS HINTS ==='
grep -RIlE 'google.*tts|texttospeech|edge_tts|edge-tts|gemini.*tts|speech.*synth|Olgido|Daro|Enzo' '/srv/Zombie Horror Game' '/srv/ARGON-VC' 2>/dev/null | head -80 || true
