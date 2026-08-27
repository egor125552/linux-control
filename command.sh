#!/usr/bin/env bash
set -euo pipefail

echo '===== ORCA TREE ====='
ps -p 92481,92483,92486 -o pid=,ppid=,stat=,etimes=,comm=,args= || true

echo '===== PARENT CHAIN ====='
p=92486
for i in 1 2 3 4 5; do
  [ -r "/proc/$p/stat" ] || break
  ps -p "$p" -o pid=,ppid=,stat=,etimes=,comm=,args= || true
  p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null || echo 1)
  [ "$p" = 0 ] && break
done

echo '===== LAUNCHER ====='
sed -n '1,220p' /usr/local/bin/orca-egor-launcher
