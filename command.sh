#!/usr/bin/env bash
set -euo pipefail
BASE=/opt/orca-51/lib/python3/dist-packages/orca
FILE="$BASE/braille.py"
BACKUP=/root/braille.py.before-disable
cp -a "$FILE" "$BACKUP"

echo '===== STATE BEFORE ====='
sed -n '250,300p' "$FILE"
sed -n '430,475p' "$FILE"

python3 - <<'PY'
from pathlib import Path
p = Path('/opt/orca-51/lib/python3/dist-packages/orca/braille.py')
s = p.read_text()
old = '    enable_braille: bool = True\n'
new = '    enable_braille: bool = False\n'
if old not in s:
    raise SystemExit('enable_braille runtime default not found')
s = s.replace(old, new, 1)
p.write_text(s)
PY

python3 -m py_compile "$FILE"
echo '===== STATE AFTER ====='
grep -n 'enable_braille: bool' "$FILE"

systemctl restart egor-desktop.service
for i in $(seq 1 25); do pgrep -x orca >/dev/null && break; sleep 1; done
if ! pgrep -x orca >/dev/null; then
  echo 'ERROR: Orca missing; restoring braille.py'
  cp -a "$BACKUP" "$FILE"
  systemctl restart egor-desktop.service
  exit 3
fi
sleep 12

echo '===== ORCA ====='
pgrep -a -x orca

echo '===== BRAILLE RETRIES IN CURRENT LOG TAIL ====='
tail -120 /home/egor/.local/state/orca/orca-debug.log 2>/dev/null | grep -Ei 'Attempting connection with BrlAPI|Braille initialization failed|Scheduling BrlAPI retry' || true

echo '===== SPEECH ====='
pgrep -a -f 'speech-dispatcher|sd_rhvoice' || true
systemctl is-active egor-desktop.service
systemctl is-active audio-remote.service
