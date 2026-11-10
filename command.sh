#!/usr/bin/env bash
set -euo pipefail
R='/srv/Zombie Horror Game/Зимний прототип'
echo '===== main.js 175-265 ====='
nl -ba "$R/js/main.js" | sed -n '175,265p'
echo '===== checkpoints full ====='
nl -ba "$R/js/mechanics/Чекпойнты.js"
echo '===== scene6 music full ====='
nl -ba "$R/js/audio/Музыка сцены 6.js"
