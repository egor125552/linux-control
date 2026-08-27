#!/usr/bin/env bash
set -euo pipefail

echo '===== SPEECH STACK AFTER PREVIOUS RUN CLEANUP ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -E '[s]peech-dispatcher|[s]d_rhvoice' || true

spid=$(pgrep -u egor -f '(^|/)speech-dispatcher([[:space:]]|$)' | head -1 || true)
rpid=$(pgrep -u egor -x sd_rhvoice | head -1 || true)
[ -n "$spid" ] || { echo SPEECH_DISPATCHER_MISSING=yes; exit 1; }
[ -n "$rpid" ] || { echo RHVOICE_MODULE_MISSING=yes; exit 1; }

echo "SPEECH_PID=$spid"
echo "RHVOICE_PID=$rpid"
if tr '\0' '\n' < "/proc/$spid/environ" | grep -q '^RUNNER_TRACKING_ID='; then
  echo RUNNER_TRACKING_ID_PRESENT=yes
  exit 1
else
  echo RUNNER_TRACKING_ID_PRESENT=no
fi

echo '===== RHVOICE AUDIO ====='
tail -n 12 /home/egor/.cache/speech-dispatcher/log/rhvoice.log 2>/dev/null || true
grep -q 'Audio output initialized' /home/egor/.cache/speech-dispatcher/log/rhvoice.log

echo SPEECH_PERSISTED_AFTER_CLEANUP=yes
