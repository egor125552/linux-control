#!/usr/bin/env bash
set -euo pipefail
for f in '/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 5 ручные дубли 6 ноября 2026/Довести нарезку.py' '/srv/Zombie Horror Game/Зимний прототип/scene/Сцена 6 Александр ручной дубль 6 ноября 2026/Довести Александра.py' '/srv/Zombie Horror Game/Зимний прототип/scene/Резерв нарезки Александра до захвата дыхания 6 ноября 2026/Довести Александра.py'; do
  echo "===== $f ====="
  if [ -f "$f" ]; then cat "$f"; else echo NOT_FOUND; fi
done
