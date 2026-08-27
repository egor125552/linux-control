#!/usr/bin/env bash
set -euo pipefail
export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
pe() { runuser -u egor -- env PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"; }

echo '===== PULSE MODULES ====='
pe pactl list modules | sed -n '1,520p'

echo '===== PULSE PROCESS ====='
pgrep -a -u egor pulseaudio || true
for p in $(pgrep -u egor pulseaudio || true); do
  echo PID=$p
  tr '\0' ' ' </proc/$p/cmdline; echo
  echo ENV_RATE_KEYS
  tr '\0' '\n' </proc/$p/environ 2>/dev/null | grep -Ei 'pulse|rate|xpra|audio|sound' | sort || true
done

echo '===== XPRA PROCESS ====='
pgrep -a -u egor -f 'xpra' | head -n 80 || true

echo '===== RUNTIME PULSE TREE ====='
find /run/egor-desktop/xpra/100 -maxdepth 5 -type f -print 2>/dev/null | sort | head -n 260
for f in $(find /run/egor-desktop/xpra/100 -maxdepth 5 -type f \( -name '*.pa' -o -name '*.conf' -o -name '*.log' \) 2>/dev/null | sort); do
  echo "--- $f ---"
  grep -nEi 'null-sink|Xpra-Speaker|Xpra-Microphone|rate|sample|pulse|audio|sound' "$f" 2>/dev/null | tail -n 220 || true
done

echo '===== SYSTEM XPRA AUDIO CONFIG ====='
for root in /etc/xpra /usr/share/xpra /usr/lib/python3/dist-packages/xpra; do
  echo ROOT=$root
  grep -RniE --exclude='*.pyc' '4800|4410|2400|Xpra-Speaker|Xpra-Microphone|null-sink|sample-rate|pulseaudio-command|pulse.*rate' "$root" 2>/dev/null | head -n 360 || true
done

echo '===== DESKTOP SERVICE ====='
systemctl cat egor-desktop.service
systemctl show egor-desktop.service -p Environment -p ExecStart -p FragmentPath --no-pager

echo '===== LAUNCHER / SCRIPTS ====='
grep -RniE 'xpra|pulse|sound|audio|4800|4410|2400|48000|44100|24000' /usr/local/bin /opt 2>/dev/null | head -n 500 || true

echo DONE
