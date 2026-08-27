#!/usr/bin/env bash
set -euo pipefail
export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
pe() { runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"; }

echo '===== CONFIG ====='
grep -nE 'AudioPulseMinLength|AudioOutputMethod' /home/egor/.config/speech-dispatcher/speechd.conf /etc/speech-dispatcher/speechd.conf 2>/dev/null | head -n 80 || true

echo '===== RHVOICE LATENCY ====='
pe pacmd list-sink-inputs | awk '
  /client: .*<RHVoice>/ {rh=1}
  rh && /sample spec:|current latency:|requested latency:|client:/ {print}
  rh && /^$/ {exit}
'

echo '===== XPRA SPEAKER LATENCY ====='
pe pacmd list-sinks | awk '
  /name: <Xpra-Speaker>/ {hit=1}
  hit && /sample spec:|current latency:|configured latency:|state:/ {print}
  hit && /index:/ && seen {exit}
  hit {seen=1}
'

echo '===== OVERRUNS ====='
total=$(journalctl -u egor-desktop.service --since today --no-pager 2>/dev/null | grep -c 'asyncq.c: q overrun' || true)
echo OVERRUNS_TODAY=$total
journalctl -u egor-desktop.service --since '-30 min' --no-pager 2>/dev/null | grep 'asyncq.c: q overrun' | tail -n 40 || true

echo '===== NETWORK LOSS ====='
for dev in $(ls /sys/class/net | grep -v '^lo$'); do
  printf '%s rx_drop=' "$dev"; cat /sys/class/net/$dev/statistics/rx_dropped
  printf '%s tx_drop=' "$dev"; cat /sys/class/net/$dev/statistics/tx_dropped
  printf '%s rx_err=' "$dev"; cat /sys/class/net/$dev/statistics/rx_errors
  printf '%s tx_err=' "$dev"; cat /sys/class/net/$dev/statistics/tx_errors
done

echo '===== LIVE ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,%cpu=,comm=,args= | grep -E '[o]rca|[s]peech-dispatch|[s]d_rhvoice|[p]arec' || true

echo DONE
