#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

echo '===== BEFORE RECOVERY ====='
ps -u egor -o pid=,ppid=,stat=,comm=,args= | grep -Ei '[o]rca|speech-dispatcher' || true

# Stop every live Orca process belonging to this desktop. Zombies cannot be killed;
# they disappear when their parent reaps them and do not own D-Bus names.
for p in $(pgrep -u egor -f '(^|/)(orca|orca\.real)( |$)|/opt/orca-51/bin/orca' || true); do
  state=$(ps -o stat= -p "$p" 2>/dev/null | tr -d ' ' || true)
  case "$state" in Z*) continue;; esac
  kill "$p" 2>/dev/null || true
done
sleep 0.8

# Start Orca 51 explicitly with --replace once for recovery. This releases any
# stale single-instance ownership and loads the new extension in the live session.
sudo -u egor "${RUNENV[@]}" bash -c '
  export RUNNER_TRACKING_ID=
  export PATH="/opt/orca-51/bin:$PATH"
  export LD_LIBRARY_PATH="/opt/orca-51/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export GI_TYPELIB_PATH="/opt/orca-51/lib/x86_64-linux-gnu/girepository-1.0${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
  export PYTHONPATH="/opt/orca-51/lib/python3/dist-packages${PYTHONPATH:+:$PYTHONPATH}"
  export GSETTINGS_SCHEMA_DIR=/opt/orca-51/share/glib-2.0/schemas
  mkdir -p "$HOME/.local/state/orca"
  setsid -f /opt/orca-51/bin/orca --replace --debug-file "$HOME/.local/state/orca/orca-debug.log" >"$HOME/.local/state/orca/recovery.log" 2>&1
'

for i in $(seq 1 60); do
  if pgrep -u egor -f '/opt/orca-51/bin/orca' >/dev/null 2>&1; then break; fi
  sleep 0.25
done
sleep 1

echo '===== AFTER RECOVERY ====='
ps -u egor -o pid=,ppid=,stat=,comm=,args= | grep -Ei '[o]rca|speech-dispatcher' || true

echo '===== RECOVERY LOG ====='
tail -n 100 /home/egor/.local/state/orca/recovery.log 2>/dev/null || true

echo '===== EXTENSION LOAD ====='
grep -E 'EGOR ACCESSIBILITY: VoiceOver-like virtual cursor active|Traceback|CRITICAL|ERROR' /home/egor/.local/state/orca/orca-debug.log 2>/dev/null | tail -n 80 || true

live=$(ps -u egor -o stat=,args= | grep '/opt/orca-51/bin/orca' | grep -v grep | grep -v '^Z' || true)
[ -n "$live" ] || { echo ORCA_LIVE=no; exit 1; }
echo ORCA_LIVE=yes
echo ORCA_RECOVERY_DONE=yes
