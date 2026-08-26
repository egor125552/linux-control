#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop

echo '===== DCONF PANEL OBJECTS ====='
sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" dconf dump /org/mate/panel/objects/ || true

echo '===== DCONF PANEL GENERAL ====='
sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" dconf dump /org/mate/panel/general/ || true

echo '===== PANEL OBJECT SCHEMA ====='
gsettings list-keys org.mate.panel.object || true
for key in $(gsettings list-keys org.mate.panel.object 2>/dev/null); do
  printf '%s: ' "$key"
  gsettings range org.mate.panel.object "$key" 2>/dev/null | head -3 | tr '\n' ' '; echo
done

echo '===== MENU REFERENCES IN PANEL SOURCE DATA ====='
grep -RniE 'object-type.*menu|menu-path|menu.*object' /usr/share/glib-2.0/schemas /usr/share/mate-panel 2>/dev/null | sed -n '1,120p' || true

echo EXACT_PANEL_DATA_DONE=yes
