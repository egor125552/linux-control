#!/usr/bin/env bash
set -euo pipefail
mate_pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$mate_pid" ] || { echo NO_MATE_SESSION; exit 1; }
getenvp(){ local p="$1" k="$2"; tr '\0' '\n' < "/proc/$p/environ" | sed -n "s/^${k}=//p" | head -1; }
DISPLAY_VAL=$(getenvp "$mate_pid" DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getenvp "$mate_pid" XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
DBUS_VAL=$(getenvp "$mate_pid" DBUS_SESSION_BUS_ADDRESS)
PULSE_SERVER_VAL=$(getenvp "$mate_pid" PULSE_SERVER)

# Extract Xpra's published cookie path without ever printing it.
COOKIE_LINE=$(sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" xprop -root PULSE_COOKIE 2>/dev/null || true)
COOKIE_PATH=$(printf '%s\n' "$COOKIE_LINE" | sed -n 's/^[^=]*= "\(.*\)"$/\1/p')

echo '===== COOKIE CHECK ====='
printf 'x11 cookie property parsed: '; [ -n "$COOKIE_PATH" ] && echo yes || echo no
printf 'cookie path exists: '; [ -n "$COOKIE_PATH" ] && [ -f "$COOKIE_PATH" ] && echo yes || echo no
if [ -n "$COOKIE_PATH" ] && [ -f "$COOKIE_PATH" ]; then
  printf 'cookie file size: '; stat -c %s "$COOKIE_PATH"
  printf 'cookie file hash prefix: '; sha256sum "$COOKIE_PATH" | cut -c1-16
fi

echo '===== PACTL WITH X11 COOKIE ====='
if [ -n "$COOKIE_PATH" ] && [ -f "$COOKIE_PATH" ]; then
  sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" PULSE_SERVER="$PULSE_SERVER_VAL" PULSE_COOKIE="$COOKIE_PATH" pactl info 2>&1 | sed -n '1,30p'
  echo PACTL_WITH_X11_COOKIE_OK=yes
else
  echo PACTL_WITH_X11_COOKIE_OK=no
  exit 1
fi

echo X11_COOKIE_TEST_DONE=yes
