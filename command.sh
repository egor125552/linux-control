#!/usr/bin/env bash
set -euo pipefail
R='/srv/Zombie Horror Game/Зимний прототип'
echo '===== scene6 content 1-216 ====='
nl -ba "$R/js/content/Лаборатория сцена 6.js" | sed -n '1,216p'
