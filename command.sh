#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

ext=/home/egor/.local/share/orca/extensions/egor_desktop_accessibility/__init__.py
echo '===== FILE HASH ====='
sha256sum "$ext"

echo '===== LOADER SETTINGS SOURCE ====='
sed -n '100,185p' /opt/orca-51/lib/python3/dist-packages/orca/extension_loader.py
sed -n '325,390p' /opt/orca-51/lib/python3/dist-packages/orca/extension_loader.py

echo '===== ORCA GSETTINGS SCHEMAS ====='
grep -RniE 'approved-user-extensions|disabled-extensions' /opt/orca-51/share/glib-2.0/schemas /usr/share/glib-2.0/schemas 2>/dev/null | head -80 || true

echo '===== CURRENT EXTENSION SETTINGS ====='
sudo -u egor "${RUNENV[@]}" sh -c '
  for schema in $(gsettings list-schemas | grep -Ei "orca.*extension|orca"); do
    keys=$(gsettings list-keys "$schema" 2>/dev/null | grep -E "approved-user-extensions|disabled-extensions" || true)
    [ -z "$keys" ] && continue
    echo "SCHEMA=$schema"
    for k in $keys; do printf "%s=" "$k"; gsettings get "$schema" "$k"; done
  done
'

echo ORCA_APPROVAL_INSPECT_DONE=yes
