#!/usr/bin/env bash
set -euo pipefail

echo '===== CURRENT CONFIG ====='
nl -ba /home/egor/.config/speech-dispatcher/speechd.conf

echo '===== SPEECH PROCESSES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -E '[s]peech-dispatch|[s]d_rhvoice|[o]rca' || true

echo '===== MATCHED SPEECHD PIDS ====='
pgrep -a -u egor -f '^/usr/bin/speech-dispatcher( |$)' || true
pgrep -a -u egor -x sd_rhvoice || true

echo '===== SOCKET FILE ====='
ls -l /run/egor-desktop/speech-dispatcher/speechd.sock 2>&1 || true

echo '===== SOCKET OWNER ====='
ss -xlpn 2>/dev/null | grep '/run/egor-desktop/speech-dispatcher/speechd.sock' || true

echo '===== SPEECHD TEST ====='
runuser -u egor -- env HOME=/home/egor XDG_RUNTIME_DIR=/run/egor-desktop DISPLAY=:100 \
  PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native' \
  PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE' \
  timeout 5 spd-say -w 'Проверка связи речевого сервера.' >/tmp/state-spd.out 2>/tmp/state-spd.err || true
cat /tmp/state-spd.err || true

echo '===== RHVOICE PULSE INPUT ====='
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native' PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE' pactl list sink-inputs | sed -n '/application.name = "RHVoice"/,+12p' || true

echo DONE
