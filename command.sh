#!/usr/bin/env bash
set -euo pipefail

echo '===== LIVE ORCA ====='
ps -u egor -o pid=,ppid=,stat=,comm=,etimes=,args= | grep '[o]rca' || true

echo '===== DEBUG STARTUP / EXTENSION LINES ====='
grep -nEi 'EXTENSION LOADER|user extension|egor_desktop|Traceback|ImportError|ModuleNotFoundError|AttributeError|TypeError|Exception|ERROR|CRITICAL' /home/egor/.local/state/orca/orca-debug.log 2>/dev/null | tail -n 260 || true

echo '===== DEBUG HEAD ====='
sed -n '1,320p' /home/egor/.local/state/orca/orca-debug.log 2>/dev/null | tail -n 320 || true

echo '===== RESTART STDERR ====='
cat /home/egor/.local/state/orca/voiceover-cursor-restart.log 2>/dev/null || true

echo '===== LOADER DISCOVERY IMPLEMENTATION ====='
sed -n '205,325p' /opt/orca-51/lib/python3/dist-packages/orca/extension_loader.py
sed -n '760,825p' /opt/orca-51/lib/python3/dist-packages/orca/extension_loader.py

echo ORCA_LOADER_FAILURE_READ=yes
