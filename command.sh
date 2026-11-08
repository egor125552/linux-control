#!/usr/bin/env bash
set -euo pipefail
cd '/srv/Zombie Horror Game/Зимний прототип'

echo '=== TRAINING STILL ACTIVE ==='
systemctl is-active argon-neural-long.service || true

echo '=== VOICES ==='
sed -n '1,220p' 'scene/Голоса Google TTS.txt' 2>/dev/null || true

echo '=== GEMINI TTS GUIDE ==='
sed -n '1,320p' 'Как работать с Gemini TTS для ChatGPT.txt' 2>/dev/null || true

echo '=== RELATED SCRIPTS ==='
find . -maxdepth 4 -type f \( -iname '*.py' -o -iname '*.sh' -o -iname '*.js' \) -print0 2>/dev/null  | xargs -0 grep -IlE 'gemini.*tts|generate.*speech|response_modalities.*AUDIO|prebuilt_voice_config|speech_config' 2>/dev/null  | head -50 || true
