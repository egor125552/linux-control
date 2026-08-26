#!/usr/bin/env bash
set -euo pipefail
BASE=/opt/orca-51/lib/python3/dist-packages/orca
FILE="$BASE/braille_presenter.py"
BACKUP=/root/braille_presenter.py.before-disable-final
cp -a "$FILE" "$BACKUP"

python3 - <<'PY'
from pathlib import Path
p = Path('/opt/orca-51/lib/python3/dist-packages/orca/braille_presenter.py')
s = p.read_text()
old1 = '''    @gsettings_registry.get_registry().gsetting(
        key=KEY_ENABLED,
        schema="braille",
        gtype="b",
        default=True,
        summary="Enable braille output",
        migration_key="enableBraille",
    )
'''
new1 = '''    @gsettings_registry.get_registry().gsetting(
        key=KEY_ENABLED,
        schema="braille",
        gtype="b",
        default=False,
        summary="Enable braille output",
        migration_key="enableBraille",
    )
'''
old2 = '''        return self._get_setting(self.KEY_ENABLED, "b", True)
'''
new2 = '''        return self._get_setting(self.KEY_ENABLED, "b", False)
'''
if old1 not in s:
    raise SystemExit('braille decorator block not found')
if old2 not in s:
    raise SystemExit('braille getter fallback not found')
s = s.replace(old1, new1, 1).replace(old2, new2, 1)
p.write_text(s)
PY

python3 -m py_compile "$FILE"
echo '===== PATCHED BRAILLE SETTING ====='
sed -n '824,842p' "$FILE"

START=$(date '+%Y-%m-%d %H:%M:%S')
systemctl restart egor-desktop.service
for i in $(seq 1 25); do pgrep -x orca >/dev/null && break; sleep 1; done
if ! pgrep -x orca >/dev/null; then
  echo 'ERROR: Orca missing; restoring backup'
  cp -a "$BACKUP" "$FILE"
  systemctl restart egor-desktop.service
  exit 3
fi
sleep 12

echo '===== ORCA PROCESS ====='
pgrep -a -x orca

echo '===== NEW BRAILLE RETRIES AFTER RESTART ====='
awk -v start="$START" '1' /home/egor/.local/state/orca/orca-debug.log 2>/dev/null | tail -220 | grep -Ei 'BrlAPI|Braille initialization failed|Scheduling BrlAPI retry|braille/enabled' || true

echo '===== SPEECH HEALTH ====='
pgrep -a -f 'speech-dispatcher|sd_rhvoice' || true
systemctl is-active egor-desktop.service
systemctl is-active audio-remote.service

echo '===== XBRLAPI PACKAGE ====='
dpkg-query -W -f='${Package} ${Status}\n' xbrlapi 2>/dev/null || echo 'xbrlapi: removed'
