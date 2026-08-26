#!/usr/bin/env bash
set -euo pipefail
cd /opt/orca-51

echo '===== REPO ====='
pwd
git status --short --branch 2>/dev/null || true
git log -5 --oneline 2>/dev/null || true
printf 'python files: '; find . -type f -name '*.py' | wc -l
printf 'python LOC: '; find . -type f -name '*.py' -print0 | xargs -0 cat | wc -l

echo '===== TOP LEVEL ====='
find . -maxdepth 2 -type d | sort | head -100

echo '===== BIGGEST PYTHON FILES ====='
find . -type f -name '*.py' -printf '%s %p\n' | sort -nr | head -30

echo '===== ORCA PACKAGE ====='
find src -maxdepth 3 -type f -name '*.py' 2>/dev/null | sort | head -160

echo '===== ENTRY / EVENT / SPEECH SYMBOLS ====='
grep -RniE 'class (Orca|EventManager|Speech|ScriptManager)|def (main|start|run|activate|process|enqueue|presentMessage|speak|_process)' src/orca 2>/dev/null | head -220 || true

echo '===== IMPORT / MAIN ENTRY ====='
grep -RniE 'GLib\.MainLoop|Gtk\.main|Atspi|pyatspi|EventManager|event_manager|speech\.speak|script_manager' src/orca 2>/dev/null | head -260 || true

echo '===== LIKELY HOT PATTERNS ====='
printf 'getattr calls: '; grep -Rho 'getattr(' src/orca --include='*.py' | wc -l
printf 'try blocks: '; grep -Rho '^[[:space:]]*try:' src/orca --include='*.py' | wc -l
printf 'list comprehensions: '; grep -Rho '\[[^]]* for [^]]*\]' src/orca --include='*.py' | wc -l || true
printf 'sleep calls: '; grep -RniE 'time\.sleep|GLib\.timeout_add' src/orca --include='*.py' | wc -l

echo '===== LIVE ORCA ====='
pid=$(pgrep -n -f '(^|/)orca( |$)' || true)
echo "pid=$pid"
if [ -n "$pid" ]; then
  ps -p "$pid" -o pid,ppid,user,%cpu,%mem,rss,vsz,etime,cmd
  readlink -f "/proc/$pid/exe" || true
  tr '\0' '\n' < "/proc/$pid/environ" | grep -E '^(PYTHONPATH|PATH|XDG|DISPLAY|DBUS|GI_TYPELIB)' | head -50 || true
fi

echo '===== CORE FILE EXCERPTS ====='
for f in src/orca/orca.py src/orca/event_manager.py src/orca/script_manager.py src/orca/speech.py src/orca/script.py; do
  if [ -f "$f" ]; then
    echo "--- $f ---"
    sed -n '1,260p' "$f" | head -260
  fi
done
