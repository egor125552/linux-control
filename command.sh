#!/usr/bin/env bash
set -euo pipefail
BASE=/opt/orca-51/lib/python3/dist-packages/orca
BACKUP=/root/orca51-backup-20260826-121208

echo '===== CURRENT SERVICES ====='
systemctl is-active egor-desktop.service || true
systemctl is-active audio-remote.service || true
pgrep -a -x orca || true
pgrep -a -f 'speech-dispatcher|sd_rhvoice' || true

echo '===== RECENT DESKTOP LOG ====='
journalctl -u egor-desktop.service --since '2026-08-26 12:12:00' --no-pager -n 180 || true

echo '===== DIRECT IMPORT CHECK ====='
set +e
PYTHONPATH=/opt/orca-51/lib/python3/dist-packages python3 - <<'PY'
try:
    import orca.script_manager
    import orca.event_manager
    print('imports: OK')
except Exception:
    import traceback
    traceback.print_exc()
    raise
PY
IMPORT_RC=$?
set -e

if [ "$IMPORT_RC" -ne 0 ]; then
  echo '===== IMPORT BROKEN: ROLLING BACK SCRIPT MANAGER ====='
  cp -a "$BACKUP/script_manager.py" "$BASE/script_manager.py"
  python3 -m py_compile "$BASE/script_manager.py" "$BASE/event_manager.py"
  systemctl restart egor-desktop.service
fi

echo '===== WAIT FOR ORCA ====='
for i in $(seq 1 20); do
  if pgrep -x orca >/dev/null; then
    break
  fi
  sleep 1
done

pid=$(pgrep -n -x orca || true)
if [ -z "$pid" ]; then
  echo 'Orca still absent; rolling back both modified files.'
  cp -a "$BACKUP/event_manager.py" "$BASE/event_manager.py"
  cp -a "$BACKUP/script_manager.py" "$BASE/script_manager.py"
  python3 -m py_compile "$BASE/event_manager.py" "$BASE/script_manager.py"
  systemctl restart egor-desktop.service
  for i in $(seq 1 20); do
    pgrep -x orca >/dev/null && break
    sleep 1
  done
  pid=$(pgrep -n -x orca || true)
fi

if [ -z "$pid" ]; then
  echo 'ERROR: Orca failed even after rollback.' >&2
  journalctl -u egor-desktop.service --since '2026-08-26 12:12:00' --no-pager -n 220 || true
  exit 4
fi

echo '===== ORCA HEALTH ====='
ps -p "$pid" -o pid,ppid,user,%cpu,%mem,rss,vsz,nlwp,etime,cmd
pgrep -a -f 'speech-dispatcher|sd_rhvoice' || true
systemctl is-active egor-desktop.service
systemctl is-active audio-remote.service

echo '===== ACTIVE PATCH STATE ====='
grep -nE 'app_hash|time.monotonic|_APP_NAME_MAP_CASEFOLD|_TOOLKIT_NAME_MAP' "$BASE/event_manager.py" "$BASE/script_manager.py" || true
