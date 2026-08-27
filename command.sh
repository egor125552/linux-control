#!/usr/bin/env bash
set -euo pipefail

echo '===== EGOR MATE SESSION SAFE VIEW ====='
if [ -f /usr/local/bin/egor-mate-session ]; then
  sed -n '1,220p' /usr/local/bin/egor-mate-session \
    | sed -E 's#(PULSE_COOKIE=).*#\1<redacted>#; s#(token|password|secret|authorization)=.*#\1=<redacted>#Ig'
fi

echo '===== PULSE CLIENT CONFIG SAFE VIEW ====='
for f in /etc/pulse/client.conf /home/egor/.config/pulse/client.conf /home/egor/.pulse/client.conf; do
  if [ -f "$f" ]; then
    echo "FILE=$f"
    grep -Ev '^[[:space:]]*(#|;|$)' "$f" | sed -E 's#(cookie-file[[:space:]]*=).*#\1 <redacted>#' || true
  fi
done

echo '===== SPEECHD CONFIG AUDIO LINES ====='
grep -Ei '^[[:space:]]*(AudioOutputMethod|AudioPulseServer|DefaultModule|DefaultLanguage|DefaultVoiceType|CommunicationMethod|SocketPath)[[:space:]]' /home/egor/.config/speech-dispatcher/speechd.conf 2>/dev/null || true

echo '===== SPEECH PROCESS ENV PRESENCE ====='
for p in $(pgrep -u egor -f 'speech-dispatcher|sd_rhvoice' || true); do
  [ -r "/proc/$p/environ" ] || continue
  echo "PID=$p COMM=$(cat /proc/$p/comm 2>/dev/null || true)"
  for k in PULSE_SERVER PULSE_COOKIE DISPLAY XDG_RUNTIME_DIR; do
    if tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -q "^${k}="; then
      echo "$k=present"
    else
      echo "$k=absent"
    fi
  done
done

echo '===== CURRENT WORKING COOKIE TEST ====='
mate_pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$mate_pid" ] || { echo NO_MATE_SESSION; exit 1; }
getenvp(){ local p="$1" k="$2"; tr '\0' '\n' < "/proc/$p/environ" | sed -n "s/^${k}=//p" | head -1; }
DISPLAY_VAL=$(getenvp "$mate_pid" DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getenvp "$mate_pid" XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
DBUS_VAL=$(getenvp "$mate_pid" DBUS_SESSION_BUS_ADDRESS)
PULSE_SERVER_VAL=$(getenvp "$mate_pid" PULSE_SERVER)
COOKIE=$(find /run/egor-desktop /home/egor/.config/pulse /home/egor/.pulse /tmp -maxdepth 6 -type f -user egor -size 256c 2>/dev/null | grep -E '(^|/)[^/]*cookie[^/]*$' | head -1 || true)
[ -n "$COOKIE" ] && [ -f "$COOKIE" ] || { echo WORKING_COOKIE_FOUND=no; exit 1; }
if sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" PULSE_SERVER="$PULSE_SERVER_VAL" PULSE_COOKIE="$COOKIE" pactl info >/dev/null 2>&1; then
  echo WORKING_COOKIE_FOUND=yes
  echo WORKING_COOKIE_AUTH=yes
else
  echo WORKING_COOKIE_AUTH=no
fi

echo SPEECH_STARTUP_CONFIG_INSPECT_DONE=yes
