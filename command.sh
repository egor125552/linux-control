#!/usr/bin/env bash
set -euo pipefail

echo '===== LOCATE EGOR ACCESSIBILITY CODE ====='
grep -Rni --exclude='*.log' --exclude-dir='.cache' --exclude-dir='.git' \
  -E 'EGOR ACCESSIBILITY|_check_navigation_result|_desktop_signature|spoke .пусто.|changed nothing' \
  /home/egor/.local /home/egor/.config /opt/orca-51 /usr/local 2>/dev/null | head -240 || true

echo '===== ORCA USER EXTENSION FILES ====='
find /home/egor/.local/share/orca /home/egor/.config/orca -maxdepth 5 -type f -printf '%p\n' 2>/dev/null | sort | head -240 || true

echo '===== POSSIBLE CUSTOM PYTHON FILES ====='
for f in $(grep -RIl --exclude='*.log' --exclude-dir='.cache' --exclude-dir='.git' \
  -E 'EGOR ACCESSIBILITY|_check_navigation_result|_desktop_signature' \
  /home/egor/.local /home/egor/.config /usr/local 2>/dev/null | head -20); do
  echo "--- FILE $f"
  sed -n '1,520p' "$f" || true
done

echo LOCATE_EGOR_ORCA_CODE_DONE=yes
