#!/usr/bin/env bash
set -uo pipefail

CONF=/home/egor/.config/speech-dispatcher/speechd.conf
SOCK=/run/egor-desktop/speech-dispatcher/speechd.sock
PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
BACKUP="/home/egor/.config/speech-dispatcher/speechd.conf.before-40ms-final-$(date +%Y%m%d-%H%M%S)"
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
  DBUS_SESSION_BUS_ADDRESS=$(tr '\0' '\n' </proc/$mate/environ | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -1)
  DISPLAY_VALUE=$(tr '\0' '\n' </proc/$mate/environ | sed -n 's/^DISPLAY=//p' | head -1)
  XAUTHORITY_VALUE=$(tr '\0' '\n' </proc/$mate/environ | sed -n 's/^XAUTHORITY=//p' | head -1)
  XDG_RUNTIME_VALUE=$(tr '\0' '\n' </proc/$mate/environ | sed -n 's/^XDG_RUNTIME_DIR=//p' | head -1)
  [ -n "$DBUS_SESSION_BUS_ADDRESS" ] || return 1
  [ -n "$DISPLAY_VALUE" ] || DISPLAY_VALUE=:100
  [ -n "$XAUTHORITY_VALUE" ] || XAUTHORITY_VALUE=/home/egor/.Xauthority
  [ -n "$XDG_RUNTIME_VALUE" ] || XDG_RUNTIME_VALUE=/run/egor-desktop
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
  runuser -u egor -- env -u RUNNER_TRACKING_ID \
    HOME=/home/egor USER=egor LOGNAME=egor \
    DISPLAY="$DISPLAY_VALUE" XAUTHORITY="$XAUTHORITY_VALUE" XDG_RUNTIME_DIR="$XDG_RUNTIME_VALUE" \
    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    PULSE_SERVER="$PULSE_SERVER" \
    nohup setsid /usr/local/bin/orca-egor-launcher >/tmp/orca-40ms.out 2>/tmp/orca-40ms.err </dev/null &
}

wait_stack() {
  for _ in $(seq 1 180); do
    ORCA_PID=$(live_orca | tail -1)
    SPEECHD_PID=$(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' | head -1 || true)
    RHVOICE_PID=$(pgrep -u egor -x sd_rhvoice | head -1 || true)
    if [ -n "$ORCA_PID" ] && [ -n "$SPEECHD_PID" ] && [ -n "$RHVOICE_PID" ] && [ -S "$SOCK" ]; then
      return 0
    fi
    sleep .1
  done
  return 1
}

verify_pulse() {
  pulse pactl info >/tmp/40ms-pactl-info || return 1
  pulse pactl list clients | grep -q 'application.name = "RHVoice"' || return 1
  pulse pactl list sink-inputs > /tmp/40ms-inputs || return 1
  grep -q 'application.name = "RHVoice"' /tmp/40ms-inputs || return 1
  pulse pactl list sinks > /tmp/40ms-sinks || return 1
  CONFIGURED_USEC=$(awk 'BEGIN{RS="Sink #"} /Name: Xpra-Speaker/{if (match($0,/configured [0-9]+ usec/)) {x=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",x); print x; exit}}' /tmp/40ms-sinks)
  BUFFER_USEC=$(awk 'BEGIN{RS="Sink Input #"} /application.name = "RHVoice"/{if (match($0,/Buffer Latency: [0-9]+ usec/)) {x=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",x); print x; exit}}' /tmp/40ms-inputs)
  echo "XPRA_CONFIGURED_USEC=${CONFIGURED_USEC:-missing}"
  echo "RHVOICE_BUFFER_USEC=${BUFFER_USEC:-missing}"
  [ -n "$CONFIGURED_USEC" ] || return 1
  [ "$CONFIGURED_USEC" -ge 8000 ] || return 1
  return 0
}

rollback() {
  echo '===== ROLLBACK ====='
  cp -a "$BACKUP" "$CONF" 2>/dev/null || true
  chown egor:egor "$CONF" 2>/dev/null || true
  stop_stack
  start_stack
  wait_stack || true
  echo ROLLBACK_COMPLETE=yes
}

load_session_env || { echo ERROR=session_env; exit 1; }
cp -a "$CONF" "$BACKUP"
echo "BACKUP=$BACKUP"

if grep -qE '^[[:space:]]*AudioPulseMinLength[[:space:]]+' "$CONF"; then
  sed -Ei 's/^[[:space:]]*AudioPulseMinLength[[:space:]]+.*/AudioPulseMinLength 40/' "$CONF"
else
  printf '\n# Stable buffering for RHVoice over Xpra PulseAudio.\nAudioPulseMinLength 40\n' >> "$CONF"
fi
chown egor:egor "$CONF"

echo '===== CONFIGURED ====='
grep -nE 'AudioOutputMethod|AudioPulseMinLength' "$CONF"
[ "$(grep -Ec '^[[:space:]]*AudioPulseMinLength[[:space:]]+40([[:space:]]|$)' "$CONF")" -eq 1 ] || { rollback; exit 1; }

echo '===== RESTART ====='
stop_stack
start_stack
if ! wait_stack; then
  echo ERROR=stack_start
  cat /tmp/orca-40ms.err 2>/dev/null || true
  rollback
  exit 1
fi

echo "ORCA_PID=$ORCA_PID"
echo "SPEECHD_PID=$SPEECHD_PID"
echo "RHVOICE_PID=$RHVOICE_PID"

# Let Orca finish its initial speech so Pulse settles into the requested latency.
sleep 2

echo '===== AUDIBLE TEST ====='
if ! pulse timeout 10 spd-say -w 'Буфер звука исправлен.' >/tmp/40ms-say.out 2>/tmp/40ms-say.err; then
  cat /tmp/40ms-say.err 2>/dev/null || true
  rollback
  exit 1
fi
sleep 1

echo '===== PACTL VERIFICATION ====='
if ! verify_pulse; then
  echo ERROR=pactl_verification
  cat /tmp/40ms-inputs 2>/dev/null || true
  cat /tmp/40ms-sinks 2>/dev/null || true
  rollback
  exit 1
fi

NEW_OVERRUNS=$(journalctl -u egor-desktop.service --since "$MARK" --no-pager 2>/dev/null | grep -c 'asyncq.c: q overrun' || true)
echo "NEW_OVERRUNS_SINCE_FIX=$NEW_OVERRUNS"
if [ "$NEW_OVERRUNS" -gt 0 ]; then
  echo 'WARNING=new overruns occurred during short verification'
  journalctl -u egor-desktop.service --since "$MARK" --no-pager 2>/dev/null | grep 'asyncq.c: q overrun' | tail -n 30 || true
fi

echo '===== FINAL RHVOICE INPUT ====='
awk 'BEGIN{RS="Sink Input #"} /application.name = "RHVoice"/{print "Sink Input #" $0}' /tmp/40ms-inputs

echo '===== FINAL XPRA SPEAKER ====='
awk 'BEGIN{RS="Sink #"} /Name: Xpra-Speaker/{print "Sink #" $0}' /tmp/40ms-sinks

echo '===== FINAL STACK ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,%cpu=,comm=,args= | grep -E '[o]rca|[s]peech-dispatch|[s]d_rhvoice' || true

echo AUDIO_PULSE_MIN_LENGTH=40
echo AUDIO_LATENCY_FIX_APPLIED=yes
