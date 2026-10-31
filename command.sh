#!/usr/bin/env bash
set -euo pipefail
BASE=/srv/zero-line-audio/sonniss-2026
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/141 Safari/537.36'
python3 - <<'PY'
from pathlib import Path
p=Path("/srv/zero-line-audio/sonniss-2026/convert_all.py")
s=p.read_text()
old='subprocess.run([str(GDOWN),fid,"-O",str(partial)],check=True)'
new='subprocess.run(["wget","--timeout=30","--tries=20","--continue","--user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/141 Safari/537.36","--referer=https://gdc.sonniss.com/","-O",str(partial),f"https://downloads.sonniss.com/Sonniss.com-GDC2026-GameAudioBundle{part}of5.zip"],check=True)'
if old not in s:
    raise SystemExit("Expected download line not found")
s=s.replace(old,new)
p.write_text(s)
print("DOWNLOAD_METHOD=wget")
PY
rm -f "$BASE/tests/curl-range.bin" "$BASE/tests/wget-range.bin" "$BASE/tests/gdrive.bin" "$BASE/tests/gcookie.txt" "$BASE/tests/sonniss.torrent" 2>/dev/null || true
systemctl stop zeroline-sonniss.service 2>/dev/null || true
systemctl reset-failed zeroline-sonniss.service 2>/dev/null || true
systemd-run --unit=zeroline-sonniss --description="Sonniss 2026 all 5 parts to MP3" --property=WorkingDirectory="$BASE" /usr/bin/python3 "$BASE/convert_all.py"
sleep 5
echo "SERVICE=$(systemctl is-active zeroline-sonniss.service || true)"
cat "$BASE/status.json" 2>/dev/null || true
ls -lh "$BASE"/part-*.partial "$BASE"/part-*.zip 2>/dev/null || true
journalctl -u zeroline-sonniss.service -n 10 --no-pager -o cat || true
