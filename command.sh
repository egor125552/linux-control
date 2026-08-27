#!/usr/bin/env bash
set -euo pipefail

echo '===== LAUNCHER ====='
sed -n '1,240p' /usr/local/bin/orca-egor-launcher

echo '===== AUTOSTART ====='
cat /home/egor/.config/autostart/orca-autostart.desktop 2>/dev/null || true

echo '===== LIVE ORCA PROCESSES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep '[o]rca' || true

for p in $(pgrep -u egor -x orca || true); do
  st=$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)
  echo "PID=$p STATE=$st"
  [ "$st" = Z ] && continue
  echo 'ENV_PATHS:'
  tr '\0' '\n' </proc/$p/environ 2>/dev/null | grep -E '^(PATH|PYTHONPATH|GI_TYPELIB_PATH|LD_LIBRARY_PATH|GSETTINGS_SCHEMA_DIR)=' || true
  echo 'OPEN_ORCA_FILES:'
  lsof -p "$p" 2>/dev/null | grep -E '/opt/orca-51|/usr/lib/python3/dist-packages/orca' | head -120 || true
  echo 'PROC_MAPS:'
  grep -E '/opt/orca-51|/usr/lib/python3/dist-packages/orca' /proc/$p/maps 2>/dev/null | head -80 || true
done

echo '===== SYSTEM ORCA FILE ====='
readlink -f /usr/bin/orca || true
head -n 4 /usr/bin/orca 2>/dev/null || true

echo ORCA51_VERIFY_DONE=yes
