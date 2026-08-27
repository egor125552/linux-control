#!/usr/bin/env bash
set -euo pipefail

echo '===== WAIT FOR LIVE WEBRTC CAPTURE ====='
found=no
for i in $(seq 1 20); do
  if pgrep -u egor -x parec >/dev/null 2>&1; then
    found=yes
    break
  fi
  sleep 0.5
done

echo "PAREC_ACTIVE=$found"
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -E '[p]arec|[a]udio_remote|[p]ython' | tail -n 40 || true

echo '===== WEBRTC JOURNAL AFTER RESTART ====='
journalctl -u audio-remote.service --since '2026-08-27 15:29:09' --no-pager -n 200 2>&1 || true

if [ "$found" = yes ]; then
  echo '===== SEND LONG SPEECH TEST ====='
  runuser -u egor -- env \
    HOME=/home/egor \
    XDG_RUNTIME_DIR=/run/egor-desktop \
    PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native' \
    PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE' \
    spd-say -w 'Проверка нового звука. Раз, два, три, четыре, пять. Сейчас речь должна идти ровно, без резких обрывов и без вываливания слов кусками.'
  echo LONG_AUDIO_TEST_SENT=yes
else
  echo LONG_AUDIO_TEST_SENT=no
fi

echo DONE
