#!/usr/bin/env bash
set -euo pipefail

pid=$(pgrep -u egor -x mate-session | head -1 || true)
if [ -z "$pid" ]; then
  echo 'NO_MATE_SESSION'
  exit 1
fi

getenv_from_proc() {
  key="$1"
  tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^${key}=//p" | head -1
}

DISPLAY_VAL=$(getenv_from_proc DISPLAY)
DBUS_VAL=$(getenv_from_proc DBUS_SESSION_BUS_ADDRESS)
XDG_VAL=$(getenv_from_proc XDG_RUNTIME_DIR)

[ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
[ -n "$DBUS_VAL" ] || { echo 'NO_SESSION_DBUS'; exit 1; }
[ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop

echo '===== LIVE SESSION ====='
echo "DISPLAY=$DISPLAY_VAL"
echo "XDG_RUNTIME_DIR=$XDG_VAL"
echo 'DBUS_SESSION_BUS_ADDRESS=present'

echo '===== A11Y BUS ====='
sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" \
  gdbus call --session --dest org.a11y.Bus --object-path /org/a11y/bus --method org.a11y.Bus.GetAddress 2>&1 || true

echo '===== LIVE AT-SPI APPLICATION TREE ====='
sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" \
python3 - <<'PY'
import sys
try:
    import pyatspi
except Exception as e:
    print('PYATSPI_IMPORT_ERROR', repr(e))
    sys.exit(0)

def safe_name(obj):
    try:
        return obj.name or ''
    except Exception:
        return '<name-error>'

def safe_role(obj):
    try:
        return obj.getRoleName() or ''
    except Exception:
        return '<role-error>'

def walk(obj, depth=0, maxdepth=4, budget=[0]):
    if budget[0] >= 500:
        return
    budget[0] += 1
    name=safe_name(obj)
    role=safe_role(obj)
    marker=' EMPTY-NAME' if not name.strip() else ''
    print('  '*depth + f'- role={role!r} name={name!r} children={getattr(obj,"childCount",-1)}{marker}')
    if depth >= maxdepth:
        return
    try:
        n=min(obj.childCount, 60)
        for i in range(n):
            try:
                walk(obj.getChildAtIndex(i), depth+1, maxdepth, budget)
            except Exception as e:
                print('  '*(depth+1)+f'- CHILD_ERROR {i}: {e!r}')
    except Exception as e:
        print('  '*(depth+1)+f'- ENUM_ERROR {e!r}')

d=pyatspi.Registry.getDesktop(0)
print(f'DESKTOP children={d.childCount}')
for i in range(d.childCount):
    try:
        app=d.getChildAtIndex(i)
        print(f'APP[{i}] role={safe_role(app)!r} name={safe_name(app)!r} children={app.childCount}')
        walk(app,1,4,[0])
    except Exception as e:
        print(f'APP_ERROR {i}: {e!r}')
PY

echo 'AT_SPI_TREE_DONE=yes'
