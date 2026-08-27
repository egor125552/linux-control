#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

echo '===== AUDIO SERVICES ====='
systemctl is-active audio-remote.service 2>/dev/null || true
systemctl status audio-remote.service --no-pager -n 60 2>&1 | grep -Ev '(password|token|secret|authorization|private)' || true

echo '===== USER AUDIO PROCESSES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -Ei 'pulse|pipewire|wireplumber|speech-dispatch|sd_rhvoice|rhvoice' || true

echo '===== SESSION AUDIO ENV ====='
tr '\0' '\n' < "/proc/$pid/environ" | grep -E '^(PULSE_SERVER|PULSE_RUNTIME_PATH|PIPEWIRE_REMOTE|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|DISPLAY)=' | sed -E 's#(DBUS_SESSION_BUS_ADDRESS=).*#\1present#' || true

echo '===== PACTL IN LIVE SESSION ====='
sudo -u egor "${RUNENV[@]}" pactl info 2>&1 || true
sudo -u egor "${RUNENV[@]}" pactl list short sinks 2>&1 || true
sudo -u egor "${RUNENV[@]}" pactl list short sources 2>&1 || true

echo '===== PIPEWIRE/WPCTL ====='
sudo -u egor "${RUNENV[@]}" wpctl status 2>&1 | head -160 || true

echo '===== RUNTIME AUDIO PATHS ====='
find /run/egor-desktop -maxdepth 3 \( -type s -o -type d \) -printf '%y %m %u:%g %p\n' 2>/dev/null | grep -Ei 'pulse|pipewire|speech|audio' | head -160 || true

echo '===== SPEECH DISPATCHER SAFE SETTINGS ====='
if [ -f /home/egor/.config/speech-dispatcher/speechd.conf ]; then
  grep -Ei '^[[:space:]]*(AudioOutputMethod|AudioPulseServer|DefaultModule|DefaultVoiceType|DefaultLanguage|LogLevel|LogDir|CommunicationMethod|SocketPath)[[:space:]]' /home/egor/.config/speech-dispatcher/speechd.conf 2>/dev/null || true
fi

echo '===== RHVOICE LOG ====='
tail -n 120 /run/egor-desktop/speech-dispatcher/log/rhvoice.log 2>/dev/null || true

echo '===== AUDIO REMOTE JOURNAL ERRORS ====='
journalctl -u audio-remote.service -b --no-pager 2>/dev/null | grep -Ei 'error|fail|pulse|pipewire|audio|socket|listen|connect' | tail -140 || true

echo '===== ORCA SPEECH ERRORS ====='
grep -Ei 'speech dispatcher|playback stream|audio not initialized|speech server|ERROR' /home/egor/.local/state/orca/virtual-cursor-final.log 2>/dev/null | tail -100 || true

echo AUDIO_CHAIN_INSPECT_DONE=yes
