#!/usr/bin/env bash
set -euo pipefail
echo '=== BIG SPLITTER ==='
for f in '/srv/Zombie Horror Game/Tools/vosk/Разрезать большой дубль Vosk.py' '/srv/Zombie Horror Game/Tools/vosk/Разрезать большой дубль Vosk резерв до захвата дыхания 6 ноября 2026.py' '/srv/Zombie Horror Game/Tools/vosk/Разрезать по словам Vosk.py' '/srv/Zombie Horror Game/Server/voice_upload.py'; do
  echo "----- $f -----"
  if [ -f "$f" ]; then sed -n '1,260p' "$f"; else echo NOT_FOUND; fi
done
echo '=== RECENT AUDIO ON SERVER ==='
find '/srv/Zombie Horror Game' -type f \( -iname '*.wav' -o -iname '*.mp3' -o -iname '*.m4a' \) -printf '%T@ %s %p\n' 2>/dev/null | sort -nr | head -80
