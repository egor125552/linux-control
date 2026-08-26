#!/usr/bin/env bash
set -euo pipefail

pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo 'NO_MATE_SESSION'; exit 1; }
getv() { tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS); [ -n "$DBUS_VAL" ] || { echo 'NO_SESSION_DBUS'; exit 1; }
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop

echo '===== ACCESSIBILITY SETTINGS ====='
sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" sh -c '
  printf "mate accessibility: "; gsettings get org.mate.interface accessibility
  printf "toolkit accessibility: "; gsettings get org.gnome.desktop.interface toolkit-accessibility
  printf "screen reader: "; gsettings get org.gnome.desktop.a11y.applications screen-reader-enabled
'

echo '===== AT-SPI TREE SUMMARY ====='
sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" python3 - <<'PY'
import pyatspi
from collections import Counter, defaultdict

d=pyatspi.Registry.getDesktop(0)
print('desktop_children=', d.childCount)
role_counts=Counter()
empty=[]
apps=[]
interesting=[]

SKIP_EMPTY_ROLES={'filler','panel','layered pane','root pane','scroll pane','viewport','separator','unknown'}

for ai in range(d.childCount):
    try:
        app=d.getChildAtIndex(ai)
        an=(app.name or '').strip()
        apps.append((ai,an,app.childCount))
        stack=[(app,0,an or f'app#{ai}')]
        seen=0
        while stack and seen<1200:
            obj,depth,path=stack.pop(); seen+=1
            try: role=(obj.getRoleName() or '').strip()
            except Exception: role='<role-error>'
            try: name=(obj.name or '').strip()
            except Exception: name='<name-error>'
            role_counts[role]+=1
            p=path + '/' + (name or f'<{role}>')
            if not name and role not in SKIP_EMPTY_ROLES:
                empty.append((an,role,depth,p))
            if role in {'push button','toggle button','menu item','check menu item','radio menu item','text','entry','combo box','link','tab','page tab','icon'}:
                interesting.append((an,role,name,depth,p))
            if depth<7:
                try:
                    for i in range(min(obj.childCount,120)-1,-1,-1):
                        stack.append((obj.getChildAtIndex(i),depth+1,p))
                except Exception:
                    pass
    except Exception as e:
        print('APP_ERROR',ai,repr(e))

print('APPLICATIONS')
for x in apps: print(repr(x))
print('ROLE_COUNTS_TOP')
for r,c in role_counts.most_common(35): print(f'{r}: {c}')
print('EMPTY_INTERACTIVE_OR_SEMANTIC_COUNT=',len(empty))
for rec in empty[:180]: print('EMPTY',repr(rec))
print('NAMED_INTERACTIVE_SAMPLE')
for rec in interesting[:220]: print('ITEM',repr(rec))
PY

echo '===== ORCA / MATE LOG WARNINGS ====='
journalctl -u egor-desktop.service -b --no-pager | grep -Ei 'orca|at-spi|accessib|brisk-menu|caja|mate-panel|critical|warning|error|failed' | tail -n 160 || true

echo 'MATE_A11Y_AUDIT_DONE=yes'
