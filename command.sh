#!/usr/bin/env bash
set -euo pipefail

echo '===== LIVE ORCA ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep '[o]rca' || true

echo '===== SPEECH DISPATCHER PROCESSES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep '[s]peech-dispatcher' || true
pgrep -a -u egor speech-dispatcher || true

echo '===== ORCA DEBUG TAIL ====='
if [ -f /home/egor/.local/state/orca/orca-debug.log ]; then
  tail -n 160 /home/egor/.local/state/orca/orca-debug.log
else
  echo NO_ORCA_DEBUG_LOG
fi

echo '===== SPEECH DISPATCHER FILES ====='
find /home/egor/.config/speech-dispatcher /home/egor/.cache/speech-dispatcher /home/egor/.local/state -maxdepth 3 -type f 2>/dev/null | head -80 || true

echo '===== RECENT SPEECH DISPATCHER LOGS ====='
for f in /home/egor/.cache/speech-dispatcher/log/* /home/egor/.local/state/speech-dispatcher/*; do
  [ -f "$f" ] || continue
  echo "--- $f ---"
  tail -n 80 "$f" || true
done

echo '===== PULSE ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep '[p]ulseaudio' || true
ss -xlpn 2>/dev/null | grep -E 'pulse|speech-dispatcher' || true
