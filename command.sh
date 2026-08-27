#!/usr/bin/env bash
set -euo pipefail
export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'

echo '===== PACMD SINK INPUT DETAIL ====='
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pacmd list-sink-inputs 2>&1 || true

echo '===== PACMD SINK DETAIL ====='
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pacmd list-sinks 2>&1 | sed -n '/name: <Xpra-Speaker>/,/index:/p' || true

echo '===== RHVOICE PACKAGE / LIBRARIES ====='
bin=/usr/lib/speech-dispatcher-modules/sd_rhvoice
dpkg -S "$bin" 2>/dev/null || true
pkg=$(dpkg -S "$bin" 2>/dev/null | head -1 | cut -d: -f1 || true)
[ -n "$pkg" ] && dpkg -L "$pkg" | head -n 260 || true
ldd "$bin" 2>/dev/null | grep -Ei 'pulse|audio|speech|rhvoice|snd|asound' || true

echo '===== RHVOICE BINARY PULSE STRINGS ====='
strings "$bin" 2>/dev/null | grep -Ei 'pulse|latenc|buffer|pa_simple|pa_stream|audio|fragment|tlength|minreq|prebuf' | head -n 260 || true

echo '===== SPEECH DISPATCHER AUDIO LIBS ====='
ldd /usr/bin/speech-dispatcher 2>/dev/null | grep -Ei 'pulse|audio|snd|asound' || true
find /usr/lib -type f \( -name '*speechd*' -o -name '*spd_audio*' \) 2>/dev/null | head -n 180

echo '===== CONFIG AUDIO SETTINGS ====='
grep -RnsEi --binary-files=without-match 'AudioOutputMethod|Pulse|latency|buffer|fragment|period|playback' /etc/speech-dispatcher /home/egor/.config/speech-dispatcher 2>/dev/null | head -n 320 || true

echo DONE
