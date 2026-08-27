#!/usr/bin/env bash
set -euo pipefail
mate_pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$mate_pid" ] || { echo NO_MATE_SESSION; exit 1; }
getenvp(){ local p="$1" k="$2"; tr '\0' '\n' < "/proc/$p/environ" | sed -n "s/^${k}=//p" | head -1; }
DISPLAY_VAL=$(getenvp "$mate_pid" DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getenvp "$mate_pid" XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
DBUS_VAL=$(getenvp "$mate_pid" DBUS_SESSION_BUS_ADDRESS)
PULSE_SERVER_VAL=$(getenvp "$mate_pid" PULSE_SERVER)
COOKIE=$(find /run/egor-desktop /home/egor/.config/pulse /home/egor/.pulse /tmp -maxdepth 5 -type f \( -name cookie -o -name '*cookie*' \) -user egor -size 256c 2>/dev/null | head -1 || true)
[ -n "$COOKIE" ] || { echo COOKIE_CANDIDATE=no; exit 1; }
echo COOKIE_CANDIDATE=yes
printf 'COOKIE_HASH_PREFIX='; sha256sum "$COOKIE" | cut -c1-16

echo '===== PACTL TEST ====='
if sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" PULSE_SERVER="$PULSE_SERVER_VAL" PULSE_COOKIE="$COOKIE" pactl info >/tmp/egor-pactl-test.$$ 2>&1; then
  sed -n '1,28p' /tmp/egor-pactl-test.$$
  rm -f /tmp/egor-pactl-test.$$
  echo PACTL_COOKIE_CANDIDATE_OK=yes
else
  cat /tmp/egor-pactl-test.$$ || true
  rm -f /tmp/egor-pactl-test.$$
  echo PACTL_COOKIE_CANDIDATE_OK=no
  exit 1
fi

echo COOKIE_CANDIDATE_TEST_DONE=yes
