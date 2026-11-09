#!/usr/bin/env bash
set -euo pipefail
WORK='/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 7 ручные дубли 9 ноября 2026'
python3 - <<'PY'
from pathlib import Path
import json
work=Path('/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 7 ручные дубли 9 ноября 2026')
for person,a,b in [('Александр',112,205),('Дмитрий',98,205)]:
    words=json.loads((work/f'Слова Vosk {person}.json').read_text('utf-8'))
    print('\n===',person,'WORDS',a,b,'===')
    for w in words:
        if w['end']>=a and w['start']<=b:
            print(f"{w['start']:.2f}-{w['end']:.2f}\t{w['word']}\tconf={w.get('conf',0):.2f}")
PY
echo '=== SILENCE ALEXANDER 112-205 ==='
ffmpeg -hide_banner -nostats -ss 112 -t 93 -i '/srv/ARGON-VC/data/ARGON uploads/Сцена 7 Александр.wav' -af 'silencedetect=noise=-38dB:d=0.25' -f null - 2>&1 | grep -E 'silence_(start|end)' || true
echo '=== SILENCE DMITRY 98-205 ==='
ffmpeg -hide_banner -nostats -ss 98 -t 107 -i '/srv/ARGON-VC/data/ARGON uploads/Сцена 7 Дмитрий.wav' -af 'silencedetect=noise=-38dB:d=0.25' -f null - 2>&1 | grep -E 'silence_(start|end)' || true
