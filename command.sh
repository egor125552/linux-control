#!/usr/bin/env bash
set -euo pipefail
PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
pulse() { runuser -u egor -- env HOME=/home/egor XDG_RUNTIME_DIR=/run/egor-desktop LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"; }
live_orca() { pgrep -u egor -x orca | while read -r p; do [ "$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)" != Z ] && echo "$p"; done; }

echo '===== PERSISTED LAUNCHER ====='
grep -n -C 2 '^export PULSE_LATENCY_MSEC=40$' /usr/local/bin/orca-egor-launcher
bash -n /usr/local/bin/orca-egor-launcher

echo '===== LIVE STACK AFTER PRIOR RUNNER CLEANUP ====='
ORCA=$(live_orca | tail -1)
SPD=$(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' | head -1 || true)
RHV=$(pgrep -u egor -x sd_rhvoice | head -1 || true)
[ -n "$ORCA" ] && [ -n "$SPD" ] && [ -n "$RHV" ]
echo "ORCA=$ORCA SPEECHD=$SPD RHVOICE=$RHV"
ps -u egor -o pid=,ppid=,stat=,etimes=,%cpu=,comm=,args= | grep -E '[o]rca|[s]peech-dispatch|[s]d_rhvoice' || true

echo '===== RHVOICE ENV ====='
tr '\0' '\n' </proc/$RHV/environ | grep '^PULSE_LATENCY_MSEC=40$'

echo '===== LIVE PULSE ====='
INPUTS=$(pulse pactl list sink-inputs)
SINKS=$(pulse pactl list sinks)
printf '%s\n' "$INPUTS" | grep -q 'application.name = "RHVoice"'
CONFIGURED=$(printf '%s\n' "$SINKS" | awk 'BEGIN{RS="Sink #"} /Name: Xpra-Speaker/{if(match($0,/configured [0-9]+ usec/)){x=substr($0,RSTART,RLENGTH);gsub(/[^0-9]/,"",x);print x;exit}}')
BUFFER=$(printf '%s\n' "$INPUTS" | awk 'BEGIN{RS="Sink Input #"} /application.name = "RHVoice"/{if(match($0,/Buffer Latency: [0-9]+ usec/)){x=substr($0,RSTART,RLENGTH);gsub(/[^0-9]/,"",x);print x;exit}}')
echo "XPRA_CONFIGURED_USEC=$CONFIGURED"
echo "RHVOICE_BUFFER_USEC=$BUFFER"
[ "$CONFIGURED" -ge 8000 ]

echo '===== FINAL AUDIBLE CHECK ====='
MARK=$(date '+%Y-%m-%d %H:%M:%S')
pulse timeout 10 spd-say -w 'Звук исправлен и проверен.'
sleep 1
OVERRUNS=$(journalctl -u egor-desktop.service --since "$MARK" --no-pager 2>/dev/null | grep -c 'asyncq.c: q overrun' || true)
echo "OVERRUNS_FINAL_CHECK=$OVERRUNS"
[ "$OVERRUNS" -eq 0 ]

echo PERSISTENCE_VERIFIED=yes
