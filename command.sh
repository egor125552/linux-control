#!/usr/bin/env bash
set -euo pipefail

echo '===== ORCA SPEECHDISPATCHERFACTORY LOCATION ====='
python3 - <<'PY'
import inspect, orca.speechdispatcherfactory as m
print(inspect.getsourcefile(m))
PY

file=$(python3 - <<'PY'
import inspect, orca.speechdispatcherfactory as m
print(inspect.getsourcefile(m))
PY
)

echo '===== MARK / CALLBACK RELATED SOURCE ====='
grep -nE 'mark|callback|speak\(|cancel|stop|index|SSML|CallbackType' "$file" | head -260 || true

echo '===== SPEAK IMPLEMENTATION CONTEXT ====='
start=$(grep -n 'def speak' "$file" | head -1 | cut -d: -f1 || true)
if [ -n "$start" ]; then
  a=$((start-30)); [ "$a" -lt 1 ] && a=1
  b=$((start+180))
  sed -n "${a},${b}p" "$file"
fi

echo '===== CUSTOM EXTENSION CORE ====='
sed -n '1,320p' /home/egor/.local/share/orca/extensions/egor_desktop_accessibility/core.py 2>/dev/null || true

echo '===== USER SETTINGS VOICES CONTEXT ====='
python3 - <<'PY'
import json
p='/home/egor/.local/share/orca/user-settings.conf'
try:
    d=json.load(open(p,encoding='utf-8'))
except Exception as e:
    print('JSON_READ_ERROR',e); raise SystemExit
# Print only speech-related non-secret settings.
for k,v in d.items():
    if any(x in k.lower() for x in ('speech','voice','punct','rate','pitch','gain','interrupt')):
        print(k,repr(v))
PY

echo ORCA_MARK_SOURCE_INSPECT_DONE=yes
