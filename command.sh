#!/usr/bin/env bash
set -euo pipefail

echo '===== /etc/pulse/daemon.conf ACTIVE LINES ====='
nl -ba /etc/pulse/daemon.conf | grep -Ev '^[[:space:]]*[0-9]+[[:space:]]+[;#]?[[:space:]]*$' | grep -E 'default-sample-rate|alternate-sample-rate|default-sample-format|resample-method|avoid-resampling|default-fragments|default-fragment-size-msec|realtime|high-priority' || true

echo '===== EXACT BAD RATE SEARCH IN PULSE CONFIG ====='
grep -RnsE --binary-files=without-match '(^|[^0-9])(4800|4410|2400)([^0-9]|$)|default-sample-rate|alternate-sample-rate' /etc/pulse /home/egor/.config/pulse 2>/dev/null || true

echo '===== PULSEAUDIO DUMP CONF AS EGOR ====='
runuser -u egor -- pulseaudio --dump-conf 2>&1 | grep -E 'default-sample-rate|alternate-sample-rate|default-sample-format|resample-method|avoid-resampling|default-fragments|default-fragment-size-msec|realtime|high-priority' || true

echo '===== LIVE SERVER/SINK RATE ====='
export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
runuser -u egor -- env PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list short sinks
runuser -u egor -- env PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list short sources

echo '===== SPEECH DISPATCHER RATE CONFIG ====='
grep -RnsEi --binary-files=without-match '2400|24000|sample.*rate|rate|frequency' /etc/speech-dispatcher /home/egor/.config/speech-dispatcher /etc/RHVoice /home/egor/.config/RHVoice 2>/dev/null | head -n 260 || true

echo '===== RECENT OVERRUN COUNT ====='
c=$(journalctl -u egor-desktop.service --since today --no-pager 2>/dev/null | grep -c 'asyncq.c: q overrun' || true)
echo ASYNCQ_OVERRUNS_TODAY=$c
journalctl -u egor-desktop.service --since today --no-pager 2>/dev/null | grep 'asyncq.c: q overrun' | tail -n 30 || true

echo DONE
