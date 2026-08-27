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
live_pids=''
for p in $(pgrep -u egor -x orca || true); do
  state=$(ps -o stat= -p "$p" 2>/dev/null | xargs || true)
  echo "PID=$p STATE=$state EXE=$(readlink -f /proc/$p/exe 2>/dev/null || true)"
  tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null || true; echo
  case "$state" in Z*) ;; *) live_pids="$live_pids $p";; esac
done
[ -n "$live_pids" ] || { echo LIVE_ORCA=no; exit 1; }
echo LIVE_ORCA=yes

echo '===== ORCA DEBUG NEW TAIL ====='
tail -n 260 /home/egor/.local/state/orca/orca-debug.log 2>/dev/null | grep -Ei 'EGOR ACCESSIBILITY|extension|traceback|exception|error|critical|ready' | tail -n 160 || true

echo '===== EXTENSION IMPORT WITH ORCA51 ENV ====='
sudo -u egor "${RUNENV[@]}" bash -c '
  export PATH="/opt/orca-51/bin:$PATH"
  export LD_LIBRARY_PATH="/opt/orca-51/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export GI_TYPELIB_PATH="/opt/orca-51/lib/x86_64-linux-gnu/girepository-1.0${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
  export PYTHONPATH="/home/egor/.local/share:/opt/orca-51/lib/python3/dist-packages${PYTHONPATH:+:$PYTHONPATH}"
  export GSETTINGS_SCHEMA_DIR=/opt/orca-51/share/glib-2.0/schemas
  python3 - <<"PY"
import importlib.util
p="/home/egor/.local/share/orca/extensions/egor_desktop_accessibility/__init__.py"
spec=importlib.util.spec_from_file_location("orca.extensions.egor_desktop_accessibility",p,submodule_search_locations=[p.rsplit("/",1)[0]])
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print("EXTENSION_IMPORT_OK=yes")
print("VERSION=",m.EgorDesktopAccessibility.VERSION)
d=m._safe(lambda: m.Atspi.get_desktop(0))
print("DESKTOP_OK=",d is not None)
if d is not None:
    print("DESKTOP_CHILDREN=",d.get_child_count())
    candidates=m._top_level_candidates()
    print("TOP_LEVEL_CANDIDATES=",[(s,a,m._name(w),m._role(w)) for s,a,w in candidates[:8]])
    surface=m._best_surface()
    print("BEST_SURFACE=",m._name(surface),m._role(surface))
    items=m._flatten_semantic(surface) if surface is not None else []
    print("SEMANTIC_ITEMS=",len(items))
    print("FIRST_ITEMS=",[(m._name(x),m._role(x)) for x in items[:20]])
PY
'

echo ORCA_RECOVERY_VERIFIED=yes
