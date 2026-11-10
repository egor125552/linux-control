#!/usr/bin/env bash
set -euo pipefail
R='/srv/Zombie Horror Game/Зимний прототип'
for p in  js/mechanics/walking.js  js/mechanics/player-footsteps.js  js/game/player.js  js/mechanics/Чекпойнты.js  js/audio/Музыка\ сцены\ 6.js  js/audio/Звуки\ шестой\ сцены.js
do
 echo "===== $p ====="
 nl -ba "$R/$p"
done
