#!/usr/bin/env bash
set -euo pipefail

sock=/run/egor-desktop/speech-dispatcher/speechd.sock
[ -S "$sock" ]
spid=$(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' | head -1 || true)
rhv=$(pgrep -u egor -x sd_rhvoice | head -1 || true)
[ -n "$spid" ] && [ -n "$rhv" ]

echo '===== OLD ORCA ====='
old=$(pgrep -u egor -x orca | while read -r p; do [ "$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)" != Z ] && echo "$p"; done | tail -1)
[ -n "$old" ]
echo OLD_ORCA=$old
pp=$(ps -o ppid= -p "$old" | tr -d ' ')
[ -n "$pp" ]
echo OLD_PARENT=$pp

# The running Orca has already sanitized some environment variables; its sudo
# parent still has the exact env arguments used to launch this desktop Orca.
mapfile -t pargs < <(tr '\0' '\n' </proc/$pp/cmdline)
dbus=''
xauth=''
for a in "${pargs[@]}"; do
  case "$a" in
    DBUS_SESSION_BUS_ADDRESS=*) dbus=${a#DBUS_SESSION_BUS_ADDRESS=} ;;
    XAUTHORITY=*) xauth=${a#XAUTHORITY=} ;;
  esac
done
[ -n "$dbus" ]
[ -n "$xauth" ] || xauth=/home/egor/.Xauthority
echo DBUS_PRESENT=yes

echo '===== STOP OLD ORCA ONLY ====='
kill -TERM "$old" 2>/dev/null || true
for i in $(seq 1 50); do
  ! kill -0 "$old" 2>/dev/null && break
  sleep .1
done
kill -KILL "$old" 2>/dev/null || true
sleep .3

echo '===== START ORCA 51 ====='
runuser -u egor -- env -u RUNNER_TRACKING_ID \
  HOME=/home/egor USER=egor LOGNAME=egor \
  DISPLAY=:100 XAUTHORITY="$xauth" XDG_RUNTIME_DIR=/run/egor-desktop \
  DBUS_SESSION_BUS_ADDRESS="$dbus" \
  PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native' \
  nohup setsid /usr/local/bin/orca-egor-launcher >/tmp/orca-reconnect.out 2>/tmp/orca-reconnect.err </dev/null &
launcher=$!
echo LAUNCH_WRAPPER=$launcher

for i in $(seq 1 120); do
  new=$(pgrep -u egor -x orca | while read -r p; do [ "$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)" != Z ] && echo "$p"; done | tail -1)
  if [ -n "${new:-}" ] && [ "$new" != "$old" ]; then break; fi
  sleep .1
done
new=$(pgrep -u egor -x orca | while read -r p; do [ "$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)" != Z ] && echo "$p"; done | tail -1)
[ -n "$new" ] && [ "$new" != "$old" ]
echo NEW_ORCA=$new
sleep 4

echo '===== SPEECH SOCKET CONNECTIONS ====='
ss -xnp 2>/dev/null | grep "$sock" || true
conn_count=$(ss -xnp 2>/dev/null | grep -c "$sock" || true)
echo SPEECH_SOCKET_LINES=$conn_count

# Also use Speech Dispatcher's own connection log as confirmation in case ss
# only prints the pathname on the listening side of an established Unix socket.
tail -n 160 /run/egor-desktop/speech-dispatcher/log/speech-dispatcher.log | grep -Ei 'client|connection|waiting|opened|accepted' | tail -n 60 || true

echo '===== RHVOICE PULSE ====='
PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
clients=$(runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list clients)
inputs=$(runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list sink-inputs)
printf '%s\n' "$clients" | grep -q 'application.name = "RHVoice"'
printf '%s\n' "$inputs" | grep -q 'application.name = "RHVoice"'
echo RHVOICE_PULSE_OK=yes

echo '===== FINAL ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,%cpu=,comm=,args= | grep -E '[o]rca|[s]peech-dispatch|[s]d_rhvoice' || true
cat /tmp/orca-reconnect.err 2>/dev/null || true

echo ORCA_51_RESTARTED=yes
