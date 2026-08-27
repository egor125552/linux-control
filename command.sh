#!/usr/bin/env bash
set -euo pipefail

server='unix:/run/egor-desktop/xpra/100/pulse/native'
echo "PULSE_SERVER=$server"

if [ ! -S /run/egor-desktop/xpra/100/pulse/native ]; then
  echo PULSE_SOCKET_MISSING
  exit 1
fi

mapfile -t candidates < <(find /run/egor-desktop /home/egor/.config/pulse /home/egor/.pulse /tmp \
  -maxdepth 8 -type f -user egor -size 256c 2>/dev/null \
  | grep -Ei 'cookie' | sort -u)

echo "COOKIE_CANDIDATES=${#candidates[@]}"
working=''
for c in "${candidates[@]}"; do
  echo "TEST_COOKIE=$c"
  if runuser -u egor -- env HOME=/home/egor PULSE_SERVER="$server" PULSE_COOKIE="$c" pactl info >/tmp/pactl-test.out 2>/tmp/pactl-test.err; then
    echo COOKIE_WORKS=yes
    cat /tmp/pactl-test.out
    working="$c"
    break
  else
    echo COOKIE_WORKS=no
    tail -n 3 /tmp/pactl-test.err || true
  fi
done

if [ -z "$working" ]; then
  echo NO_WORKING_COOKIE
  exit 1
fi

echo "WORKING_COOKIE=$working"
echo '===== SINKS ====='
runuser -u egor -- env HOME=/home/egor PULSE_SERVER="$server" PULSE_COOKIE="$working" pactl list short sinks
