#!/usr/bin/env bash
set -euo pipefail

server='unix:/run/egor-desktop/xpra/100/pulse/native'
cookie='/home/egor/.config/pulse/$PULSE_COOKIE'

[ -S /run/egor-desktop/xpra/100/pulse/native ] || { echo PULSE_SOCKET_MISSING; exit 1; }
[ -r "$cookie" ] || { echo PULSE_COOKIE_MISSING; exit 1; }

# Stop any broken/stale speech daemon, then launch a replacement without the
# GitHub runner tracking variable so post-job orphan cleanup does not kill it.
pkill -u egor -f '(^|/)speech-dispatcher([[:space:]]|$)' 2>/dev/null || true
pkill -u egor -x sd_rhvoice 2>/dev/null || true
rm -f /home/egor/.cache/speech-dispatcher/pid/speech-dispatcher.pid
sleep 0.3

runuser -u egor -- env -u RUNNER_TRACKING_ID \
  HOME=/home/egor \
  PULSE_SERVER="$server" \
  PULSE_COOKIE="$cookie" \
  speech-dispatcher -d
sleep 1

echo '===== STARTED ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -E '[s]peech-dispatcher|[s]d_rhvoice' || true

echo '===== ENV CHECK ====='
for p in $(pgrep -u egor -f '(^|/)speech-dispatcher([[:space:]]|$)' || true); do
  echo "PID=$p"
  tr '\0' '\n' < "/proc/$p/environ" | grep -E '^(PULSE_SERVER|PULSE_COOKIE|RUNNER_TRACKING_ID)=' || true
done

echo '===== RHVOICE ====='
tail -n 12 /home/egor/.cache/speech-dispatcher/log/rhvoice.log 2>/dev/null || true

echo SPEECH_DAEMON_STARTED=yes
