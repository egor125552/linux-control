#!/usr/bin/env bash
set -euo pipefail

old=$(systemctl show audio-remote.service -p MainPID --value)
echo "OLD_AUDIO_REMOTE_PID=$old"

echo '===== RESTART AUDIO REMOTE ONLY ====='
systemctl restart audio-remote.service
sleep 2
systemctl is-active audio-remote.service
new=$(systemctl show audio-remote.service -p MainPID --value)
echo "NEW_AUDIO_REMOTE_PID=$new"
[ -n "$new" ] && [ "$new" != 0 ] && [ "$new" != "$old" ]

echo '===== VERIFY PATCH LOADED ON DISK ====='
grep -nE 'prebuffer_ms|next_send_time|silence_frames|dropped_frames|capture_latency_ms' /opt/audio-remote/audio_remote/audio.py
/opt/audio-remote/.venv/bin/python -m py_compile /opt/audio-remote/audio_remote/audio.py

echo '===== SERVICE LOG AFTER RESTART ====='
journalctl -u audio-remote.service --since '-3 min' --no-pager -n 160 2>&1 || true

echo '===== ACCESSIBILITY STACK UNTOUCHED ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -E '[o]rca|[s]peech-dispatcher|[s]d_rhvoice' || true
orca=$(pgrep -u egor -x orca | while read -r p; do st=$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true); [ "$st" != Z ] && echo "$p"; done | tail -1)
spd=$(pgrep -u egor -f '(^|/)speech-dispatcher([[:space:]]|$)' | head -1 || true)
rhv=$(pgrep -u egor -x sd_rhvoice | head -1 || true)
[ -n "$orca" ] && [ -n "$spd" ] && [ -n "$rhv" ]
echo "ORCA=$orca SPEECH=$spd RHVOICE=$rhv"

echo AUDIO_REMOTE_PACING_LIVE=yes
