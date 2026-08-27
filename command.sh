#!/usr/bin/env bash
set -euo pipefail
mate_pid=$(pgrep -u egor -x mate-session | head -1 || true)
pulse_pid=$(pgrep -u egor -x pulseaudio | head -1 || true)
[ -n "$mate_pid" ] && [ -n "$pulse_pid" ] || { echo MISSING_PROCESS; exit 1; }

getenvp(){ local p="$1" k="$2"; tr '\0' '\n' < "/proc/$p/environ" | sed -n "s/^${k}=//p" | head -1; }
PULSE_SERVER_MATE=$(getenvp "$mate_pid" PULSE_SERVER)
PULSE_COOKIE_MATE=$(getenvp "$mate_pid" PULSE_COOKIE)
PULSE_SERVER_PULSE=$(getenvp "$pulse_pid" PULSE_SERVER)
PULSE_COOKIE_PULSE=$(getenvp "$pulse_pid" PULSE_COOKIE)

echo '===== PRESENCE ONLY ====='
printf 'mate PULSE_SERVER present: '; [ -n "$PULSE_SERVER_MATE" ] && echo yes || echo no
printf 'mate PULSE_COOKIE present: '; [ -n "$PULSE_COOKIE_MATE" ] && echo yes || echo no
printf 'pulse PULSE_SERVER present: '; [ -n "$PULSE_SERVER_PULSE" ] && echo yes || echo no
printf 'pulse PULSE_COOKIE present: '; [ -n "$PULSE_COOKIE_PULSE" ] && echo yes || echo no

# Never print cookie paths or contents. Only compare stable hashes of the path strings and files.
if [ -n "$PULSE_COOKIE_MATE" ]; then
  printf 'mate cookie path exists: '; [ -f "$PULSE_COOKIE_MATE" ] && echo yes || echo no
  printf 'mate cookie path hash: '; printf '%s' "$PULSE_COOKIE_MATE" | sha256sum | cut -c1-16
  if [ -f "$PULSE_COOKIE_MATE" ]; then printf 'mate cookie file hash: '; sha256sum "$PULSE_COOKIE_MATE" | cut -c1-16; fi
fi
if [ -n "$PULSE_COOKIE_PULSE" ]; then
  printf 'pulse cookie path exists: '; [ -f "$PULSE_COOKIE_PULSE" ] && echo yes || echo no
  printf 'pulse cookie path hash: '; printf '%s' "$PULSE_COOKIE_PULSE" | sha256sum | cut -c1-16
  if [ -f "$PULSE_COOKIE_PULSE" ]; then printf 'pulse cookie file hash: '; sha256sum "$PULSE_COOKIE_PULSE" | cut -c1-16; fi
fi

echo '===== X11 PULSE PROPERTIES NAMES ONLY ====='
DISPLAY_VAL=$(getenvp "$mate_pid" DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getenvp "$mate_pid" XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
DBUS_VAL=$(getenvp "$mate_pid" DBUS_SESSION_BUS_ADDRESS)
sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" xprop -root 2>/dev/null | grep '^PULSE_' | sed -E 's/(PULSE_COOKIE[^=]*=).*/\1 <redacted>/; s/(PULSE_SERVER[^=]*=).*/\1 <redacted>/' || true

echo '===== PACTL TEST WITH PULSE PROCESS COOKIE ENV ====='
if [ -n "$PULSE_COOKIE_PULSE" ]; then
  sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" PULSE_SERVER="$PULSE_SERVER_MATE" PULSE_COOKIE="$PULSE_COOKIE_PULSE" pactl info 2>&1 | sed -n '1,25p' || true
else
  echo NO_PULSE_COOKIE_IN_PULSE_ENV
fi

echo COOKIE_PROPAGATION_CHECK_DONE=yes
