#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

echo '===== LIVE ORCA ====='
ps -u egor -o pid=,ppid=,stat=,comm=,etimes=,args= | grep '[o]rca' || true

echo '===== ORCA SELECTED ENV ====='
live=$(pgrep -u egor -x orca | while read p; do s=$(ps -o stat= -p "$p" | xargs); case "$s" in Z*) ;; *) echo "$p"; break;; esac; done)
[ -n "$live" ] || { echo LIVE_ORCA=no; exit 1; }
tr '\0' '\n' < /proc/$live/environ | grep -E '^(PATH|PYTHONPATH|GI_TYPELIB_PATH|GSETTINGS_SCHEMA_DIR|XDG_DATA_DIRS|DISPLAY|XDG_RUNTIME_DIR)=' || true

echo '===== USER SETTINGS EXTENSION REFERENCES ====='
grep -RniE 'egor_desktop_accessibility|extension|plugin' /home/egor/.local/share/orca/user-settings.conf /home/egor/.config/orca /home/egor/.local/share/orca 2>/dev/null | grep -v '__pycache__' | head -180 || true

echo '===== DEBUG FILE INFO ====='
stat -c 'size=%s mtime=%y' /home/egor/.local/state/orca/orca-debug.log 2>/dev/null || true
sed -n '1,180p' /home/egor/.local/state/orca/orca-debug.log 2>/dev/null | grep -Ei 'extension|plugin|egor|traceback|error|critical|starting|version' || true
tail -n 400 /home/egor/.local/state/orca/orca-debug.log 2>/dev/null | grep -Ei 'extension|plugin|egor|traceback|error|critical|focus manager' | tail -n 180 || true

echo '===== ORCA51 EXTENSION LOADER SOURCE REFERENCES ====='
grep -RniE 'user.*extension|extension.*user|extensions.*share|ExtensionManager|extension_manager' /opt/orca-51/lib/python3/dist-packages/orca 2>/dev/null | head -160 || true

echo ORCA_EXTENSION_REGISTRATION_CHECK_DONE=yes
