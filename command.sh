#!/usr/bin/env bash
set -euo pipefail

echo '===== FINAL LIVE CHECK AFTER RUNNER CLEANUP ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -E '[o]rca|[s]peech-dispatcher|[s]d_rhvoice' || true

orca=$(pgrep -u egor -x orca | while read -r p; do st=$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true); [ "$st" != Z ] && echo "$p"; done | tail -1)
spd=$(pgrep -u egor -f '(^|/)speech-dispatcher([[:space:]]|$)' | head -1 || true)
rhv=$(pgrep -u egor -x sd_rhvoice | head -1 || true)

[ -n "$orca" ] || { echo LIVE_ORCA_MISSING; exit 1; }
[ -n "$spd" ] || { echo LIVE_SPEECH_DISPATCHER_MISSING; exit 1; }
[ -n "$rhv" ] || { echo LIVE_RHVOICE_MISSING; exit 1; }
grep -q '/opt/orca-51/' "/proc/$orca/maps"

echo "LIVE_ORCA=$orca LIVE_SPEECH=$spd LIVE_RHVOICE=$rhv"

echo '===== LATEST RHVOICE AUDIO STATUS ====='
tail -n 20 /home/egor/.cache/speech-dispatcher/log/rhvoice.log 2>/dev/null || true
grep -q 'Audio output initialized' /home/egor/.cache/speech-dispatcher/log/rhvoice.log

echo '===== AUDIBLE TEST ====='
runuser -u egor -- env \
  HOME=/home/egor \
  XDG_RUNTIME_DIR=/run/egor-desktop \
  PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native' \
  PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE' \
  spd-say -w 'Орка снова говорит'

echo FINAL_AUDIO_TEST_SENT=yes
