#!/usr/bin/env bash
set -euo pipefail
pulse_pid=$(pgrep -u egor -x pulseaudio | head -1 || true)
echo "PULSE_PID=${pulse_pid:-none}"
[ -n "$pulse_pid" ] || { echo NO_PULSEAUDIO; exit 0; }

echo '===== PROCESS ====='
ps -o pid=,ppid=,stat=,etimes=,wchan=,comm=,args= -p "$pulse_pid" || true

echo '===== SOCKET PATH ====='
ls -la /run/egor-desktop/xpra/100/pulse 2>/dev/null || true
stat /run/egor-desktop/xpra/100/pulse/native 2>/dev/null || true

echo '===== UNIX LISTENERS ====='
ss -xlpn 2>/dev/null | grep -E 'pulse|xpra/100' || true

echo '===== PULSE FDS ====='
ls -l "/proc/$pulse_pid/fd" 2>/dev/null | head -120 || true

echo '===== PULSE UNIX FDS ====='
for fd in /proc/$pulse_pid/fd/*; do
  target=$(readlink "$fd" 2>/dev/null || true)
  case "$target" in socket:*) echo "$(basename "$fd") $target";; esac
done

echo '===== PULSE STATUS ====='
cat "/proc/$pulse_pid/status" 2>/dev/null | grep -E '^(State|Threads|FDSize|VmRSS|voluntary_ctxt_switches|nonvoluntary_ctxt_switches)' || true

echo '===== XPRA PULSE LOG REFERENCES ====='
journalctl -u egor-desktop.service -b --no-pager 2>/dev/null | grep -Ei 'pulseaudio|pulse|sound' | tail -180 || true

echo '===== XPRA PROCESS TREE ====='
pstree -aps "$pulse_pid" 2>/dev/null || true

echo PULSE_SOCKET_INSPECT_DONE=yes
