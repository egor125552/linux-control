#!/usr/bin/env bash
set -euo pipefail

echo '===== CURRENT ORCA ENV RELEVANT ====='
live=$(pgrep -u egor -x orca | while read -r p; do st=$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true); [ "$st" != Z ] && echo "$p"; done | tail -1)
echo "LIVE=$live"
tr '\0' '\n' < "/proc/$live/environ" | grep -E '^(DISPLAY|DBUS_SESSION_BUS_ADDRESS|XAUTHORITY|XDG_RUNTIME_DIR|XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|DESKTOP_SESSION|AT_SPI_BUS_ADDRESS|PULSE_SERVER|PULSE_COOKIE|RUNNER_TRACKING_ID|HOME|USER|LOGNAME|PATH)=' || true

echo '===== EGOR MATE SESSION ====='
sed -n '1,120p' /usr/local/bin/egor-mate-session

echo '===== PARENT ENV RELEVANT ====='
for p in 92483 92481; do
  [ -r "/proc/$p/environ" ] || continue
  echo "PID=$p"
  tr '\0' '\n' < "/proc/$p/environ" | grep -E '^(DISPLAY|DBUS_SESSION_BUS_ADDRESS|XAUTHORITY|XDG_RUNTIME_DIR|AT_SPI_BUS_ADDRESS|PULSE_SERVER|PULSE_COOKIE|RUNNER_TRACKING_ID|HOME|USER|LOGNAME|PATH)=' || true
done
