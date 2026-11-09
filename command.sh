#!/usr/bin/env bash
set -euo pipefail
ROOT='/srv/Zombie Horror Game/Зимний прототип'
echo '=== SCENE6 WORKSPACE ==='
find "$ROOT/scene/Сцена 6 ручные дубли 6 ноября 2026" -maxdepth 3 -type f -printf '%p\n' 2>/dev/null | sort | sed -n '1,240p'
echo '=== DOVESTI SCRIPTS ==='
for f in "$ROOT/scene/Сцена 5 ручные дубли 6 ноября 2026/Довести нарезку.py" "$ROOT/scene/Сцена 6 Александр ручной дубль 6 ноября 2026/Довести Александра.py" "$ROOT/scene/Резерв нарезки Александра до захвата дыхания 6 ноября 2026/Довести Александра.py" "$ROOT/tests/Проверка голосов продолжения.py" '/srv/Zombie Horror Game/Tools/vosk/Разрезать по словам Vosk.py'; do
  echo "----- $f -----"
  [ -f "$f" ] && sed -n '1,320p' "$f" || echo NOT_FOUND
done
echo '=== SEARCH LONGEST/DURATION MATCHING ==='
grep -RniE 'duration|длительн|reverse=True|reverse *= *True|sorted\(|longest|длинн|коротк|ratio|match' "$ROOT/scene" "$ROOT/tools" 2>/dev/null | grep -E 'Довести|ручн|Vosk|нарез|дубл' | head -260 || true
