#!/usr/bin/env bash
set -euo pipefail
export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'

echo '===== PROCESSES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -E '[s]peech-dispatch|[s]d_rhvoice|[o]rca|[p]ulseaudio' || true

echo '===== ENV SPEECHD / RHVOICE ====='
for p in $(pgrep -u egor -f '^/usr/bin/speech-dispatcher( |$)' || true) $(pgrep -u egor -x sd_rhvoice || true); do
  echo "--- PID $p ---"
  tr '\0' '\n' </proc/$p/environ 2>/dev/null | grep -E '^(HOME|XDG_RUNTIME_DIR|DISPLAY|PULSE_SERVER|PULSE_COOKIE|LANG|LC_)=' | sort || true
done

echo '===== PULSE ACCESS AS EGOR ====='
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl info
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list short sinks

echo '===== SPEECH LOGS ====='
find /run/egor-desktop/speech-dispatcher/log -maxdepth 2 -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %p\n' | sort | tail -n 30
for f in /run/egor-desktop/speech-dispatcher/log/rhvoice.log /run/egor-desktop/speech-dispatcher/log/speech-dispatcher.log; do
  [ -r "$f" ] || continue
  echo "--- $f ---"
  tail -n 220 "$f"
done

echo '===== CURRENT PULSE CLIENTS / INPUTS ====='
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list clients | sed -n '/application.name = "RHVoice"/,+16p' || true
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list sink-inputs | sed -n '/application.name = "RHVoice"/,+20p' || true

echo '===== DIRECT RHVOICE MODULE CONFIG ====='
nl -ba /etc/speech-dispatcher/modules/rhvoice.conf | sed -n '1,260p'

echo DONE
