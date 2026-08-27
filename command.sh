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
echo '===== ACTIVE WINDOW ====='
if command -v xdotool >/dev/null 2>&1; then
  WID=$(runegor xdotool getactivewindow 2>/dev/null || true)
  echo "WINDOW_ID=${WID:-unknown}"
  if [ -n "${WID:-}" ]; then
    echo -n 'WINDOW_NAME='; runegor xdotool getwindowname "$WID" 2>/dev/null || true
    echo -n 'WINDOW_CLASS='; runegor xdotool getwindowclassname "$WID" 2>/dev/null || true
    echo -n 'WINDOW_PID='; runegor xdotool getwindowpid "$WID" 2>/dev/null || true
  fi
else
  echo 'xdotool=missing'
fi

echo '===== WMCTRL ACTIVE ====='
if command -v wmctrl >/dev/null 2>&1; then
  runegor wmctrl -lx 2>/dev/null | head -n 80 || true
else
  echo 'wmctrl=missing'
fi

echo '===== AT-SPI FOCUS ====='
runegor python3 - <<'PY' || true
import sys
try:
    import pyatspi
except Exception as e:
    print('PYATSPI_ERROR=', repr(e))
    sys.exit(0)

def focused_desc(acc, depth=0):
    try:
        st = acc.getState()
        focused = st.contains(pyatspi.STATE_FOCUSED)
    except Exception:
        focused = False
    if focused:
        try: role=acc.getRoleName()
        except Exception: role='?'
        try: name=acc.name
        except Exception: name='?'
        try: app=acc.getApplication().name if acc.getApplication() else '?'
        except Exception: app='?'
        print(f'FOCUSED_APP={app}')
        print(f'FOCUSED_ROLE={role}')
        print(f'FOCUSED_NAME={name}')
        return True
    try:
        n=acc.childCount
    except Exception:
        n=0
    for i in range(n):
        try:
            ch=acc.getChildAtIndex(i)
        except Exception:
            continue
        if focused_desc(ch, depth+1):
            return True
    return False

d=pyatspi.Registry.getDesktop(0)
found=False
for i in range(d.childCount):
    try: app=d.getChildAtIndex(i)
    except Exception: continue
    if focused_desc(app):
        found=True
        break
print('FOCUS_FOUND=' + ('yes' if found else 'no'))
PY

echo '===== ORCA RECENT FOCUS EVENTS ====='
LOG=/home/egor/.local/state/orca/orca-debug.log
if [ -f "$LOG" ]; then
  grep -Ei 'focus|active window|window:activate|object:state-changed:focused' "$LOG" | tail -n 40 || true
else
  echo 'orca log missing'
fi
