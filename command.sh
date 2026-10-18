#!/usr/bin/env bash
set -u
echo '===== RDC SERVICE SETTINGS ====='
systemctl show desktop-commander-remote.service -p User -p ExecStart -p Restart -p WorkingDirectory -p StandardOutput -p ActiveState --no-pager
echo '===== CREDENTIAL PRESENCE ====='
for f in /root/.desktop-commander-device/device.json /home/egor/.desktop-commander-device/device.json; do [ ! -e "$f" ] || echo "Present: $f"; done
echo '===== DONE ====='
