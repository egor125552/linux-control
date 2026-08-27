#!/usr/bin/env bash
set -euo pipefail

export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
pe() { runuser -u egor -- env PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"; }

conf=/etc/xpra/pulse/xpra.pa
stamp=$(date +%Y%m%d-%H%M%S)
backup="$conf.before-rate-fix-$stamp"

echo '===== BEFORE CONFIG ====='
grep -nE 'Xpra-Speaker|Xpra-Microphone' "$conf"
grep -q 'sink_name=Xpra-Speaker.*rate=4800 channels=2' "$conf"
grep -q 'sink_name=Xpra-Microphone.*rate=4410 channels=2' "$conf"
cp -a "$conf" "$backup"
echo "BACKUP=$backup"

python3 - <<'PY'
p='/etc/xpra/pulse/xpra.pa'
s=open(p, encoding='utf-8').read()
a='rate=4800 channels=2'
b='rate=4410 channels=2'
if s.count(a) != 1:
    raise SystemExit(f'expected exactly one {a}, got {s.count(a)}')
if s.count(b) != 1:
    raise SystemExit(f'expected exactly one {b}, got {s.count(b)}')
s=s.replace(a, 'rate=48000 channels=2', 1)
s=s.replace(b, 'rate=44100 channels=2', 1)
open(p, 'w', encoding='utf-8').write(s)
PY

echo '===== AFTER CONFIG ====='
grep -nE 'Xpra-Speaker|Xpra-Microphone' "$conf"
grep -q 'sink_name=Xpra-Speaker.*rate=48000 channels=2' "$conf"
grep -q 'sink_name=Xpra-Microphone.*rate=44100 channels=2' "$conf"

speaker_mod=$(pe pactl list modules | awk '
  /^Модуль #/ {id=$2; sub(/^#/,"",id)}
  /^Module #/ {id=$2; sub(/^#/,"",id)}
  /sink_name=Xpra-Speaker/ {print id; exit}
')
if [ -z "$speaker_mod" ]; then
  echo 'SPEAKER_MODULE_NOT_FOUND'
  cp -a "$backup" "$conf"
  exit 1
fi

echo "OLD_SPEAKER_MODULE=$speaker_mod"
echo '===== BEFORE LIVE SINK ====='
pe pactl list short sinks | grep 'Xpra-Speaker' || true
pe pactl list short source-outputs | grep 'Xpra-Speaker.monitor' || true

rollback() {
  rc=$?
  trap - ERR
  echo "ROLLBACK_AFTER_ERROR=$rc"
  cp -a "$backup" "$conf" || true
  if ! pe pactl list short sinks | grep -q 'Xpra-Speaker'; then
    pe pactl load-module module-null-sink sink_name=Xpra-Speaker 'sink_properties=device.description=Xpra-Speaker' rate=4800 channels=2 || true
    pe pactl set-default-sink Xpra-Speaker || true
  fi
  exit "$rc"
}
trap rollback ERR

# Replace only the playback null sink live. This causes a very short audio interruption,
# but leaves Xpra, Orca, Speech Dispatcher and the desktop session running.
pe pactl unload-module "$speaker_mod"
new_mod=$(pe pactl load-module module-null-sink sink_name=Xpra-Speaker 'sink_properties=device.description=Xpra-Speaker' rate=48000 channels=2)
pe pactl set-default-sink Xpra-Speaker
sleep 2

echo "NEW_SPEAKER_MODULE=$new_mod"
echo '===== AFTER LIVE SINK ====='
pe pactl list short sinks | grep 'Xpra-Speaker'
pe pactl list short sources | grep 'Xpra-Speaker.monitor'
pe pactl list sinks | sed -n '/Имя: Xpra-Speaker/,/Форматы:/p' || pe pactl list sinks | sed -n '/Name: Xpra-Speaker/,/Formats:/p'

# Hard assertion: the live device must now really be 48 kHz.
pe pactl list short sinks | grep 'Xpra-Speaker' | grep -q '48000Hz'

trap - ERR

echo '===== ACCESSIBILITY STACK ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,%cpu=,comm=,args= | grep -E '[o]rca|[s]peech-dispatcher|[s]d_rhvoice|[p]arec' || true

echo '===== AUDIO REMOTE ====='
systemctl is-active audio-remote.service
systemctl show audio-remote.service -p MainPID --no-pager
sleep 1
pgrep -a -u egor parec || true

echo RATE_FIX_LIVE=yes
