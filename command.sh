#!/usr/bin/env bash
set -euo pipefail
echo '=== SPLITTER CLI ==='
grep -nE 'ArgumentParser|add_argument|parse_args|def main|__main__|report|output|script' '/srv/Zombie Horror Game/Tools/vosk/Разрезать большой дубль Vosk.py' | tail -120
echo '=== UPLOAD SERVICE ==='
grep -nE 'PORT|HOST|do_POST|do_GET|upload|WINTER|ARGON|Path\(|server|HTTPServer|Threading|url|endpoint|route' '/srv/Zombie Horror Game/Server/voice_upload.py' | head -260
echo '=== SERVICE STATUS ==='
ps aux | grep -E '[v]oice_upload.py|[u]vicorn|[g]unicorn' || true
ss -ltnp | grep -E ':(8000|8080|8765|8787|9000|5000|3000)\b' || true
