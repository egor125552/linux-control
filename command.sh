#!/usr/bin/env bash
set -euo pipefail

echo '===== ORCA PROCESSES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep '[o]rca' || true

echo '===== ORCA PROCESS TREES ====='
for p in $(pgrep -u egor -x orca || true); do
  echo "--- PID $p"
  pstree -aps "$p" 2>/dev/null || true
  printf 'state='; ps -o stat= -p "$p" 2>/dev/null | xargs || true
  printf 'exe='; readlink -f "/proc/$p/exe" 2>/dev/null || true
  echo 'selected-env:'
  tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -E '^(PULSE_SERVER|PULSE_COOKIE|PYTHONPATH|GSETTINGS_SCHEMA_DIR|DISPLAY|XDG_RUNTIME_DIR)=' | sed -E 's#^(PULSE_COOKIE)=.*#\1=<present>#' || true
done

echo '===== LAUNCHER CURRENT ====='
bash -n /usr/local/bin/orca-egor-launcher && echo LAUNCHER_SYNTAX=yes || echo LAUNCHER_SYNTAX=no
sed -n '1,90p' /usr/local/bin/orca-egor-launcher | sed -E 's#(PULSE_COOKIE=).*#\1<redacted>#' || true

echo '===== PULSE COOKIE RESTART LOG ====='
cat /home/egor/.local/state/orca/pulse-cookie-restart.log 2>/dev/null || true

echo '===== ORCA LAUNCHER LOG ====='
tail -n 100 /home/egor/.local/state/orca/orca-launcher.log 2>/dev/null || true

echo '===== SPEECH PROCESSES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -Ei 'speech-dispatcher|sd_rhvoice' || true

echo LIVE_ORCA_PATH_INSPECT_DONE=yes
