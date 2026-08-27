#!/usr/bin/env bash
set -euo pipefail
export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'

echo '===== C LOCALE SHORT SINKS/SOURCES ====='
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list short sinks
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list short sources
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list short sink-inputs
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list short source-outputs

echo '===== C LOCALE FULL SPECS ====='
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list sinks | sed -n '/Name: Xpra-Speaker/,/Formats:/p'
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list sources | sed -n '/Name: Xpra-Speaker.monitor/,/Formats:/p'

echo '===== RAW SHORT OUTPUT HEX ====='
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list short sinks | od -An -tx1c

echo '===== JSON IF SUPPORTED ====='
if runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl --format=json list sinks >/tmp/sinks.json 2>/tmp/json.err; then
  python3 - <<'PY'
import json
x=json.load(open('/tmp/sinks.json'))
for s in x:
    if s.get('name')=='Xpra-Speaker':
        print(json.dumps({k:s.get(k) for k in ('name','sample_specification','state','latency','configured_latency')}, ensure_ascii=False, indent=2))
PY
else
  cat /tmp/json.err || true
fi

echo '===== SERVER INFO ====='
runuser -u egor -- env LC_ALL=C LANG=C PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl info

echo DONE
