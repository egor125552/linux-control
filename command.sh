#!/usr/bin/env bash
set -euo pipefail
echo '=== SONNISS STATUS ==='
systemctl is-active zeroline-sonniss.service || true
systemctl show zeroline-sonniss.service -p ExecMainStatus -p Result -p ActiveState -p SubState --no-pager || true
if [ -f /srv/zero-line-audio/sonniss-2026/status.json ]; then
  cat /srv/zero-line-audio/sonniss-2026/status.json
else
  echo 'No status file'
fi
echo '=== FILE COUNTS ==='
find /srv/zero-line-audio/sonniss-2026/mp3 -type f -iname '*.mp3' 2>/dev/null | wc -l || true
du -sh /srv/zero-line-audio/sonniss-2026 2>/dev/null || true
df -h /srv/zero-line-audio/sonniss-2026 || true
echo '=== RECENT LOG ==='
journalctl -u zeroline-sonniss.service -n 22 --no-pager -o cat || true
