#!/usr/bin/env bash
set -euo pipefail

echo '===== RHVOICE PACKAGE SOURCE ====='
apt-cache show speech-dispatcher-rhvoice 2>/dev/null | grep -E '^(Package|Source|Version|Depends):' | head -n 80 || true

echo '===== RHVOICE LDD ====='
ldd /usr/lib/speech-dispatcher-modules/sd_rhvoice || true

echo '===== RELATED LIBRARIES ====='
find /usr/lib /lib -type f \( -iname '*speechd*' -o -iname '*spd*pulse*' -o -iname '*rhvoice*' \) 2>/dev/null | sort | head -n 500

echo '===== STRINGS IN LINKED / AUDIO LIBS ====='
for f in $(ldd /usr/lib/speech-dispatcher-modules/sd_rhvoice 2>/dev/null | awk '/=> \//{print $3}') /usr/lib/x86_64-linux-gnu/speech-dispatcher/spd_pulse.so; do
  [ -f "$f" ] || continue
  echo "--- $f ---"
  strings "$f" | grep -Ei 'audio_pulse|min_length|tlength|fragsize|buffer_attr|latency|pa_stream|pulse' | head -n 240 || true
done

echo '===== EXPORTED SYMBOLS PULSE ====='
nm -D /usr/lib/x86_64-linux-gnu/speech-dispatcher/spd_pulse.so 2>/dev/null | grep -Ei 'pulse|audio|open|play|stop|close' | head -n 300 || true

echo '===== EXPORTED SYMBOLS RHVOICE ====='
nm -D /usr/lib/speech-dispatcher-modules/sd_rhvoice 2>/dev/null | head -n 300 || true

echo '===== APT SOURCE AVAILABILITY ====='
apt-cache showsrc speech-dispatcher 2>&1 | head -n 100 || true
apt-cache showsrc rhvoice 2>&1 | head -n 100 || true

echo DONE
