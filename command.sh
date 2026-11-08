#!/usr/bin/env bash
set -euo pipefail
cd /srv/ARGON-VC
echo '=== FEATURES ==='
sed -n '1,260p' argon_neural_v2/features.py 2>/dev/null || true
echo '=== CURRENT VOCOS ENGINE ==='
sed -n '1,280p' argon_neural_v2/vocos_engine.py
echo '=== TARGET DURATION ==='
ffprobe -v error -show_entries format=duration,size -of default=nw=1 'data/ARGON uploads/Экспериментальный голос.mp3'
echo '=== SOURCE DURATION ==='
ffprobe -v error -show_entries format=duration,size -of default=nw=1 data/victor_source.wav
