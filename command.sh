#!/usr/bin/env bash
set -euo pipefail
BASE=/opt/orca-51/lib/python3/dist-packages/orca

echo '===== FIND BRAILLE SETTING KEYS ====='
grep -RniE 'braille.*enabled|enabled.*braille|enableBraille|brailleEnabled' "$BASE" | head -80 || true

echo '===== USER ORCA CONFIG FILES ====='
find /home/egor -maxdepth 4 -type f \( -iname '*orca*' -o -path '*/orca/*' \) -print 2>/dev/null | head -120 || true

echo '===== XBRLAPI REMOVE SIMULATION ====='
apt-get -s remove --purge xbrlapi || true

echo '===== REMOVE XBRLAPI ONLY ====='
DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y xbrlapi

echo '===== FORCE BRAILLE OFF IN ORCA USER SETTINGS IF PRESENT ====='
python3 - <<'PY'
from pathlib import Path
candidates = [
    Path('/home/egor/.local/share/orca/user-settings.conf'),
    Path('/home/egor/.config/orca/user-settings.conf'),
]
for p in candidates:
    if not p.exists():
        continue
    s = p.read_text(errors='ignore')
    old = s
    # Common Orca preference spellings across versions.
    import re
    s = re.sub(r'(?m)^(\s*["\']?enableBraille["\']?\s*[:=]\s*)True\b', r'\1False', s)
    s = re.sub(r'(?m)^(\s*["\']?brailleEnabled["\']?\s*[:=]\s*)True\b', r'\1False', s)
    if s != old:
        backup = p.with_suffix(p.suffix + '.before-braille-disable')
        backup.write_text(old)
        p.write_text(s)
        print('patched', p)
PY

echo '===== RESTART DESKTOP ====='
systemctl restart egor-desktop.service
for i in $(seq 1 25); do pgrep -x orca >/dev/null && break; sleep 1; done
pgrep -a -x orca || { echo 'ERROR: Orca missing'; exit 3; }

echo '===== WAIT AND CHECK BRAILLE RETRIES ====='
sleep 12
tail -160 /home/egor/.local/state/orca/orca-debug.log 2>/dev/null | grep -Ei 'BRAILLE|BrlAPI' || true

echo '===== SPEECH HEALTH ====='
pgrep -a -f 'speech-dispatcher|sd_rhvoice' || true
systemctl is-active egor-desktop.service
systemctl is-active audio-remote.service

echo '===== REMAINING BRAILLE PACKAGES ====='
dpkg-query -W -f='${Package}\t${Status}\t${Version}\n' 2>/dev/null | grep -Ei 'brltty|brlapi|braille' || true
