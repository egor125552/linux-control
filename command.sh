#!/usr/bin/env bash
set -euo pipefail

export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
pe() { runuser -u egor -- env PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"; }

echo '===== TIME / LOAD ====='
date -Ins
uptime
cat /proc/loadavg

echo '===== LIVE AUDIO PROCESSES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,%cpu=,%mem=,comm=,args= | grep -E '[p]arec|[o]rca|[s]peech-dispatcher|[s]d_rhvoice|[p]acat' || true

echo '===== PULSE SHORT ====='
pe pactl list short sinks || true
pe pactl list short sources || true
pe pactl list short sink-inputs || true
pe pactl list short source-outputs || true

echo '===== XPRA SPEAKER EXACT ====='
pe pactl list sinks | sed -n '/Имя: Xpra-Speaker/,/Форматы:/p' || pe pactl list sinks | sed -n '/Name: Xpra-Speaker/,/Formats:/p' || true

echo '===== MONITOR EXACT ====='
pe pactl list sources | sed -n '/Имя: Xpra-Speaker.monitor/,/Форматы:/p' || pe pactl list sources | sed -n '/Name: Xpra-Speaker.monitor/,/Formats:/p' || true

echo '===== PULSE CONFIG RATE KEYS ====='
grep -RniE 'default-sample-rate|alternate-sample-rate|rate=|sample-rate|resample|fragment|latency' /etc/pulse /etc/xpra /home/egor/.config/pulse 2>/dev/null | head -n 220 || true

echo '===== AUDIO REMOTE SOCKETS ====='
pid=$(systemctl show audio-remote.service -p MainPID --value)
echo AUDIO_REMOTE_PID=$pid
ss -uapn 2>/dev/null | grep -E "pid=$pid|python" | head -n 120 || true
ss -tapn 2>/dev/null | grep -E "pid=$pid|:8765|python" | head -n 120 || true

echo '===== NETWORK COUNTERS ====='
ip -s link
for dev in $(ls /sys/class/net | grep -v '^lo$'); do
  echo DEV=$dev
  printf 'rx_dropped='; cat /sys/class/net/$dev/statistics/rx_dropped
  printf 'tx_dropped='; cat /sys/class/net/$dev/statistics/tx_dropped
  printf 'rx_errors='; cat /sys/class/net/$dev/statistics/rx_errors
  printf 'tx_errors='; cat /sys/class/net/$dev/statistics/tx_errors
done

echo '===== QDISC ====='
tc -s qdisc show 2>/dev/null || true

echo '===== CPU / STEAL 8 SECONDS ====='
for i in $(seq 1 8); do
  awk '/^cpu / {print strftime("%H:%M:%S"), $0}' /proc/stat
  sleep 1
done

echo '===== AUDIO SERVICE LOG ====='
journalctl -u audio-remote.service --since '-20 min' --no-pager -n 300 2>&1 || true

echo '===== DESKTOP AUDIO WARNINGS ====='
journalctl -u egor-desktop.service --since '-20 min' --no-pager 2>&1 | grep -Ei 'pulse|asyncq|overrun|underrun|drop|latenc|buffer|xrun' | tail -n 240 || true

echo DONE
