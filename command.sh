#!/usr/bin/env bash
set -euo pipefail

live=$(pgrep -u egor -x orca | while read -r p; do st=$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true); [ "$st" != Z ] && echo "$p"; done | tail -1)
[ -n "$live" ] || { echo NO_LIVE_ORCA; exit 1; }

echo "LIVE_ORCA_PID=$live"

envfile="/proc/$live/environ"
pserver=$(tr '\0' '\n' < "$envfile" | sed -n 's/^PULSE_SERVER=//p' | tail -1)
pcookie=$(tr '\0' '\n' < "$envfile" | sed -n 's/^PULSE_COOKIE=//p' | tail -1)
xruntime=$(tr '\0' '\n' < "$envfile" | sed -n 's/^XDG_RUNTIME_DIR=//p' | tail -1)

echo "PULSE_SERVER=${pserver:-<missing>}"
if [ -n "$pcookie" ]; then
  echo PULSE_COOKIE_SET=yes
  if [ -r "$pcookie" ]; then
    echo PULSE_COOKIE_READABLE=yes
    stat -c 'PULSE_COOKIE_SIZE=%s' "$pcookie" || true
  else
    echo PULSE_COOKIE_READABLE=no
  fi
else
  echo PULSE_COOKIE_SET=no
fi
echo "XDG_RUNTIME_DIR=${xruntime:-<missing>}"

echo '===== PACTL TEST AS EGOR ====='
if command -v pactl >/dev/null 2>&1; then
  runuser -u egor -- env HOME=/home/egor XDG_RUNTIME_DIR="${xruntime:-/run/user/$(id -u egor)}" PULSE_SERVER="$pserver" PULSE_COOKIE="$pcookie" pactl info || true
  echo '===== SINKS ====='
  runuser -u egor -- env HOME=/home/egor XDG_RUNTIME_DIR="${xruntime:-/run/user/$(id -u egor)}" PULSE_SERVER="$pserver" PULSE_COOKIE="$pcookie" pactl list short sinks || true
else
  echo NO_PACTL
fi
