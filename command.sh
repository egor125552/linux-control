#!/usr/bin/env bash
set -euo pipefail
MATE_PID=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$MATE_PID" ] || { echo 'ERROR=no mate-session'; exit 1; }
DBUS=$(tr '\0' '\n' </proc/$MATE_PID/environ | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -1)
DISPLAY_VALUE=$(tr '\0' '\n' </proc/$MATE_PID/environ | sed -n 's/^DISPLAY=//p' | head -1)
XAUTH=$(tr '\0' '\n' </proc/$MATE_PID/environ | sed -n 's/^XAUTHORITY=//p' | head -1)
XDG=$(tr '\0' '\n' </proc/$MATE_PID/environ | sed -n 's/^XDG_RUNTIME_DIR=//p' | head -1)
: "${DISPLAY_VALUE:=:100}"; : "${XAUTH:=/home/egor/.Xauthority}"; : "${XDG:=/run/egor-desktop}"
runegor() {
  runuser -u egor -- env -u RUNNER_TRACKING_ID HOME=/home/egor USER=egor LOGNAME=egor DISPLAY="$DISPLAY_VALUE" XAUTHORITY="$XAUTH" XDG_RUNTIME_DIR="$XDG" DBUS_SESSION_BUS_ADDRESS="$DBUS" "$@"
}

echo '===== BEFORE ====='
runegor xprop -root _NET_ACTIVE_WINDOW _NET_CLIENT_LIST 2>&1 || true

# Clear any stale Caja popup/menu state, then request a real browser window.
runegor xdotool key Escape 2>/dev/null || true
runegor caja --no-desktop --browser /home/egor >/tmp/caja-focus.out 2>/tmp/caja-focus.err &

WIN=''
for _ in $(seq 1 100); do
  IDS=$(runegor xprop -root _NET_CLIENT_LIST 2>/dev/null | sed 's/^[^#]*# //' | tr ',' ' ' || true)
  for id in $IDS; do
    TYPE=$(runegor xprop -id "$id" _NET_WM_WINDOW_TYPE 2>/dev/null || true)
    CLASS=$(runegor xprop -id "$id" WM_CLASS 2>/dev/null || true)
    if echo "$TYPE" | grep -q '_NET_WM_WINDOW_TYPE_NORMAL' && echo "$CLASS" | grep -qi 'Caja'; then
      WIN=$id
    fi
  done
  [ -n "$WIN" ] && break
  sleep .1
done

echo "NORMAL_CAJA_WINDOW=${WIN:-missing}"
if [ -z "$WIN" ]; then
  cat /tmp/caja-focus.err 2>/dev/null || true
  exit 1
fi

runegor xdotool windowmap "$WIN" 2>/dev/null || true
runegor xdotool windowactivate --sync "$WIN"
runegor xdotool windowfocus --sync "$WIN" 2>/dev/null || true
sleep .8

echo '===== AFTER ====='
runegor xprop -root _NET_ACTIVE_WINDOW _NET_CLIENT_LIST _NET_CLIENT_LIST_STACKING 2>&1 || true
echo -n 'WINDOW_NAME='; runegor xdotool getwindowname "$WIN" 2>/dev/null || true
echo -n 'WINDOW_CLASS='; runegor xdotool getwindowclassname "$WIN" 2>/dev/null || true
runegor xprop -id "$WIN" _NET_WM_WINDOW_TYPE _NET_WM_STATE 2>/dev/null || true

echo '===== ORCA RECENT ====='
LOG=/home/egor/.local/state/orca/orca-debug.log
if [ -f "$LOG" ]; then
  grep -Ei 'Active window|Locus of focus|Changing locus|window:activate|state-changed:focused' "$LOG" | tail -n 60 || true
fi

echo FOCUS_REPAIR_DONE=yes
