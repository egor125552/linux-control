#!/usr/bin/env bash
set -uo pipefail

CONF=/home/egor/.config/speech-dispatcher/speechd.conf
SOCK=/run/egor-desktop/speech-dispatcher/speechd.sock
PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
BACKUP="/home/egor/.config/speech-dispatcher/speechd.conf.before-latency-fix-$(date +%Y%m%d-%H%M%S)"

live_orca() {
  pgrep -u egor -x orca 2>/dev/null | while read -r p; do
    [ "$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)" != Z ] && echo "$p"
  done
}

session_env() {
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

stop_speech_stack() {
  for p in $(live_orca); do kill -TERM "$p" 2>/dev/null || true; done
  for p in $(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' 2>/dev/null || true); do kill -TERM "$p" 2>/dev/null || true; done
  pkill -TERM -u egor -x sd_rhvoice 2>/dev/null || true
  for _ in $(seq 1 50); do
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
  runuser -u egor -- env -u RUNNER_TRACKING_ID \
    HOME=/home/egor USER=egor LOGNAME=egor \
    DISPLAY="$DISPLAY_VALUE" XAUTHORITY="$XAUTHORITY_VALUE" XDG_RUNTIME_DIR="$XDG_RUNTIME_VALUE" \
    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    PULSE_SERVER="$PULSE_SERVER" \
    nohup setsid /usr/local/bin/orca-egor-launcher >/tmp/orca-latency-fix.out 2>/tmp/orca-latency-fix.err </dev/null &
}

wait_stack() {
  for _ in $(seq 1 150); do
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

pulse_env() {
  runuser -u egor -- env HOME=/home/egor XDG_RUNTIME_DIR=/run/egor-desktop LC_ALL=C LANG=C \
    PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"
}

verify_latency() {
  pulse_env pactl list clients | grep -q 'application.name = "RHVoice"' || return 1
  pulse_env pactl list sink-inputs | grep -q 'application.name = "RHVoice"' || return 1
  RH_LAT=$(pulse_env pacmd list-sink-inputs | python3 -c 'import re,sys; t=sys.stdin.read(); bs=re.split(r"\n(?=\s*(?:\* )?index:)",t); b=next((x for x in bs if "<RHVoice>" in x or "application.name = \"RHVoice\"" in x),""); m=re.search(r"requested latency:\s*([0-9.]+)\s*ms",b); print(m.group(1) if m else "")')
  SINK_LAT=$(pulse_env pacmd list-sinks | python3 -c 'import re,sys; t=sys.stdin.read(); bs=re.split(r"\n(?=\s*(?:\* )?index:)",t); b=next((x for x in bs if "name: <Xpra-Speaker>" in x),""); m=re.search(r"configured latency:\s*([0-9.]+)\s*ms",b); print(m.group(1) if m else "")')
  echo "RHVOICE_REQUESTED_LATENCY_MS=${RH_LAT:-missing}"
  echo "XPRA_CONFIGURED_LATENCY_MS=${SINK_LAT:-missing}"
  python3 - "$RH_LAT" "$SINK_LAT" <<'PY'
import sys
try:
    rh=float(sys.argv[1]); sink=float(sys.argv[2])
except Exception:
    raise SystemExit(1)
# 40 ms AudioPulseMinLength should yield about 10 ms Pulse requested/configured latency.
raise SystemExit(0 if rh >= 8.0 and sink >= 8.0 else 1)
PY
}

rollback() {
  echo '===== ROLLBACK ====='
  cp -a "$BACKUP" "$CONF" 2>/dev/null || true
  chown egor:egor "$CONF" 2>/dev/null || true
  stop_speech_stack
  start_orca
  wait_stack || true
  echo 'ROLLBACK_COMPLETE=yes'
}

session_env || { echo 'ERROR=session environment unavailable'; exit 1; }
cp -a "$CONF" "$BACKUP"
echo "BACKUP=$BACKUP"

if grep -qE '^[[:space:]]*AudioPulseMinLength[[:space:]]+' "$CONF"; then
  sed -Ei 's/^[[:space:]]*AudioPulseMinLength[[:space:]]+.*/AudioPulseMinLength 40/' "$CONF"
else
  printf '\n# Stable PulseAudio buffering for RHVoice over Xpra.\nAudioPulseMinLength 40\n' >> "$CONF"
fi
chown egor:egor "$CONF"

echo '===== APPLIED CONFIG ====='
grep -nE 'AudioOutputMethod|AudioPulseMinLength' "$CONF"
[ "$(grep -Ec '^[[:space:]]*AudioPulseMinLength[[:space:]]+40([[:space:]]|$)' "$CONF")" -eq 1 ] || { rollback; exit 1; }

BASE_OVERRUNS=$(journalctl -u egor-desktop.service --since '-10 min' --no-pager 2>/dev/null | grep -c 'asyncq.c: q overrun' || true)
echo "OVERRUNS_BASELINE_10MIN=$BASE_OVERRUNS"

echo '===== RESTART CANONICAL ORCA SPEECH STACK ====='
stop_speech_stack
start_orca
if ! wait_stack; then
  echo 'ERROR=stack did not return'
  cat /tmp/orca-latency-fix.err 2>/dev/null || true
  rollback
  exit 1
fi

echo "ORCA_PID=$ORCA_PID"
echo "SPEECHD_PID=$SPEECHD_PID"
echo "RHVOICE_PID=$RHVOICE_PID"

echo '===== AUDIBLE TEST ====='
if ! pulse_env timeout 10 spd-say -w 'Буфер звука исправлен.' >/tmp/latency-fix-say.out 2>/tmp/latency-fix-say.err; then
  cat /tmp/latency-fix-say.err 2>/dev/null || true
  rollback
  exit 1
fi
sleep 1

if ! verify_latency; then
  echo 'ERROR=latency verification failed'
  pulse_env pacmd list-sink-inputs | tail -n 160 || true
  pulse_env pacmd list-sinks | tail -n 160 || true
  rollback
  exit 1
fi

AFTER_OVERRUNS=$(journalctl -u egor-desktop.service --since '-10 min' --no-pager 2>/dev/null | grep -c 'asyncq.c: q overrun' || true)
echo "OVERRUNS_AFTER_TEST_10MIN=$AFTER_OVERRUNS"
echo "NEW_OVERRUNS_DURING_FIX=$((AFTER_OVERRUNS-BASE_OVERRUNS))"

echo '===== FINAL STACK ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,%cpu=,comm=,args= | grep -E '[o]rca|[s]peech-dispatch|[s]d_rhvoice' || true
echo '===== ORCA SPEECH DEBUG ====='
tail -n 120 /home/egor/.local/state/orca/orca-debug.log 2>/dev/null | grep -E 'SPEECH DISPATCHER|SPEECH OUTPUT' | tail -n 30 || true

echo AUDIO_PULSE_MIN_LENGTH=40
echo AUDIO_LATENCY_FIX_APPLIED=yes
