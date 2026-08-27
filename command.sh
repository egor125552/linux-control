#!/usr/bin/env bash
set -euo pipefail
MATE_PID=$(pgrep -u egor -x mate-session | head -1 || true)
if [ -z "$MATE_PID" ]; then echo 'ERROR=no mate-session'; exit 1; fi
DBUS=$(tr '\0' '\n' </proc/$MATE_PID/environ | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -1)
DISPLAY_VALUE=$(tr '\0' '\n' </proc/$MATE_PID/environ | sed -n 's/^DISPLAY=//p' | head -1)
XAUTH=$(tr '\0' '\n' </proc/$MATE_PID/environ | sed -n 's/^XAUTHORITY=//p' | head -1)
XDG=$(tr '\0' '\n' </proc/$MATE_PID/environ | sed -n 's/^XDG_RUNTIME_DIR=//p' | head -1)
: "${DISPLAY_VALUE:=:100}"
: "${XAUTH:=/home/egor/.Xauthority}"
: "${XDG:=/run/egor-desktop}"
runegor() {
  runuser -u egor -- env HOME=/home/egor USER=egor LOGNAME=egor DISPLAY="$DISPLAY_VALUE" XAUTHORITY="$XAUTH" XDG_RUNTIME_DIR="$XDG" DBUS_SESSION_BUS_ADDRESS="$DBUS" "$@"
}

echo '===== CORE PROCESSES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -E '[m]arco|[m]ate-panel|[c]aja|[o]rca|[x]pra' || true

echo '===== ROOT WINDOW FOCUS PROPERTIES ====='
runegor xprop -root _NET_ACTIVE_WINDOW _NET_CLIENT_LIST _NET_CLIENT_LIST_STACKING 2>&1 || true

echo '===== X INPUT FOCUS ====='
runegor xdotool getwindowfocus 2>&1 || true
runegor xdotool getactivewindow 2>&1 || true

echo '===== CLIENT WINDOWS ====='
IDS=$(runegor xprop -root _NET_CLIENT_LIST_STACKING 2>/dev/null | sed 's/^[^#]*# //' | tr ',' ' ' || true)
for id in $IDS; do
  [ -n "$id" ] || continue
  echo "--- $id ---"
  runegor xprop -id "$id" _NET_WM_NAME WM_NAME WM_CLASS _NET_WM_PID _NET_WM_WINDOW_TYPE _NET_WM_STATE _NET_WM_DESKTOP 2>/dev/null || true
done

echo '===== VISIBLE WINDOWS XDOTOOL ====='
runegor xdotool search --onlyvisible --name '.*' 2>/dev/null | while read -r id; do
  printf '%s ' "$id"
  runegor xdotool getwindowname "$id" 2>/dev/null || true
done | tail -n 80 || true

echo '===== XWININFO TOP TREE ====='
runegor xwininfo -root -tree 2>/dev/null | head -n 160 || true

echo '===== MARCO SETTINGS ====='
runegor gsettings get org.mate.Marco.general focus-mode 2>/dev/null || true
runegor gsettings get org.mate.Marco.general auto-raise 2>/dev/null || true

echo '===== XINPUT ====='
runegor xinput --list --short 2>/dev/null | head -n 80 || true

echo '===== ORCA LAST KEY/FOCUS EVENTS ====='
LOG=/home/egor/.local/state/orca/orca-debug.log
if [ -f "$LOG" ]; then
  grep -Ei 'KEYBOARD|key event|focus manager|locus of focus|active window|window:activate|state-changed:focused' "$LOG" | tail -n 140 || true
fi
