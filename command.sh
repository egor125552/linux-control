#!/usr/bin/env bash
set -euo pipefail

echo '===== ORCA TREE ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -E '[o]rca|[s]peech-dispatch|[s]d_rhvoice|[a]t-spi' || true
orca=$(pgrep -u egor -x orca | while read -r p; do [ "$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)" != Z ] && echo "$p"; done | tail -1)
echo ORCA=$orca
if [ -n "$orca" ]; then
  pp=$(ps -o ppid= -p "$orca" | tr -d ' ')
  echo ORCA_PARENT=$pp
  ps -fp "$pp" || true
  tr '\0' ' ' </proc/$pp/cmdline 2>/dev/null; echo
fi

echo '===== LAUNCHER ====='
ls -l /usr/local/bin/orca-egor-launcher 2>/dev/null || true
sed -n '1,320p' /usr/local/bin/orca-egor-launcher 2>/dev/null || true

echo '===== DESKTOP SERVICE / ORCA REFERENCES ====='
systemctl cat egor-desktop.service | sed -n '1,300p'
grep -RnsE 'orca-egor-launcher|orca( |$)|speech-dispatcher' /usr/local/bin /etc/systemd/system 2>/dev/null | head -n 320 || true

echo DONE
