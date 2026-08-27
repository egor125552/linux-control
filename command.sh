#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

echo '===== CUSTOMIZATIONS ====='
sed -n '1,360p' /home/egor/.local/share/orca/orca-customizations.py 2>/dev/null || true

echo '===== ORCA 51 FOCUS / OBJECT NAVIGATOR SOURCES ====='
for base in /opt/orca-51/lib/python3/dist-packages/orca /opt/orca-51/share/orca /usr/lib/python3/dist-packages/orca; do
  [ -d "$base" ] || continue
  echo "--- $base"
  grep -RniE 'object.navigator|focus.*manager|locusOfFocus|activeWindow|presentObject|present.*object|flat.review|focused' "$base" 2>/dev/null | head -220 || true
done

echo '===== CURRENT FOCUSED AT-SPI OBJECTS ====='
sudo -u egor "${RUNENV[@]}" python3 - <<'PY'
import pyatspi
D=pyatspi.Registry.getDesktop(0)
for ai in range(D.childCount):
    try:
        app=D.getChildAtIndex(ai)
        an=(app.name or '').strip()
        stack=[app]; seen=0
        while stack and seen<1500:
            o=stack.pop(); seen+=1
            try:
                ss=o.getState()
                if ss.contains(pyatspi.STATE_FOCUSED):
                    print('FOCUSED',repr((an,o.getRoleName(),o.name,o.childCount)))
            except Exception: pass
            try:
                for i in range(min(o.childCount,120)-1,-1,-1): stack.append(o.getChildAtIndex(i))
            except Exception: pass
    except Exception as e: print('APPERR',repr(e))
PY

echo '===== RECENT ORCA DEBUG FOCUS LINES ====='
for f in /home/egor/.local/state/orca/orca-debug.log /home/egor/.local/state/orca/orca-launcher.log; do
  [ -f "$f" ] || continue
  echo "--- $f"
  grep -Ei 'focus|locus|empty|пуст|active window|object' "$f" | tail -220 || true
done

echo ORCA_FOCUS_INSPECT_DONE=yes
