#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
ENVV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

echo '===== PANEL OBJECT IDS ====='
sudo -u egor "${ENVV[@]}" gsettings get org.mate.panel object-id-list || true

echo '===== PANEL TOPLEVEL IDS ====='
sudo -u egor "${ENVV[@]}" gsettings get org.mate.panel toplevel-id-list || true

echo '===== PANEL OBJECT CONFIG ====='
ids=$(sudo -u egor "${ENVV[@]}" gsettings get org.mate.panel object-id-list 2>/dev/null | tr -d "[],'" || true)
for id in $ids; do
  echo "--- $id"
  path="/org/mate/panel/objects/$id/"
  sudo -u egor "${ENVV[@]}" gsettings get org.mate.panel.object object-type --path "$path" 2>/dev/null || true
  sudo -u egor "${ENVV[@]}" gsettings get org.mate.panel.object applet-iid --path "$path" 2>/dev/null || true
  sudo -u egor "${ENVV[@]}" gsettings get org.mate.panel.object toplevel-id --path "$path" 2>/dev/null || true
  sudo -u egor "${ENVV[@]}" gsettings get org.mate.panel.object position --path "$path" 2>/dev/null || true
done

echo '===== AVAILABLE MENU APPLET DESCRIPTORS ====='
find /usr/share /usr/lib -type f \( -iname '*.mate-panel-applet' -o -iname '*.panel-applet' \) 2>/dev/null | xargs -r grep -HilE 'menu|mainmenu|brisk' | sed -n '1,80p'

echo '===== BRISK PACKAGE ====='
dpkg -l | grep -Ei 'brisk|mate-menu|mate-panel' || true

echo PANEL_INSPECT_DONE=yes
