#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

echo '===== HASH IMPLEMENTATION ====='
grep -n 'def _compute_hash' /opt/orca-51/lib/python3/dist-packages/orca/extension_loader.py || true
line=$(grep -n 'def _compute_hash' /opt/orca-51/lib/python3/dist-packages/orca/extension_loader.py | head -1 | cut -d: -f1 || true)
if [ -n "$line" ]; then sed -n "${line},$((line+90))p" /opt/orca-51/lib/python3/dist-packages/orca/extension_loader.py; fi

echo '===== ORCA-NATIVE DISCOVERY ====='
sudo -u egor "${RUNENV[@]}" bash -c '
  export PYTHONPATH="/opt/orca-51/lib/python3/dist-packages${PYTHONPATH:+:$PYTHONPATH}"
  export GI_TYPELIB_PATH="/opt/orca-51/lib/x86_64-linux-gnu/girepository-1.0${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
  export LD_LIBRARY_PATH="/opt/orca-51/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export GSETTINGS_SCHEMA_DIR=/opt/orca-51/share/glib-2.0/schemas
  python3 - <<"PY"
from orca.extension_loader import ExtensionLoader
root="/home/egor/.local/share/orca/extensions"
loader=ExtensionLoader()
infos=loader.discover_user_extensions(root)
print("DISCOVER_COUNT=",len(infos))
for x in infos:
    print("INFO", x.filename, x.filepath, x.class_name, x.file_hash, x.approved_hash, x.status.name)
PY
'

echo ORCA_NATIVE_HASH_CHECK_DONE=yes
