#!/usr/bin/env bash
set -euo pipefail
export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
pe() { runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"; }

echo '===== SINK INPUTS FULL ====='
pe pactl list sink-inputs

echo '===== SOURCE OUTPUTS FULL ====='
pe pactl list source-outputs

echo '===== CLIENTS FULL ====='
pe pactl list clients

echo '===== SINK LATENCY SNAPSHOTS ====='
for i in $(seq 1 20); do
  printf '%s ' "$(date +%H:%M:%S.%3N)"
  pe pactl --format=json list sinks | python3 -c 'import json,sys; x=json.load(sys.stdin); s=next(v for v in x if v.get("name")=="Xpra-Speaker"); print("actual_us=%s configured_us=%s state=%s" % (s.get("latency",{}).get("actual"),s.get("latency",{}).get("configured"),s.get("state")))'
  sleep .25
done

echo '===== PROCESS PRIORITIES ====='
for p in $(pgrep -u egor -f 'pulseaudio|sd_rhvoice|speech-dispatcher|parec|audio_remote' || true); do
  ps -o pid=,ppid=,cls=,rtprio=,pri=,ni=,psr=,%cpu=,%mem=,stat=,comm=,args= -p "$p"
done

echo DONE
