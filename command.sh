#!/usr/bin/env bash
set -euo pipefail

echo '===== ORCA PROCESS STATES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep '[o]rca' || true

echo '===== DEBUG CONTENT ====='
cat /home/egor/.local/state/orca/virtual-cursor-debug.log 2>/dev/null || true

echo '===== STDERR ====='
cat /home/egor/.local/state/orca/virtual-cursor-debug-stderr.log 2>/dev/null || true

echo '===== OTHER_ORCAS / CLEANUP SOURCE ====='
for name in 'def other_orcas' 'def cleanup'; do
  n=$(grep -n "$name" /opt/orca-51/bin/orca | head -1 | cut -d: -f1 || true)
  if [ -n "$n" ]; then echo "--- $name at $n"; sed -n "$n,$((n+110))p" /opt/orca-51/bin/orca; fi
done

echo '===== ZOMBIE PARENT ====='
z=$(ps -u egor -o pid=,stat= | awk '$2 ~ /^Z/ {print $1; exit}')
if [ -n "${z:-}" ]; then
  ppid=$(ps -o ppid= -p "$z" | xargs || true)
  echo "ZOMBIE=$z PARENT=$ppid"
  ps -o pid=,ppid=,stat=,etimes=,comm=,args= -p "$z" -p "$ppid" 2>/dev/null || true
  [ -n "$ppid" ] && pstree -aps "$ppid" 2>/dev/null || true
fi

echo ORCA_CLEANUP_INSPECT_DONE=yes
