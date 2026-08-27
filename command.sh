#!/usr/bin/env bash
set -euo pipefail

getenv_from() {
  local pid=$1 key=$2
  tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n "s/^${key}=//p" | tail -1
}

old_orca=$(pgrep -u egor -x orca | while read -r p; do st=$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true); [ "$st" != Z ] && echo "$p"; done | tail -1)
[ -n "$old_orca" ] || { echo NO_LIVE_ORCA_TO_RESTART; exit 1; }
old_launcher=$(awk '{print $4}' "/proc/$old_orca/stat")
old_sudo=$(awk '{print $4}' "/proc/$old_launcher/stat")

echo "OLD_ORCA=$old_orca OLD_LAUNCHER=$old_launcher OLD_SUDO=$old_sudo"

display=$(getenv_from "$old_sudo" DISPLAY)
xauth=$(getenv_from "$old_sudo" XAUTHORITY)
xdg_runtime=$(getenv_from "$old_sudo" XDG_RUNTIME_DIR)
dbus=$(getenv_from "$old_sudo" DBUS_SESSION_BUS_ADDRESS)
pulse=$(getenv_from "$old_sudo" PULSE_SERVER)

: "${display:=:100}"
: "${xauth:=/home/egor/.Xauthority}"
: "${xdg_runtime:=/run/egor-desktop}"
: "${pulse:=unix:/run/egor-desktop/xpra/100/pulse/native}"
[ -n "$dbus" ] || { echo DBUS_SESSION_BUS_ADDRESS_MISSING; exit 1; }

echo "SESSION_DISPLAY=$display"
echo "SESSION_XDG_RUNTIME=$xdg_runtime"
echo "SESSION_PULSE=$pulse"

echo '===== STOP OLD LIVE ORCA ONLY ====='
kill -TERM "$old_orca" 2>/dev/null || true
for i in $(seq 1 20); do
  [ ! -e "/proc/$old_orca" ] && break
  sleep 0.1
done
if [ -e "/proc/$old_orca" ]; then
  state=$(awk '{print $3}' "/proc/$old_orca/stat" 2>/dev/null || true)
  if [ "$state" != Z ]; then kill -KILL "$old_orca" 2>/dev/null || true; fi
fi
sleep 0.3
kill -TERM "$old_launcher" 2>/dev/null || true
sleep 0.2
kill -TERM "$old_sudo" 2>/dev/null || true
sleep 0.3

echo '===== START NEW ORCA WITH SESSION ENV ====='
mkdir -p /home/egor/.local/state/orca
chown egor:egor /home/egor/.local/state/orca
nohup setsid sudo -u egor env \
  HOME=/home/egor USER=egor LOGNAME=egor \
  DISPLAY="$display" XAUTHORITY="$xauth" \
  XDG_RUNTIME_DIR="$xdg_runtime" \
  DBUS_SESSION_BUS_ADDRESS="$dbus" \
  PULSE_SERVER="$pulse" \
  /usr/local/bin/orca-egor-launcher \
  </dev/null >/home/egor/.local/state/orca/manual-restart.log 2>&1 &
new_sudo=$!
echo "NEW_SUDO=$new_sudo"

# Give Orca enough time to start, autospawn Speech Dispatcher, and keep it alive.
sleep 8

echo '===== NEW ORCA ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep '[o]rca' || true
new_orca=$(pgrep -u egor -x orca | while read -r p; do st=$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true); [ "$st" != Z ] && echo "$p"; done | tail -1)
[ -n "$new_orca" ] || { echo NEW_ORCA_MISSING; cat /home/egor/.local/state/orca/manual-restart.log || true; exit 1; }
[ "$new_orca" != "$old_orca" ] || { echo ORCA_PID_DID_NOT_CHANGE; exit 1; }
grep -q '/opt/orca-51/' "/proc/$new_orca/maps"
echo "NEW_LIVE_ORCA51_PID=$new_orca"

echo '===== NEW ORCA PULSE ENV ====='
tr '\0' '\n' < "/proc/$new_orca/environ" 2>/dev/null | grep -E '^(PULSE_SERVER|PULSE_COOKIE|DISPLAY|DBUS_SESSION_BUS_ADDRESS)=' || true

echo '===== SPEECH STACK AFTER 8 SECONDS ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -E '[s]peech-dispatcher|[s]d_rhvoice' || true
spid=$(pgrep -u egor -f '(^|/)speech-dispatcher([[:space:]]|$)' | head -1 || true)
rpid=$(pgrep -u egor -x sd_rhvoice | head -1 || true)
[ -n "$spid" ] || { echo SPEECH_DISPATCHER_NOT_HELD_BY_ORCA; tail -n 80 /home/egor/.cache/speech-dispatcher/log/speech-dispatcher.log || true; exit 1; }
[ -n "$rpid" ] || { echo RHVOICE_NOT_RUNNING; exit 1; }

grep -q 'Audio output initialized' /home/egor/.cache/speech-dispatcher/log/rhvoice.log
echo "SPEECH_PID=$spid RHVOICE_PID=$rpid"
echo ORCA_SPEECH_RESTART_OK=yes
