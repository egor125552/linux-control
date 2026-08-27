#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

echo '===== ORCA PROCESSES ====='
pgrep -a -u egor -x orca || true
pgrep -a -u egor -f '/opt/orca-51/bin/orca' || true

echo '===== STARTUP LOG ====='
tail -n 120 /home/egor/.local/state/orca/manual-restart.log 2>/dev/null || true

echo '===== EXTENSION RUNTIME MARKERS ====='
grep -E 'EGOR ACCESSIBILITY: VoiceOver-like|Virtual cursor|Traceback|CRITICAL|ERROR' /home/egor/.local/state/orca/orca-debug.log 2>/dev/null | tail -n 100 || true

echo '===== AT-SPI RUNTIME API ====='
sudo -u egor "${RUNENV[@]}" python3 - <<'PY'
import gi
gi.require_version('Atspi','2.0')
from gi.repository import Atspi
try:
    d=Atspi.get_desktop(0)
    print('ATSPI_GET_DESKTOP_OK=yes')
    print('DESKTOP_CHILDREN=',d.get_child_count())
    for i in range(min(d.get_child_count(),20)):
        a=d.get_child_at_index(i)
        try: print('APP',i,repr(a.get_name()),'children=',a.get_child_count())
        except Exception as e: print('APPERR',i,repr(e))
except Exception as e:
    print('ATSPI_GET_DESKTOP_OK=no')
    print('ATSPI_ERROR=',repr(e))
PY

echo '===== RECENT ORCA ERRORS ====='
tail -n 240 /home/egor/.local/state/orca/orca-debug.log 2>/dev/null | grep -Ei 'traceback|exception|error|critical|egor accessibility' | tail -n 120 || true

echo ORCA_VIRTUAL_CURSOR_RUNTIME_CHECK_DONE=yes
