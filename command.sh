#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

echo '===== ORCA DCONF TREE ====='
sudo -u egor "${RUNENV[@]}" dconf dump /org/gnome/orca/ | grep -E '^\[|approved-user-extensions|disabled-extensions|active-profile|profiles' || true

echo '===== PROFILE KEYS ====='
sudo -u egor "${RUNENV[@]}" dconf list /org/gnome/orca/ || true
for p in $(sudo -u egor "${RUNENV[@]}" dconf list /org/gnome/orca/ 2>/dev/null | grep '/$' || true); do
  echo "--- $p"
  sudo -u egor "${RUNENV[@]}" dconf dump "/org/gnome/orca/$p" 2>/dev/null | grep -E '^\[|approved-user-extensions|disabled-extensions' || true
done

echo ORCA_PROFILE_FOUND=yes
