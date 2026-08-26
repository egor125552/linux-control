#!/usr/bin/env bash
set -euo pipefail
BASE=/opt/orca-51/lib/python3/dist-packages/orca
sleep 8

echo '===== ORCA ====='
pid=$(pgrep -n -x orca || true)
[ -n "$pid" ] || { echo 'ERROR: Orca missing'; exit 2; }
ps -p "$pid" -o pid,ppid,user,%cpu,%mem,rss,vsz,nlwp,etime,cmd

echo '===== SPEECH ====='
pgrep -a -f 'speech-dispatcher|sd_rhvoice' || true

echo '===== SERVICES ====='
systemctl is-active egor-desktop.service
systemctl is-active audio-remote.service

echo '===== ORCA DEBUG TAIL ====='
tail -80 /home/egor/.local/state/orca/orca-debug.log 2>/dev/null || true

echo '===== ACTIVE OPTIMIZATION ====='
grep -nE 'app_hash|time.monotonic' "$BASE/event_manager.py" || true
