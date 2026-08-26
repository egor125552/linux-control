#!/usr/bin/env bash
set -euo pipefail
BASE=/opt/orca-51/lib/python3/dist-packages/orca
FILE="$BASE/braille_presenter.py"
BACKUP=/root/braille_presenter.py.before-disable

cp -a "$FILE" "$BACKUP"

echo '===== BEFORE ====='
sed -n '815,850p' "$FILE"

python3 - <<'PY'
from pathlib import Path
p = Path('/opt/orca-51/lib/python3/dist-packages/orca/braille_presenter.py')
s = p.read_text()
old = '''    KEY_ENABLED = gsettings_registry.Setting(
        key="enabled",
        namespace="braille",
        default_value=True,
        migration_key="enableBraille",
    )
'''
new = '''    KEY_ENABLED = gsettings_registry.Setting(
        key="enabled",
        namespace="braille",
        default_value=False,
        migration_key="enableBraille",
    )
'''
if old not in s:
    raise SystemExit('Expected braille enabled setting block not found; refusing blind patch')
p.write_text(s.replace(old, new, 1))
PY

python3 -m py_compile "$FILE"

echo '===== AFTER ====='
sed -n '815,850p' "$FILE"

systemctl restart egor-desktop.service
for i in $(seq 1 25); do pgrep -x orca >/dev/null && break; sleep 1; done
pgrep -a -x orca || { echo 'ERROR: Orca missing; restoring backup'; cp -a "$BACKUP" "$FILE"; systemctl restart egor-desktop.service; exit 3; }

sleep 12

echo '===== NEW BRAILLE LOG ENTRIES ====='
tail -180 /home/egor/.local/state/orca/orca-debug.log 2>/dev/null | grep -Ei 'BRAILLE|BrlAPI|braille/enabled' || true

echo '===== SPEECH HEALTH ====='
pgrep -a -f 'speech-dispatcher|sd_rhvoice' || true
systemctl is-active egor-desktop.service
systemctl is-active audio-remote.service
