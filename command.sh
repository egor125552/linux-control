#!/usr/bin/env bash
set -euo pipefail

HOME=/home/egor
XDG_RUNTIME_DIR=/run/egor-desktop
DISPLAY=:100
PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
sock=/run/egor-desktop/speech-dispatcher/speechd.sock
pe() { runuser -u egor -- env -u RUNNER_TRACKING_ID HOME="$HOME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" DISPLAY="$DISPLAY" PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"; }

echo '===== PRECONDITIONS ====='
! grep -q '^AudioPulseMinLength' /home/egor/.config/speech-dispatcher/speechd.conf
orca=$(pgrep -u egor -x orca | while read -r p; do [ "$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)" != Z ] && echo "$p"; done | tail -1)
[ -n "$orca" ]
echo ORCA=$orca

echo '===== CLEAN OLD SPEECHD ====='
for p in $(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' || true); do kill -TERM "$p" 2>/dev/null || true; done
pkill -TERM -u egor -x sd_rhvoice 2>/dev/null || true
sleep .5
for p in $(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' || true); do kill -KILL "$p" 2>/dev/null || true; done
rm -f "$sock"
find /run/egor-desktop/speech-dispatcher/pid -maxdepth 1 -type f -delete 2>/dev/null || true

echo '===== START PERSISTENT SPEECHD ====='
pe /usr/bin/speech-dispatcher --run-daemon --timeout 0 --communication-method unix_socket --socket-path "$sock" --port 6560 >/tmp/persistent-spd.out 2>/tmp/persistent-spd.err || true
for i in $(seq 1 60); do
  spid=$(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' | head -1 || true)
  [ -n "$spid" ] && [ -S "$sock" ] && break
  sleep .1
done
spid=$(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' | head -1 || true)
[ -n "$spid" ]
[ -S "$sock" ]
echo SPEECHD=$spid
ss -xlpn 2>/dev/null | grep "$sock"

echo '===== TEST RHVOICE AUDIO ====='
pe timeout 8 spd-say -w 'Речевой сервер восстановлен.' >/tmp/persistent-say.out 2>/tmp/persistent-say.err
for i in $(seq 1 40); do
  rhv=$(pgrep -u egor -x sd_rhvoice | head -1 || true)
  [ -n "$rhv" ] && break
  sleep .1
done
rhv=$(pgrep -u egor -x sd_rhvoice | head -1 || true)
[ -n "$rhv" ]
echo RHVOICE=$rhv

# A real Pulse client and sink input prove playback initialization, not merely process existence.
clients=$(pe pactl list clients)
inputs=$(pe pactl list sink-inputs)
printf '%s\n' "$clients" | grep -q 'application.name = "RHVoice"'
printf '%s\n' "$inputs" | grep -q 'application.name = "RHVoice"'
echo RHVOICE_PULSE_CLIENT=yes
echo RHVOICE_SINK_INPUT=yes

echo '===== WAIT FOR ORCA RECONNECT ====='
# Give existing Orca a chance to notice the restored socket; do not restart it here.
sleep 3
ss -xnp 2>/dev/null | grep "$sock" || true
orca_after=$(pgrep -u egor -x orca | while read -r p; do [ "$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)" != Z ] && echo "$p"; done | tail -1)
[ "$orca_after" = "$orca" ]
echo ORCA_AFTER=$orca_after

echo '===== FINAL ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -E '[s]peech-dispatch|[s]d_rhvoice|[o]rca' || true
cat /tmp/persistent-spd.err || true
cat /tmp/persistent-say.err || true

echo PERSISTENT_SPEECHD_RESTORED=yes
