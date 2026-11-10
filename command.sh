#!/usr/bin/env bash
set -euo pipefail
R='/srv/Zombie Horror Game/Зимний прототип'
for p in   js/main.js   js/core/runtime.js   js/core/event-bus.js   js/input/gesture-controller.js   js/input/input-forwarder.js   js/input/Клавиатура.js   js/input/Доступность\ лаборатории.js
do
  echo "===== $p ====="
  cat "$R/$p"
done
