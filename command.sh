#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

stamp=$(date +%Y%m%d-%H%M%S)
backup=/root/mate-panel-before-menu-fix-$stamp.ini
sudo -u egor "${RUNENV[@]}" dconf dump /org/mate/panel/ > "$backup"

echo '===== BEFORE ====='
sudo -u egor "${RUNENV[@]}" dconf dump /org/mate/panel/objects/briskmenu/ || true

# Replace only the Brisk applet object with MATE's built-in menu bar object.
sudo -u egor "${RUNENV[@]}" dconf reset -f /org/mate/panel/objects/briskmenu/
printf '%s\n' \
  '[briskmenu]' \
  "locked=true" \
  "object-type='menu-bar'" \
  'position=10' \
  "toplevel-id='bottom'" \
  | sudo -u egor "${RUNENV[@]}" dconf load /org/mate/panel/objects/

# Restart only panel, not the desktop/Xpra/Orca session.
sudo -u egor "${RUNENV[@]}" pkill -x mate-panel || true
for i in $(seq 1 40); do
  if pgrep -u egor -x mate-panel >/dev/null 2>&1; then break; fi
  sleep 0.25
done

if ! pgrep -u egor -x mate-panel >/dev/null 2>&1; then
  echo 'PANEL_RESTART_FAILED_RESTORING'
  sudo -u egor "${RUNENV[@]}" dconf reset -f /org/mate/panel/
  sudo -u egor "${RUNENV[@]}" dconf load /org/mate/panel/ < "$backup"
  sudo -u egor "${RUNENV[@]}" mate-panel >/dev/null 2>&1 &
  exit 1
fi
sleep 2

echo '===== AFTER DCONF ====='
sudo -u egor "${RUNENV[@]}" dconf dump /org/mate/panel/objects/briskmenu/ || true

echo '===== LIVE AT-SPI MENU CHECK ====='
sudo -u egor "${RUNENV[@]}" python3 - <<'PY'
import pyatspi
D=pyatspi.Registry.getDesktop(0)
found=[]
for i in range(D.childCount):
    a=D.getChildAtIndex(i)
    name=(a.name or '').strip()
    if name in ('mate-panel','brisk-menu'):
        found.append((name,a.childCount))
        stack=[(a,0)]
        seen=0
        while stack and seen<500:
            o,d=stack.pop(); seen+=1
            try:r=(o.getRoleName() or '').strip()
            except:r='?'
            try:n=(o.name or '').strip()
            except:n='?'
            if r in {'menu','menu item','menu bar','push button','toggle button'}:
                print('MENU_NODE',repr((name,r,n,d)))
            if d<6:
                try:
                    for j in range(o.childCount-1,-1,-1): stack.append((o.getChildAtIndex(j),d+1))
                except: pass
print('APPS',repr(found))
PY

echo '===== PROCESSES ====='
pgrep -a -u egor -x mate-panel || true
pgrep -a -u egor -f brisk-menu || true
pgrep -a -u egor -x orca || true

echo "BACKUP=$backup"
echo BRISK_REPLACED_WITH_NATIVE_MATE_MENU=yes
