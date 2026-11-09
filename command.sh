#!/usr/bin/env bash
set -euo pipefail
echo '=== WORD TOOL ==='
cat '/srv/Zombie Horror Game/Tools/vosk/Разрезать по словам Vosk.py'
echo '=== PRODUCTION CORE 525-696 ==='
sed -n '525,696p' '/srv/Zombie Horror Game/Tools/vosk/Разрезать большой дубль Vosk.py'
echo '=== SEARCH BIG SMALL ==='
grep -RniE 'больш.*меньш|длин.*корот|sort.*duration|duration.*sort|reverse=True' '/srv/Zombie Horror Game/Зимний прототип' '/srv/Zombie Horror Game/Tools' 2>/dev/null | head -200 || true
