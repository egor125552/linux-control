#!/usr/bin/env bash
set -euo pipefail
R='/srv/Zombie Horror Game/Зимний прототип'
echo '===== main.js 1-308 ====='
nl -ba "$R/js/main.js" | sed -n '1,308p'
echo '===== Лаборатория сцена 6.js mechanics 1-202 ====='
nl -ba "$R/js/mechanics/Лаборатория сцена 6.js" | sed -n '1,202p'
