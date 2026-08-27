#!/usr/bin/env bash
set -uo pipefail

LAUNCHER=/usr/local/bin/orca-egor-launcher
SOCK=/run/egor-desktop/speech-dispatcher/speechd.sock
PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
BACKUP="/root/orca-egor-launcher-before-latency-fix-$(date +%Y%m%d-%H%M%S)"
MARK=$(date '+%Y-%m-%d %H:%M:%S')

live_orca() {
  pgrep -u egor -x orca 2>/dev/null | while read -r p; do
    [ "$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)" != Z ] && echo "$p"
  done
}

load_session_env() {
  local mate
  mate=$(pgrep -u egor -x mate-session | head -1 || true)
  [ -n "$mate" ] || return 1
  DBUS=$(tr '\0' '\n' </proc/$mate/environ | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -1)
  DISP=$(tr '\0' '\n' </proc/$mate/environ | sed -n 's/^DISPLAY=//p' | head -1)
  XAUTH=$(tr '\0' '\n' </proc/$mate/environ | sed -n 's/^XAUTHORITY=//p' | head -1)
  XDG=$(tr '\0' '\n' </proc/$mate/environ | sed -n 's/^XDG_RUNTIME_DIR=//p' | head -1)
  [ -n "$DBUS" ] || return 1
  [ -n "$DISP" ] || DISP=:100
  [ -n "$XAUTH" ] || XAUTH=/home/egor/.Xauthority
  [ -n "$XDG" ] || XDG=/run/egor-desktop
}

pulse() {
  runuser -u egor -- env HOME=/home/egor XDG_RUNTIME_DIR=/run/egor-desktop LC_ALL=C LANG=C \
    PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"
}

