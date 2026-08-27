#!/usr/bin/env bash
set -euo pipefail
PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
pe() { runuser -u egor -- env HOME=/home/egor XDG_RUNTIME_DIR=/run/egor-desktop LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"; }

echo '===== CONFIG ====='
nl -ba /home/egor/.config/speech-dispatcher/speechd.conf

echo '===== STACK ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,%cpu=,comm=,args= | grep -E '[o]rca|[s]peech-dispatch|[s]d_rhvoice' || true

echo '===== PULSE INFO ====='
pe pactl info

echo '===== RHVOICE SINK INPUT FULL ====='
pe pactl list sink-inputs | awk 'BEGIN{RS="Sink Input #"} /application.name = "RHVoice"/{print "Sink Input #" $0}'

echo '===== XPRA SPEAKER FULL ====='
pe pactl list sinks | awk 'BEGIN{RS="Sink #"} /Name: Xpra-Speaker/{print "Sink #" $0}'

echo '===== JSON RHVOICE ====='
pe pactl -f json list sink-inputs || true

echo DONE
