#!/usr/bin/env bash
set -euo pipefail
BASE=/srv/zero-line-audio/sonniss-2026
"$BASE/tools/venv/bin/gdown" --version || true
echo "=== TEST URL ==="
"$BASE/tools/venv/bin/gdown" --fuzzy "https://drive.google.com/file/d/1ndDWhCoq0NgkrJH6ku5MSA65zinEby9r/view?usp=sharing" -O /tmp/sonniss-test.partial || true
ls -lh /tmp/sonniss-test.partial 2>/dev/null || true
file /tmp/sonniss-test.partial 2>/dev/null || true
echo "=== JOURNAL ==="
journalctl -u zeroline-sonniss.service -n 40 --no-pager -o cat || true
