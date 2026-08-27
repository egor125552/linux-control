#!/usr/bin/env bash
set -euo pipefail

echo '===== CURRENT ACCESSIBILITY PROCESSES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,%cpu=,comm=,args= | grep -E '[o]rca|[s]peech-dispatch|[s]d_rhvoice|[a]t-spi' || true

echo '===== ORCA RESTART STDERR ====='
cat /tmp/orca-reconnect.err 2>/dev/null || true
echo '===== ORCA RESTART STDOUT ====='
cat /tmp/orca-reconnect.out 2>/dev/null || true

echo '===== ORCA DEBUG TAIL ====='
tail -n 240 /home/egor/.local/state/orca/orca-debug.log 2>/dev/null || true

echo '===== SESSION DBUS SOURCES ====='
for p in $(pgrep -u egor -f 'mate-panel|marco|caja|mate-session|at-spi2-registryd' || true); do
  echo "--- PID=$p $(ps -o comm= -p $p) ---"
  tr '\0' '\n' </proc/$p/environ 2>/dev/null | grep -E '^(DISPLAY|XAUTHORITY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|PULSE_SERVER)=' | sort || true
done

echo '===== DBUS SOCKETS ====='
ss -xlpn 2>/dev/null | grep -E '/tmp/dbus-|/run/user/.*/bus|/run/egor-desktop' | head -n 160 || true

echo '===== SPEECHD STATE ====='
ls -l /run/egor-desktop/speech-dispatcher/speechd.sock 2>/dev/null || true
pgrep -a -u egor -f '^/usr/bin/speech-dispatcher( |$)' || true
pgrep -a -u egor -x sd_rhvoice || true

echo DONE
