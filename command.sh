#!/usr/bin/env bash
set -euo pipefail
export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
pe() { runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"; }

cleanup() {
  set +e
  [ -n "${player:-}" ] && kill "$player" 2>/dev/null || true
  [ -n "${mod:-}" ] && pe pactl unload-module "$mod" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mod=$(pe pactl load-module module-null-sink sink_name=Diag-Sink 'sink_properties=device.description=Diag-Sink' rate=48000 channels=2)
echo DIAG_MODULE=$mod

echo '===== LATENCY MAPPING ====='
for lat in 10 20 40 80 160; do
  echo "--- client_latency_ms=$lat ---"
  pe pacat --playback --raw --device=Diag-Sink --format=s16le --rate=48000 --channels=1 --latency-msec="$lat" </dev/zero >/dev/null 2>/tmp/diag-pacat.err &
  player=$!
  sleep .6
  pe pacmd list-sink-inputs | awk '
    /sink: .*<Diag-Sink>/ {hit=1}
    hit && /current latency:|requested latency:|sample spec:|client:/ {print}
    hit && /^$/ {exit}
  '
  pe pacmd list-sinks | awk '
    /name: <Diag-Sink>/ {hit=1}
    hit && /current latency:|configured latency:/ {print}
    hit && /index:/ && seen {exit}
    hit {seen=1}
  '
  kill "$player" 2>/dev/null || true
  wait "$player" 2>/dev/null || true
  player=
  sleep .3
done

echo '===== REAL RHVOICE FOR COMPARISON ====='
pe pacmd list-sink-inputs | awk '
  /client: .*<RHVoice>/ {rh=1}
  rh && /current latency:|requested latency:|sample spec:|client:/ {print}
'
pe pacmd list-sinks | awk '
  /name: <Xpra-Speaker>/ {hit=1}
  hit && /current latency:|configured latency:/ {print}
  hit && /index:/ && seen {exit}
  hit {seen=1}
'

echo DONE
