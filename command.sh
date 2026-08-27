#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

echo '===== DIRECT LOADER TEST ====='
sudo -u egor "${RUNENV[@]}" bash -c '
  export PYTHONPATH="/opt/orca-51/lib/python3/dist-packages${PYTHONPATH:+:$PYTHONPATH}"
  export GI_TYPELIB_PATH="/opt/orca-51/lib/x86_64-linux-gnu/girepository-1.0${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
  export LD_LIBRARY_PATH="/opt/orca-51/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export GSETTINGS_SCHEMA_DIR=/opt/orca-51/share/glib-2.0/schemas
  python3 - <<"PY"
import traceback
from orca.extension_loader import ExtensionLoader
root="/home/egor/.local/share/orca/extensions"
loader=ExtensionLoader()
try:
    x=loader._load_user_extension_source(root,"egor_desktop_accessibility")
    print("LOAD_RESULT=",x)
    if x is not None:
        print("CLASS=",type(x).__name__)
        print("MODULE_NAME=",x.module_name)
        print("VERSION=",getattr(x,"VERSION",None))
except Exception as e:
    print("LOAD_EXCEPTION=",repr(e))
    traceback.print_exc()
PY
'

echo '===== DISCOVER_AND_LOAD CALL SITES ====='
grep -Rni 'discover_and_load' /opt/orca-51/bin/orca /opt/orca-51/lib/python3/dist-packages/orca 2>/dev/null | head -80 || true

echo '===== USER DATA DIR REFERENCES ====='
grep -RniE 'user_data_dir|XDG_DATA_HOME|extensions_dir.*orca.*extensions' /opt/orca-51/lib/python3/dist-packages/orca 2>/dev/null | head -160 || true

echo '===== SCREEN READER STARTUP AROUND LOADER ====='
for f in /opt/orca-51/lib/python3/dist-packages/orca/*.py /opt/orca-51/bin/orca; do
  grep -q 'discover_and_load' "$f" 2>/dev/null || continue
  echo "--- $f"
  n=$(grep -n 'discover_and_load' "$f" | head -1 | cut -d: -f1)
  sed -n "$((n-60)),$((n+80))p" "$f" 2>/dev/null || true
done

echo ORCA_DIRECT_LOADER_TEST_DONE=yes
