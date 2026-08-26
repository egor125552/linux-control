#!/usr/bin/env bash
set -euo pipefail
BASE=/opt/orca-51/lib/python3/dist-packages/orca

echo '===== RETRY CODE ====='
grep -nE 'Scheduling BrlAPI retry|retry.*BrlAPI|Attempting connection with BrlAPI|BrlAPI Connection is unavailable' "$BASE/braille.py" "$BASE/braille_presenter.py" || true

echo '===== BRAILLE INIT BLOCKS ====='
grep -nE '^def .*braille|^    def .*braille|initialize|retry' "$BASE/braille.py" | tail -120 || true
sed -n '1880,2025p' "$BASE/braille.py" 2>/dev/null || true
sed -n '1810,1855p' "$BASE/braille_presenter.py" 2>/dev/null || true
