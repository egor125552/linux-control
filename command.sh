#!/usr/bin/env bash
set -euo pipefail
export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
pe() { runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" "$@"; }

echo '===== DIAG CLEANUP CHECK ====='
pe pactl list short sinks | grep 'Diag-Sink' || echo DIAG_SINK_ABSENT=yes
pgrep -a -u egor pacat || echo PACAT_ABSENT=yes

echo '===== USER SPEECHD CONFIG ====='
nl -ba /home/egor/.config/speech-dispatcher/speechd.conf

echo '===== LIVE SPEECH PIDS / COMMANDS ====='
ps -u egor -o pid=,ppid=,lstart=,stat=,comm=,args= | grep -E '[s]peech-dispatcher|[s]d_rhvoice|[o]rca' || true

echo '===== SPEECHD HELP ====='
speech-dispatcher --help 2>&1 | head -n 220 || true

echo '===== SOCKET ====='
ls -l /run/egor-desktop/speech-dispatcher 2>/dev/null || true
ss -xlpn | grep speechd 2>/dev/null || true

echo DONE
