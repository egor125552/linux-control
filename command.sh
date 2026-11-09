#!/usr/bin/env bash
set -euo pipefail
echo '=== WORD TOOL ==='
cat '/srv/Zombie Horror Game/Tools/vosk/Разрезать по словам Vosk.py'
echo '=== PRODUCTION TAIL ==='
sed -n '525,696p' '/srv/Zombie Horror Game/Tools/vosk/Разрезать большой дубль Vosk.py'
