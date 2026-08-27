#!/usr/bin/env bash
set -euo pipefail

echo '===== VERSION ====='
speech-dispatcher --version 2>&1 || true
dpkg-query -W -f='${Package} ${Version}\n' speech-dispatcher speech-dispatcher-audio-plugins speech-dispatcher-rhvoice 2>/dev/null || true

echo '===== CONFIG REFERENCES ====='
grep -RnsEi 'AudioPulseMinLength|PulseMin|MinLength|Pulse.*Length|AudioOutputMethod|pulse' \
  /etc/speech-dispatcher /usr/share/doc/speech-dispatcher* /usr/share/speech-dispatcher 2>/dev/null | head -n 500 || true

echo '===== SYSTEM SPEECHD CONF RELEVANT ====='
grep -nEi -C 8 'AudioPulse|AudioOutput|pulse' /etc/speech-dispatcher/speechd.conf 2>/dev/null | head -n 300 || true

echo '===== USER CONF ====='
nl -ba /home/egor/.config/speech-dispatcher/speechd.conf

echo '===== RHVOICE MODULE CONF ====='
nl -ba /etc/speech-dispatcher/modules/rhvoice.conf

echo '===== MODULE BINARY STRINGS ====='
for f in /usr/lib/speech-dispatcher-modules/sd_rhvoice /usr/lib/x86_64-linux-gnu/libspeechd_module.so* /usr/lib/speech-dispatcher-modules/*; do
  [ -f "$f" ] || continue
  echo "--- $f ---"
  strings "$f" 2>/dev/null | grep -Ei 'AudioPulse|PulseMin|MinLength|pa_buffer|tlength|fragsize|latency|pulse' | head -n 160 || true
done

echo '===== PACKAGE FILES ====='
dpkg -L speech-dispatcher 2>/dev/null | grep -E 'conf|module|doc|example' | head -n 300 || true
dpkg -L speech-dispatcher-audio-plugins 2>/dev/null | head -n 300 || true

echo '===== MAN / HELP ====='
MANWIDTH=120 man speech-dispatcher 2>/dev/null | col -b | grep -nEi -C 5 'pulse|latency|audio' | head -n 240 || true
spd-conf --help 2>&1 | head -n 200 || true

echo '===== LIVE RHVOICE ENV ====='
for p in $(pgrep -u egor -x sd_rhvoice || true); do
  echo "PID=$p"
  tr '\0' '\n' </proc/$p/environ | sort | grep -E 'PULSE|SPD|SPEECH|HOME|XDG|DISPLAY' || true
done

echo DONE
