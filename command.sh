#!/usr/bin/env bash
set -euo pipefail
live=''
for p in $(pgrep -u egor -x orca || true); do
  st=$(ps -o stat= -p "$p" 2>/dev/null | xargs || true)
  case "$st" in Z*) ;; *) live="$p"; break;; esac
done
[ -n "$live" ] || { echo LIVE_ORCA=no; exit 1; }

echo "LIVE_PID=$live"
echo '===== EXECUTABLE / CMDLINE ====='
readlink -f "/proc/$live/exe" || true
tr '\0' ' ' < "/proc/$live/cmdline" 2>/dev/null || true; echo

echo '===== LIVE ENV ====='
tr '\0' '\n' < "/proc/$live/environ" 2>/dev/null | grep -E '^(HOME|PATH|PYTHONPATH|LD_LIBRARY_PATH|GI_TYPELIB_PATH|GSETTINGS_SCHEMA_DIR|XDG_DATA_HOME|XDG_DATA_DIRS|DISPLAY|XDG_RUNTIME_DIR)=' || true

echo '===== MAPS / OPEN ORCA FILES ====='
grep -E '/opt/orca-51|/usr/lib/python3/dist-packages/orca|/home/egor/.local/share/orca' "/proc/$live/maps" 2>/dev/null | head -120 || true
if command -v lsof >/dev/null 2>&1; then
  lsof -p "$live" 2>/dev/null | grep -E '/opt/orca-51|/usr/lib/python3/dist-packages/orca|/home/egor/.local/share/orca' | head -180 || true
fi

echo '===== ENTRYPOINTS ====='
ls -l /opt/orca-51/bin/orca /usr/bin/orca 2>/dev/null || true
sed -n '1,90p' /opt/orca-51/bin/orca 2>/dev/null || true
echo '--- SYSTEM ---'
sed -n '1,60p' /usr/bin/orca 2>/dev/null || true

echo '===== VERSION COMMANDS ====='
env PYTHONPATH=/opt/orca-51/lib/python3/dist-packages GI_TYPELIB_PATH=/opt/orca-51/lib/x86_64-linux-gnu/girepository-1.0 LD_LIBRARY_PATH=/opt/orca-51/lib/x86_64-linux-gnu GSETTINGS_SCHEMA_DIR=/opt/orca-51/share/glib-2.0/schemas /opt/orca-51/bin/orca --version 2>&1 || true
/usr/bin/orca --version 2>&1 || true

echo '===== EXTENSION DIR ====='
find /home/egor/.local/share/orca/extensions -maxdepth 3 -type f -printf '%p\n' 2>/dev/null | sort || true

echo LIVE_ORCA_IDENTITY_DONE=yes
