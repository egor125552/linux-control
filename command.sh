#!/usr/bin/env bash
set -euo pipefail
R='/srv/Zombie Horror Game/Зимний прототип'
for p in  js/main.js  js/mechanics/Лаборатория\ сцена\ 6.js  js/content/Лаборатория\ сцена\ 6.js  js/audio/Музыка\ сцены\ 6.js  js/audio/Звуки\ шестой\ сцены.js  js/audio/spatial-audio.js  js/mechanics/walking.js  js/mechanics/player-footsteps.js  js/game/player.js  js/mechanics/Чекпойнты.js
do
  printf '%s ' "$p"; wc -l < "$R/$p"
done
