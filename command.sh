#!/usr/bin/env bash
set -uo pipefail

SOCK=/run/egor-desktop/speech-dispatcher/speechd.sock
PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
TEST_LATENCY=40
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

configured_usec() {
  pulse pactl list sinks | awk 'BEGIN{RS="Sink #"} /Name: Xpra-Speaker/{if (match($0,/configured [0-9]+ usec/)) {x=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",x); print x; exit}}'
}

rhvoice_buffer_usec() {
  pulse pactl list sink-inputs | awk 'BEGIN{RS="Sink Input #"} /application.name = "RHVoice"/{if (match($0,/Buffer Latency: [0-9]+ usec/)) {x=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",x); print x; exit}}'
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

start_orca() {
  local latency=${1:-}
  local -a extra=()
  [ -n "$latency" ] && extra+=("PULSE_LATENCY_MSEC=$latency")
  runuser -u egor -- env -u RUNNER_TRACKING_ID \
    HOME=/home/egor USER=egor LOGNAME=egor \
    DISPLAY="$DISP" XAUTHORITY="$XAUTH" XDG_RUNTIME_DIR="$XDG" \
    DBUS_SESSION_BUS_ADDRESS="$DBUS" PULSE_SERVER="$PULSE_SERVER" \
    "${extra[@]}" \
    nohup setsid /usr/local/bin/orca-egor-launcher >/tmp/orca-pulse-latency.out 2>/tmp/orca-pulse-latency.err </dev/null &
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

restore_baseline() {
  echo '===== RESTORE BASELINE STACK ====='
  stop_stack
  start_orca
  wait_stack || true
  echo BASELINE_RESTORED=yes
}

load_session_env || { echo ERROR=no_session_env; exit 1; }

echo '===== PRECHECK ====='
grep -nE 'AudioOutputMethod|AudioPulseMinLength' /home/egor/.config/speech-dispatcher/speechd.conf || true
BASE_SINK=$(configured_usec || true)
BASE_BUF=$(rhvoice_buffer_usec || true)
echo "BASE_XPRA_CONFIGURED_USEC=${BASE_SINK:-missing}"
echo "BASE_RHVOICE_BUFFER_USEC=${BASE_BUF:-missing}"

echo '===== START TEST STACK WITH PULSE_LATENCY_MSEC=40 ====='
stop_stack
start_orca "$TEST_LATENCY"
if ! wait_stack; then
  echo ERROR=test_stack_failed
  cat /tmp/orca-pulse-latency.err 2>/dev/null || true
  restore_baseline
  exit 1
fi

echo "TEST_ORCA=$ORCA TEST_SPEECHD=$SPD TEST_RHVOICE=$RHV"
RHV_ENV=$(tr '\0' '\n' </proc/$RHV/environ | grep '^PULSE_LATENCY_MSEC=' || true)
echo "RHVOICE_ENV=${RHV_ENV:-missing}"
[ "$RHV_ENV" = "PULSE_LATENCY_MSEC=$TEST_LATENCY" ] || { echo ERROR=env_not_propagated; restore_baseline; exit 1; }

# Generate real speech, then inspect while RHVoice remains connected.
echo '===== AUDIBLE TEST ====='
if ! pulse timeout 10 spd-say -w 'Проверка устойчивого звука.' >/tmp/pulse-latency-say.out 2>/tmp/pulse-latency-say.err; then
  cat /tmp/pulse-latency-say.err 2>/dev/null || true
  restore_baseline
  exit 1
fi
sleep .5

TEST_SINK=$(configured_usec || true)
TEST_BUF=$(rhvoice_buffer_usec || true)
echo "TEST_XPRA_CONFIGURED_USEC=${TEST_SINK:-missing}"
echo "TEST_RHVOICE_BUFFER_USEC=${TEST_BUF:-missing}"

pulse pactl list sink-inputs | awk 'BEGIN{RS="Sink Input #"} /application.name = "RHVoice"/{print "Sink Input #" $0}'
pulse pactl list sinks | awk 'BEGIN{RS="Sink #"} /Name: Xpra-Speaker/{print "Sink #" $0}'

NEW_OVERRUNS=$(journalctl -u egor-desktop.service --since "$MARK" --no-pager 2>/dev/null | grep -c 'asyncq.c: q overrun' || true)
echo "NEW_OVERRUNS_DURING_TEST=$NEW_OVERRUNS"

# Accept only if the environment materially increases the sink scheduling margin.
if [ -z "$TEST_SINK" ] || [ "$TEST_SINK" -lt 8000 ]; then
  echo PULSE_LATENCY_ENV_EFFECTIVE=no
  restore_baseline
  exit 2
fi

echo PULSE_LATENCY_ENV_EFFECTIVE=yes
echo TEST_PULSE_LATENCY_MSEC=$TEST_LATENCY
echo KEEP_TEST_STACK_RUNNING=yes
