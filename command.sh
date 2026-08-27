#!/usr/bin/env bash
set -euo pipefail

export HOME=/home/egor
export XDG_RUNTIME_DIR=/run/egor-desktop
export DISPLAY=:100
export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
pe() { runuser -u egor -- env HOME="$HOME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" DISPLAY="$DISPLAY" PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"; }

sock=/run/egor-desktop/speech-dispatcher/speechd.sock

echo '===== CONFIG MUST BE ORIGINAL ====='
nl -ba /home/egor/.config/speech-dispatcher/speechd.conf
! grep -q '^AudioPulseMinLength' /home/egor/.config/speech-dispatcher/speechd.conf

orca_before=$(pgrep -u egor -x orca | while read -r p; do [ "$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)" != Z ] && echo "$p"; done | tail -1)
[ -n "$orca_before" ]
echo ORCA_BEFORE=$orca_before

echo '===== STOP STALE SPEECH SERVER ====='
mapfile -t spids < <(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' || true)
printf 'OLD_SPEECHD=%s\n' "${spids[*]:-none}"
for p in "${spids[@]}"; do kill -TERM "$p" 2>/dev/null || true; done
pkill -TERM -u egor -x sd_rhvoice 2>/dev/null || true
for i in $(seq 1 50); do
  if ! pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' >/dev/null 2>&1; then break; fi
  sleep .1
done
if pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' >/dev/null 2>&1; then
  pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' | xargs -r kill -KILL
  sleep .2
fi
rm -f "$sock"
find /run/egor-desktop/speech-dispatcher/pid -maxdepth 1 -type f -print -delete 2>/dev/null || true

echo '===== START CLEAN SPEECH SERVER ====='
pe /usr/bin/speech-dispatcher --spawn --communication-method unix_socket --socket-path "$sock" --port 6560 >/tmp/repair-spd.out 2>/tmp/repair-spd.err || true
for i in $(seq 1 60); do
  spid=$(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' | head -1 || true)
  if [ -n "$spid" ] && [ -S "$sock" ]; then break; fi
  sleep .1
done
spid=$(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' | head -1 || true)
[ -n "$spid" ]
[ -S "$sock" ]
echo NEW_SPEECHD=$spid
ls -l "$sock"
ss -xlpn 2>/dev/null | grep "$sock"

echo '===== WAKE RHVOICE ====='
pe timeout 8 spd-say -w 'Речевой сервер снова работает.' >/tmp/repair-say.out 2>/tmp/repair-say.err
for i in $(seq 1 30); do
  rhv=$(pgrep -u egor -x sd_rhvoice | head -1 || true)
  [ -n "$rhv" ] && break
  sleep .1
done
rhv=$(pgrep -u egor -x sd_rhvoice | head -1 || true)
[ -n "$rhv" ]
echo NEW_RHVOICE=$rhv

orca_after=$(pgrep -u egor -x orca | while read -r p; do [ "$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)" != Z ] && echo "$p"; done | tail -1)
[ "$orca_after" = "$orca_before" ]
echo ORCA_AFTER=$orca_after

echo '===== FINAL ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -E '[s]peech-dispatch|[s]d_rhvoice|[o]rca' || true
cat /tmp/repair-spd.err || true
cat /tmp/repair-say.err || true

echo SPEECH_STACK_REPAIRED=yes
