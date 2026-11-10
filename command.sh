#!/usr/bin/env bash
set -euo pipefail
R='/srv/Zombie Horror Game/Зимний прототип'
echo '===== spatial-audio 1-190 ====='
nl -ba "$R/js/audio/spatial-audio.js" | sed -n '1,190p'
echo '===== spatial-audio 191-366 ====='
nl -ba "$R/js/audio/spatial-audio.js" | sed -n '191,366p'
