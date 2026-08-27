#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

debugfile=/home/egor/.local/state/orca/virtual-cursor-debug.log
rm -f "$debugfile"

for p in $(pgrep -u egor -x orca || true); do
  st=$(ps -o stat= -p "$p" 2>/dev/null | xargs || true)
  case "$st" in Z*) ;; *) kill "$p" 2>/dev/null || true;; esac
done
sleep 0.7

sudo -u egor "${RUNENV[@]}" bash -c '
  export RUNNER_TRACKING_ID=
  export PATH="/opt/orca-51/bin:$PATH"
  export LD_LIBRARY_PATH="/opt/orca-51/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export GI_TYPELIB_PATH="/opt/orca-51/lib/x86_64-linux-gnu/girepository-1.0${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
  export PYTHONPATH="/opt/orca-51/lib/python3/dist-packages${PYTHONPATH:+:$PYTHONPATH}"
  export GSETTINGS_SCHEMA_DIR=/opt/orca-51/share/glib-2.0/schemas
  setsid -f /opt/orca-51/bin/orca --replace --debug --debug-file /home/egor/.local/state/orca/virtual-cursor-debug.log >/home/egor/.local/state/orca/virtual-cursor-debug-stderr.log 2>&1
'

live=''
for i in $(seq 1 60); do
  for p in $(pgrep -u egor -x orca || true); do
    st=$(ps -o stat= -p "$p" 2>/dev/null | xargs || true)
    case "$st" in Z*) ;; *) live="$p"; break;; esac
  done
  [ -n "$live" ] && break
  sleep 0.25
done
[ -n "$live" ] || { echo LIVE_ORCA=no; cat /home/egor/.local/state/orca/virtual-cursor-debug-stderr.log 2>/dev/null || true; exit 1; }
sleep 2

echo "LIVE_ORCA_PID=$live"
echo '===== DEBUG FILE ====='
stat -c 'size=%s mtime=%y' "$debugfile" 2>/dev/null || true

echo '===== EXTENSION LINES ====='
grep -Ei 'EXTENSION LOADER|EGOR ACCESSIBILITY|Failed to load|Failed to instantiate|Traceback|Exception|ERROR|CRITICAL' "$debugfile" 2>/dev/null | tail -n 220 || true

echo '===== STDERR ====='
cat /home/egor/.local/state/orca/virtual-cursor-debug-stderr.log 2>/dev/null || true

if grep -q 'EGOR ACCESSIBILITY: VoiceOver-like virtual cursor active' "$debugfile" 2>/dev/null; then
  echo VOICEOVER_CURSOR_EXTENSION_LOADED=yes
else
  echo VOICEOVER_CURSOR_EXTENSION_LOADED=no
  exit 1
fi

echo ORCA_VIRTUAL_CURSOR_VERIFIED=yes
