#!/usr/bin/env bash
set -euo pipefail
BASE=/srv/zero-line-audio/sonniss-2026
python3 - <<'PY'
from pathlib import Path
p=Path("/srv/zero-line-audio/sonniss-2026/convert_all.py")
s=p.read_text()
s=s.replace('subprocess.run([str(GDOWN),"--id",fid,"-O",str(partial)],check=True)',
            'subprocess.run([str(GDOWN),fid,"-O",str(partial)],check=True)')
p.write_text(s)
print("PATCHED")
PY
systemctl stop zeroline-sonniss.service 2>/dev/null || true
systemctl reset-failed zeroline-sonniss.service 2>/dev/null || true
systemd-run --unit=zeroline-sonniss --description="Sonniss 2026 all 5 parts to MP3" --property=WorkingDirectory="$BASE" /usr/bin/python3 "$BASE/convert_all.py"
sleep 3
echo "SERVICE=$(systemctl is-active zeroline-sonniss.service || true)"
cat "$BASE/status.json" 2>/dev/null || true
journalctl -u zeroline-sonniss.service -n 8 --no-pager -o cat || true
