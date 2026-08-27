#!/usr/bin/env bash
set -euo pipefail

server='unix:/run/egor-desktop/xpra/100/pulse/native'
cookie='/home/egor/.config/pulse/$PULSE_COOKIE'

[ -S /run/egor-desktop/xpra/100/pulse/native ] || { echo PULSE_SOCKET_MISSING; exit 1; }
[ -r "$cookie" ] || { echo PULSE_COOKIE_MISSING; exit 1; }

echo '===== STOP STALE SPEECH DISPATCHER ====='
pkill -u egor -f '(^|/)speech-dispatcher([[:space:]]|$)' 2>/dev/null || true
sleep 0.5
rm -f /home/egor/.cache/speech-dispatcher/pid/speech-dispatcher.pid

echo '===== START SPEECH DISPATCHER WITH XPRA AUDIO ====='
runuser -u egor -- env \
  HOME=/home/egor \
  PULSE_SERVER="$server" \
  PULSE_COOKIE="$cookie" \
  speech-dispatcher -d
sleep 1

ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep '[s]peech-dispatcher' || true

echo '===== RHVOICE LOG ====='
tail -n 20 /home/egor/.cache/speech-dispatcher/log/rhvoice.log 2>/dev/null || true

echo '===== SPEECHD LOG ====='
tail -n 20 /home/egor/.cache/speech-dispatcher/log/speech-dispatcher.log 2>/dev/null || true

echo '===== SPEAK TEST ====='
if command -v spd-say >/dev/null 2>&1; then
  runuser -u egor -- env \
    HOME=/home/egor \
    PULSE_SERVER="$server" \
    PULSE_COOKIE="$cookie" \
    spd-say -w 'Звук восстановлен' || true
else
  echo SPD_SAY_MISSING
fi

echo DONE
