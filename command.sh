#!/usr/bin/env bash
set -euo pipefail
export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
pe() { runuser -u egor -- env PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"; }

echo '===== CURRENT XPRA.PA EXACT ====='
stat /etc/xpra/pulse/xpra.pa
nl -ba /etc/xpra/pulse/xpra.pa

echo '===== XPRA.PA BACKUPS / NEIGHBORS ====='
find /etc/xpra/pulse -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %p\n' | sort
for f in /etc/xpra/pulse/xpra.pa*; do
  [ -f "$f" ] || continue
  echo "--- $f ---"
  grep -nE 'Xpra-Speaker|Xpra-Microphone|rate=' "$f" || true
done

echo '===== ACTIVE BAD MODULES EXACT ====='
pe pactl list modules | awk '
  /^Модуль #|^Module #/ {show=0; block=$0"\n"}
  {block=block $0"\n"}
  /sink_name=Xpra-Speaker|sink_name=Xpra-Microphone/ {show=1}
  /^$/ {if(show) printf "%s", block; block=""; show=0}
'

echo '===== PULSE PROCESS COMMAND ====='
for p in $(pgrep -u egor pulseaudio || true); do
  echo PID=$p
  tr '\0' ' ' </proc/$p/cmdline; echo
  echo START=$(ps -o lstart= -p "$p")
done

echo '===== XPRA MAIN COMMAND ====='
for p in $(pgrep -u egor -f 'xpra.*(start|seamless|desktop|server)' || true); do
  echo PID=$p
  tr '\0' ' ' </proc/$p/cmdline; echo
done

echo '===== EXACT BAD RATE SEARCH CONFIG ====='
for root in /etc /home/egor/.config /home/egor/.xpra /usr/local/bin /opt/audio-remote; do
  [ -e "$root" ] || continue
  echo ROOT=$root
  grep -RnsE --binary-files=without-match --exclude='*.pyc' --exclude='*.log' --exclude-dir=.venv \
    'rate=4800([^0-9]|$)|rate=4410([^0-9]|$)|4800Hz|4410Hz|Xpra-Speaker.*4800|Xpra-Microphone.*4410' "$root" 2>/dev/null | head -n 240 || true
done

echo '===== XPRA CODE SINK CREATION SEARCH ====='
for root in /usr/lib/python3/dist-packages/xpra /usr/share/xpra /usr/libexec/xpra; do
  [ -e "$root" ] || continue
  echo ROOT=$root
  grep -RnsE --binary-files=without-match --exclude='*.pyc' \
    'Xpra-Speaker|Xpra-Microphone|module-null-sink|load-module.*null-sink|pulseaudio.*configure|speaker.*rate|microphone.*rate' "$root" 2>/dev/null | head -n 420 || true
done

echo '===== STARTUP JOURNAL RATE/MODULE EVENTS ====='
journalctl -u egor-desktop.service --since today --no-pager 2>&1 | \
  grep -Ei 'pulse|Xpra-Speaker|Xpra-Microphone|null-sink|4800|4410|rate|module' | head -n 600 || true

echo '===== RECENT SHELL HISTORY RATE HITS ====='
for f in /root/.bash_history /home/egor/.bash_history; do
  [ -r "$f" ] || continue
  echo "--- $f ---"
  grep -nE '4800|4410|Xpra-Speaker|Xpra-Microphone|xpra.pa|null-sink' "$f" | tail -n 120 || true
done

echo DONE
