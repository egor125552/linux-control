#!/usr/bin/env bash
set -uo pipefail

LAUNCHER=/usr/local/bin/orca-egor-launcher
SOCK=/run/egor-desktop/speech-dispatcher/speechd.sock
PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
BACKUP="/root/orca-egor-launcher-before-60ms-$(date +%Y%m%d-%H%M%S)"
MARK=$(date '+%Y-%m-%d %H:%M:%S')

live_orca() {
  pgrep -u egor -x orca 2>/dev/null | while read -r p; do
    [ "$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)" != Z ] && echo "$p"
  done
}
load_env() {
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
  runuser -u egor -- env -u RUNNER_TRACKING_ID -u PULSE_LATENCY_MSEC \
    HOME=/home/egor USER=egor LOGNAME=egor \
    DISPLAY="$DISP" XAUTHORITY="$XAUTH" XDG_RUNTIME_DIR="$XDG" \
    DBUS_SESSION_BUS_ADDRESS="$DBUS" PULSE_SERVER="$PULSE_SERVER" \
    nohup setsid "$LAUNCHER" >/tmp/orca-60ms.out 2>/tmp/orca-60ms.err </dev/null &
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
rollback() {
  echo '===== ROLLBACK TO 40MS ====='
  cp -a "$BACKUP" "$LAUNCHER" 2>/dev/null || true
  chmod 755 "$LAUNCHER" 2>/dev/null || true
  stop_stack
  start_stack
  wait_stack || true
  echo ROLLBACK_COMPLETE=yes
}

load_env || { echo ERROR=no_session_env; exit 1; }
cp -a "$LAUNCHER" "$BACKUP"
echo "BACKUP=$BACKUP"

# Raise only the proven Pulse environment knob: 40 -> 60 ms.
sed -Ei 's/^export PULSE_LATENCY_MSEC=[0-9]+$/export PULSE_LATENCY_MSEC=60/' "$LAUNCHER"
# Keep the explanatory comment accurate.
sed -Ei 's/40 ms gives Xpra-Speaker a stable 10 ms scheduling margin\./60 ms gives Xpra-Speaker more scheduling margin while keeping Orca responsive./' "$LAUNCHER"

bash -n "$LAUNCHER" || { rollback; exit 1; }
[ "$(grep -c '^export PULSE_LATENCY_MSEC=60$' "$LAUNCHER" || true)" -eq 1 ] || { echo ERROR=launcher_edit; rollback; exit 1; }

echo '===== 60MS LAUNCHER ====='
grep -n -C 3 'PULSE_LATENCY_MSEC' "$LAUNCHER"

stop_stack
start_stack
if ! wait_stack; then
  echo ERROR=stack_failed
  cat /tmp/orca-60ms.err 2>/dev/null || true
  rollback
  exit 1
fi

echo "ORCA=$ORCA SPEECHD=$SPD RHVOICE=$RHV"
RHV_ENV=$(tr '\0' '\n' </proc/$RHV/environ | grep '^PULSE_LATENCY_MSEC=' || true)
echo "RHVOICE_ENV=${RHV_ENV:-missing}"
[ "$RHV_ENV" = 'PULSE_LATENCY_MSEC=60' ] || { echo ERROR=env_not_60; rollback; exit 1; }

# Prime the stream.
pulse timeout 10 spd-say -w 'Проверка шестидесяти миллисекунд.' >/tmp/60ms-prime.out 2>/tmp/60ms-prime.err || { cat /tmp/60ms-prime.err; rollback; exit 1; }
sleep .4

INPUTS=$(pulse pactl list sink-inputs)
SINKS=$(pulse pactl list sinks)
CONFIGURED=$(printf '%s\n' "$SINKS" | awk 'BEGIN{RS="Sink #"} /Name: Xpra-Speaker/{if(match($0,/configured [0-9]+ usec/)){x=substr($0,RSTART,RLENGTH);gsub(/[^0-9]/,"",x);print x;exit}}')
BUFFER=$(printf '%s\n' "$INPUTS" | awk 'BEGIN{RS="Sink Input #"} /application.name = "RHVoice"/{if(match($0,/Buffer Latency: [0-9]+ usec/)){x=substr($0,RSTART,RLENGTH);gsub(/[^0-9]/,"",x);print x;exit}}')
echo "XPRA_CONFIGURED_USEC=${CONFIGURED:-missing}"
echo "RHVOICE_BUFFER_USEC=${BUFFER:-missing}"
# 60 ms PULSE_LATENCY_MSEC should produce roughly 15 ms configured sink latency.
[ -n "$CONFIGURED" ] && [ "$CONFIGURED" -ge 12000 ] || { echo ERROR=60ms_not_effective; rollback; exit 1; }

# Stress closer to rapid VoiceOver/Orca navigation: short bursts with overlaps and cancellations.
for round in $(seq 1 4); do
  for i in $(seq 1 10); do
    pulse spd-say "Пункт $round $i" >/dev/null 2>&1 || true
    sleep .045
  done
  pulse spd-say -C >/dev/null 2>&1 || true
  sleep .12
done
pulse timeout 10 spd-say -w 'Стресс тест завершён.' >/dev/null 2>&1 || { rollback; exit 1; }
sleep 2

OVERRUNS=$(journalctl -u egor-desktop.service --since "$MARK" --no-pager 2>/dev/null | grep -c 'asyncq.c: q overrun' || true)
UNDERRUNS=$(journalctl -u egor-desktop.service --since "$MARK" --no-pager 2>/dev/null | grep -Eci 'underflow|underrun' || true)
echo "NEW_Q_OVERRUNS=$OVERRUNS"
echo "NEW_UNDERRUN_MESSAGES=$UNDERRUNS"

# Confirm processes survived the burst.
ORCA2=$(live_orca | tail -1)
SPD2=$(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' | head -1 || true)
RHV2=$(pgrep -u egor -x sd_rhvoice | head -1 || true)
[ -n "$ORCA2" ] && [ -n "$SPD2" ] && [ -n "$RHV2" ] || { echo ERROR=stack_died; rollback; exit 1; }

echo '===== FINAL STACK ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,%cpu=,%mem=,comm=,args= | grep -E '[o]rca|[s]peech-dispatch|[s]d_rhvoice' || true

echo PERSISTENT_PULSE_LATENCY_MSEC=60
echo SIXTY_MS_STRESS_OK=yes
