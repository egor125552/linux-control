#!/usr/bin/env bash
set -euo pipefail
BASE=/srv/zero-line-audio/sonniss-2026
echo "SERVICE=$(systemctl is-active zeroline-sonniss.service || true)"
cat "$BASE/status.json" 2>/dev/null || true
echo "MP3_COUNT=$(find "$BASE/mp3" -type f -iname '*.mp3' 2>/dev/null | wc -l)"
echo "PARTIALS:"
ls -lh "$BASE"/part-*.partial "$BASE"/part-*.zip 2>/dev/null || true
echo "RECENT:"
journalctl -u zeroline-sonniss.service -n 8 --no-pager -o cat || true