stop_stack() {
  for p in $(live_orca); do kill -TERM "$p" 2>/dev/null || true; done
  for p in $(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' 2>/dev/null || true); do kill -TERM "$p" 2>/dev/null || true; done
  pkill -TERM -u egor -x sd_rhvoice 2>/dev/null || true
  for _ in $(seq 1 60); do
    [ -z "$(live_orca)" ] && ! pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' >/dev/null 2>&1 && break
    sleep .1
  done
  for p in $(live_orca); do kill -KILL "$p" 2>/dev/null || true; done
  for p in $(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' 2>/dev/null || true); do kill -KILL "$p" 2>/dev/null || true; done
  pkill -KILL -u egor -x sd_rhvoice 2>/dev/null || true
  rm -f "$SOCK"
  find /run/egor-desktop/speech-dispatcher/pid -maxdepth 1 -type f -delete 2>/dev/null || true
}

start_stack() {
  # Important: do NOT pass PULSE_LATENCY_MSEC here. It must come from the launcher itself.
  runuser -u egor -- env -u RUNNER_TRACKING_ID -u PULSE_LATENCY_MSEC \
    HOME=/home/egor USER=egor LOGNAME=egor \
    DISPLAY="$DISP" XAUTHORITY="$XAUTH" XDG_RUNTIME_DIR="$XDG" \
    DBUS_SESSION_BUS_ADDRESS="$DBUS" PULSE_SERVER="$PULSE_SERVER" \
    nohup setsid "$LAUNCHER" >/tmp/orca-persist-latency.out 2>/tmp/orca-persist-latency.err </dev/null &
}

wait_stack() {
  for _ in $(seq 1 180); do
    ORCA=$(live_orca | tail -1)
    SPD=$(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' | head -1 || true)
    RHV=$(pgrep -u egor -x sd_rhvoice | head -1 || true)
    if [ -n "$ORCA" ] && [ -n "$SPD" ] && [ -n "$RHV" ] && [ -S "$SOCK" ]; then return 0; fi
    sleep .1
  done
  return 1
}

rollback_launcher() {
  echo '===== ROLLBACK LAUNCHER ====='
  cp -a "$BACKUP" "$LAUNCHER" 2>/dev/null || true
  chmod 755 "$LAUNCHER" 2>/dev/null || true
  stop_stack
  start_stack
  wait_stack || true
  echo LAUNCHER_ROLLBACK_COMPLETE=yes
}

load_session_env || { echo ERROR=no_session_env; exit 1; }
cp -a "$LAUNCHER" "$BACKUP"
echo "BACKUP=$BACKUP"

python3 - "$LAUNCHER" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
s = p.read_text()
# Remove any old copies to keep the launcher idempotent.
s = re.sub(r'(?m)^\s*(?:#.*RHVoice.*latency.*\n)?\s*export PULSE_LATENCY_MSEC=.*\n?', '', s)
marker = '# Orca 51 is the only permitted screen reader in this session.'
block = ('# RHVoice uses its own libpulse-simple backend and ignores Speech Dispatcher\n'
         '# AudioPulseMinLength. 40 ms gives Xpra-Speaker a stable 10 ms scheduling margin.\n'
         'export PULSE_LATENCY_MSEC=40\n\n')
if marker in s:
    s = s.replace(marker, block + marker, 1)
else:
    s += '\n' + block
p.write_text(s)
PY
chmod 755 "$LAUNCHER"

bash -n "$LAUNCHER" || { rollback_launcher; exit 1; }
COUNT=$(grep -c '^export PULSE_LATENCY_MSEC=40$' "$LAUNCHER" || true)
[ "$COUNT" -eq 1 ] || { echo ERROR=launcher_edit; rollback_launcher; exit 1; }

echo '===== LAUNCHER FIX ====='
grep -n -C 3 'PULSE_LATENCY_MSEC' "$LAUNCHER"

echo '===== RESTART USING PERSISTED LAUNCHER ONLY ====='
stop_stack
start_stack
if ! wait_stack; then
  echo ERROR=stack_failed
  cat /tmp/orca-persist-latency.err 2>/dev/null || true
  rollback_launcher
  exit 1
fi

echo "ORCA=$ORCA SPEECHD=$SPD RHVOICE=$RHV"
RHV_ENV=$(tr '\0' '\n' </proc/$RHV/environ | grep '^PULSE_LATENCY_MSEC=' || true)
echo "RHVOICE_ENV=${RHV_ENV:-missing}"
[ "$RHV_ENV" = 'PULSE_LATENCY_MSEC=40' ] || { echo ERROR=latency_not_persisted; rollback_launcher; exit 1; }

# One normal spoken phrase confirms the path remains audible.
pulse timeout 10 spd-say -w 'Исправление звука включено постоянно.' >/tmp/persist-latency-say.out 2>/tmp/persist-latency-say.err || {
  cat /tmp/persist-latency-say.err 2>/dev/null || true
  rollback_launcher
  exit 1
}
sleep .5

INPUTS=$(pulse pactl list sink-inputs)
SINKS=$(pulse pactl list sinks)
printf '%s\n' "$INPUTS" | grep -q 'application.name = "RHVoice"' || { echo ERROR=no_rhvoice_input; rollback_launcher; exit 1; }
CONFIGURED=$(printf '%s\n' "$SINKS" | awk 'BEGIN{RS="Sink #"} /Name: Xpra-Speaker/{if (match($0,/configured [0-9]+ usec/)) {x=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",x); print x; exit}}')
BUFFER=$(printf '%s\n' "$INPUTS" | awk 'BEGIN{RS="Sink Input #"} /application.name = "RHVoice"/{if (match($0,/Buffer Latency: [0-9]+ usec/)) {x=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",x); print x; exit}}')
echo "XPRA_CONFIGURED_USEC=${CONFIGURED:-missing}"
echo "RHVOICE_BUFFER_USEC=${BUFFER:-missing}"
[ -n "$CONFIGURED" ] && [ "$CONFIGURED" -ge 8000 ] || { echo ERROR=latency_too_low; rollback_launcher; exit 1; }

# Short stress pass: several small utterances, closer to screen-reader navigation than one long phrase.
for i in $(seq 1 8); do
  pulse spd-say "Тест $i" >/dev/null 2>&1 || true
  sleep .08
done
sleep 2

OVERRUNS=$(journalctl -u egor-desktop.service --since "$MARK" --no-pager 2>/dev/null | grep -c 'asyncq.c: q overrun' || true)
echo "NEW_OVERRUNS_SINCE_PERSIST=$OVERRUNS"

echo '===== FINAL XPRA SPEAKER ====='
printf '%s\n' "$SINKS" | awk 'BEGIN{RS="Sink #"} /Name: Xpra-Speaker/{print "Sink #" $0}'
echo '===== FINAL RHVOICE INPUT ====='
printf '%s\n' "$INPUTS" | awk 'BEGIN{RS="Sink Input #"} /application.name = "RHVoice"/{print "Sink Input #" $0}'
echo '===== FINAL STACK ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,%cpu=,comm=,args= | grep -E '[o]rca|[s]peech-dispatch|[s]d_rhvoice' || true

echo PERSISTENT_PULSE_LATENCY_MSEC=40
echo PERSISTENT_RHVOICE_LATENCY_FIX=yes
