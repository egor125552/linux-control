#!/usr/bin/env bash
set -euo pipefail
echo "SERVICE=$(systemctl is-active zeroline-sonniss.service || true)"
if [ -f /srv/zero-line-audio/sonniss-2026/status.json ]; then
  cat /srv/zero-line-audio/sonniss-2026/status.json
fi
echo "MP3_COUNT=$(find /srv/zero-line-audio/sonniss-2026/mp3 -type f -iname '*.mp3' 2>/dev/null | wc -l)"
du -sh /srv/zero-line-audio/sonniss-2026 2>/dev/null || true
journalctl -u zeroline-sonniss.service -n 12 --no-pager -o cat || true
