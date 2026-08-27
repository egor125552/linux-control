#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

ext=/home/egor/.local/share/orca/extensions/egor_desktop_accessibility/__init__.py
hash=$(sha256sum "$ext" | awk '{print $1}')
echo "CURRENT_HASH=$hash"

# Re-approve exactly this locally maintained extension under Orca's active default profile.
sudo -u egor "${RUNENV[@]}" dconf write /org/gnome/orca/default/extensions/approved-user-extensions "{'egor_desktop_accessibility': '$hash'}"

echo '===== APPROVAL ====='
sudo -u egor "${RUNENV[@]}" dconf read /org/gnome/orca/default/extensions/approved-user-extensions

# Restart only Orca and force replacement of any stale single-instance owner.
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
  setsid -f /opt/orca-51/bin/orca --replace --debug-file "$HOME/.local/state/orca/orca-debug.log" >"$HOME/.local/state/orca/voiceover-cursor-restart.log" 2>&1
'

for i in $(seq 1 60); do
  live=''
  for p in $(pgrep -u egor -x orca || true); do
    st=$(ps -o stat= -p "$p" 2>/dev/null | xargs || true)
    case "$st" in Z*) ;; *) live="$p"; break;; esac
  done
  [ -n "$live" ] && break
  sleep 0.25
done
[ -n "${live:-}" ] || { echo LIVE_ORCA=no; exit 1; }
sleep 1.5

echo "LIVE_ORCA_PID=$live"
echo '===== EXTENSION LOADER RESULT ====='
grep -E 'EXTENSION LOADER: (Loaded extension|Extension modified|New extension)|EGOR ACCESSIBILITY: VoiceOver-like virtual cursor active|Traceback|CRITICAL|ERROR' /home/egor/.local/state/orca/orca-debug.log 2>/dev/null | tail -n 120 || true

if grep -q 'EGOR ACCESSIBILITY: VoiceOver-like virtual cursor active' /home/egor/.local/state/orca/orca-debug.log 2>/dev/null; then
  echo VOICEOVER_CURSOR_EXTENSION_LOADED=yes
else
  echo VOICEOVER_CURSOR_EXTENSION_LOADED=no
  exit 1
fi

echo ORCA_VOICEOVER_CURSOR_READY=yes
