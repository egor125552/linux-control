#!/usr/bin/env bash
set -euo pipefail

echo '===== SERVICES ====='
systemctl --no-pager --full status egor-desktop.service audio-remote.service 2>&1 | tail -n 160 || true

echo '===== SERVICE FILES ====='
systemctl cat egor-desktop.service audio-remote.service 2>&1 || true

echo '===== AUDIO PROCESSES ====='
ps -eo pid,ppid,stat,ni,pri,pcpu,pmem,etimes,comm,args | grep -Ei '[p]ulse|[x]pra|[a]udio-remote|[f]fmpeg|[g]streamer|[s]peech-dispatch|[s]d_rhvoice' || true

echo '===== PULSE INFO ====='
PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native' PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE' runuser -u egor -- env PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native' PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE' pactl info 2>&1 || true

echo '===== PULSE SINKS ====='
runuser -u egor -- env PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native' PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE' pactl list sinks 2>&1 || true

echo '===== PULSE SINK INPUTS ====='
runuser -u egor -- env PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native' PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE' pactl list sink-inputs 2>&1 || true

echo '===== AUDIO REMOTE JOURNAL ====='
journalctl -u audio-remote.service --since '-15 min' --no-pager -n 300 2>&1 || true

echo '===== EGOR DESKTOP JOURNAL AUDIO ====='
journalctl -u egor-desktop.service --since '-15 min' --no-pager -n 300 2>&1 | grep -Ei 'pulse|audio|sound|xpra|underrun|overrun|drop|buffer|latenc|error|warn' || true

echo '===== SOCKETS ====='
ss -tunap 2>/dev/null | grep -Ei 'xpra|audio|ffmpeg|pulse|:100|:145|:800|:900' || true

echo '===== LOAD ====='
uptime
vmstat 1 3

echo '===== KERNEL NET ====='
ip -s link 2>/dev/null || true

echo DONE
