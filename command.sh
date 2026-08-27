#!/usr/bin/env bash
set -euo pipefail

export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
export HOME=/home/egor
export XDG_RUNTIME_DIR=/run/egor-desktop
export DISPLAY=:100
conf=/home/egor/.config/speech-dispatcher/speechd.conf
stamp=$(date +%Y%m%d-%H%M%S)
backup="$conf.before-pulse-latency-$stamp"

pe() { runuser -u egor -- env LC_ALL=C LANG=C HOME="$HOME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" DISPLAY="$DISPLAY" PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"; }

restart_speech() {
  pkill -TERM -u egor -x speech-dispatcher 2>/dev/null || true
  pkill -TERM -u egor -x sd_rhvoice 2>/dev/null || true
  for i in $(seq 1 30); do
    ! pgrep -u egor -x speech-dispatcher >/dev/null 2>&1 && break
    sleep .1
  done
  rm -f /run/egor-desktop/speech-dispatcher/speechd.sock
  pe /usr/bin/speech-dispatcher --spawn --communication-method unix_socket --socket-path /run/egor-desktop/speech-dispatcher/speechd.sock --port 6560 >/tmp/speechd-restart.out 2>/tmp/speechd-restart.err || true
  for i in $(seq 1 50); do
    if pgrep -u egor -x speech-dispatcher >/dev/null 2>&1 && [ -S /run/egor-desktop/speech-dispatcher/speechd.sock ]; then
      return 0
    fi
    sleep .1
  done
  return 1
}

rollback() {
  rc=$?
  trap - ERR
  echo "ROLLBACK rc=$rc"
  cp -a "$backup" "$conf" 2>/dev/null || true
  chown egor:egor "$conf" 2>/dev/null || true
  restart_speech || true
  exit "$rc"
}
trap rollback ERR

echo '===== CLEAN DIAGNOSTIC PACAT ====='
pkill -TERM -u egor -f 'pacat --playback --raw --device=Diag-Sink' 2>/dev/null || true
sleep .3
pgrep -a -u egor pacat || echo DIAG_PACAT_CLEAN=yes

cp -a "$conf" "$backup"
echo "BACKUP=$backup"

python3 - <<'PY'
p='/home/egor/.config/speech-dispatcher/speechd.conf'
s=open(p,encoding='utf-8').read().splitlines()
out=[]
found=False
for line in s:
    stripped=line.lstrip()
    if stripped.startswith('AudioPulseMinLength') or stripped.startswith('#AudioPulseMinLength'):
        if not found:
            out.append('AudioPulseMinLength 40')
            found=True
        continue
    out.append(line)
if not found:
    out.append('AudioPulseMinLength 40')
open(p,'w',encoding='utf-8').write('\n'.join(out)+'\n')
PY
chown egor:egor "$conf"

echo '===== NEW CONFIG ====='
nl -ba "$conf"
grep -q '^AudioPulseMinLength[[:space:]]\+40$' "$conf"

before=$(journalctl -u egor-desktop.service --since today --no-pager 2>/dev/null | grep -c 'asyncq.c: q overrun' || true)
echo "OVERRUN_BEFORE=$before"
old_orca=$(pgrep -u egor -x orca | while read -r p; do [ "$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)" != Z ] && echo "$p"; done | tail -1)
old_spd=$(pgrep -u egor -x speech-dispatcher | head -1 || true)
old_rhv=$(pgrep -u egor -x sd_rhvoice | head -1 || true)
echo "OLD_ORCA=$old_orca OLD_SPEECHD=$old_spd OLD_RHVOICE=$old_rhv"

restart_speech
sleep 1
new_spd=$(pgrep -u egor -x speech-dispatcher | head -1)
new_rhv=$(pgrep -u egor -x sd_rhvoice | head -1)
new_orca=$(pgrep -u egor -x orca | while read -r p; do [ "$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)" != Z ] && echo "$p"; done | tail -1)
[ -n "$new_spd" ] && [ -n "$new_rhv" ] && [ -n "$new_orca" ]
[ "$new_orca" = "$old_orca" ]
echo "NEW_ORCA=$new_orca NEW_SPEECHD=$new_spd NEW_RHVOICE=$new_rhv"

# Wake the module with a short phrase so Pulse exposes the negotiated buffering.
pe spd-say -w 'Проверка буфера.' >/tmp/spd-say-test.out 2>/tmp/spd-say-test.err || true
sleep .3

echo '===== RHVOICE REQUESTED LATENCY AFTER ====='
lat=$(pe pacmd list-sink-inputs | awk '/client: .*<RHVoice>/ {rh=1} rh && /requested latency:/ {print $3; exit}')
echo "RHVOICE_REQUESTED_LATENCY_MS=$lat"
python3 - "$lat" <<'PY'
import sys
v=float(sys.argv[1])
if not (8.0 <= v <= 12.0):
    raise SystemExit(f'unexpected requested latency {v} ms')
PY

pe pacmd list-sink-inputs | awk '/client: .*<RHVoice>/ {rh=1} rh && /current latency:|requested latency:|sample spec:|client:/ {print}'
pe pacmd list-sinks | awk '/name: <Xpra-Speaker>/ {hit=1} hit && /current latency:|configured latency:/ {print} hit && /index:/ && seen {exit} hit {seen=1}'

# Exercise speech repeatedly, then check whether new Pulse overruns appear.
for i in $(seq 1 8); do
  pe spd-say -w 'Раз два три четыре пять. Проверяем стабильность речи после увеличения звукового буфера.' >/dev/null 2>&1 || true
done
sleep 1
after=$(journalctl -u egor-desktop.service --since today --no-pager 2>/dev/null | grep -c 'asyncq.c: q overrun' || true)
echo "OVERRUN_AFTER=$after"
echo "OVERRUN_DELTA=$((after-before))"

echo '===== FINAL PROCESSES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,%cpu=,comm=,args= | grep -E '[o]rca|[s]peech-dispatcher|[s]d_rhvoice|[p]arec' || true

trap - ERR
echo SPEECH_PULSE_BUFFER_40_LIVE=yes
