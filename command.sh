#!/usr/bin/env bash
set -euo pipefail

echo '===== ORCA PROCESS CGROUPS ====='
for p in 92481 92483 92486; do
  if [ -r "/proc/$p/cgroup" ]; then
    echo "PID=$p"
    cat "/proc/$p/cgroup"
  fi
done

echo '===== SYSTEMD MATCHES ====='
systemctl --no-pager --all --type=service | grep -Ei 'orca|egor|xpra' || true

echo '===== USER UNITS ====='
runuser -u egor -- systemctl --user --no-pager --all --type=service 2>&1 | grep -Ei 'orca|speech|xpra' || true

echo '===== START COMMAND REFERENCES ====='
grep -Rns --exclude='*.log' --exclude-dir='.cache' 'orca-egor-launcher' /etc/systemd /home/egor/.config/systemd /usr/local/bin /etc/xdg/autostart /home/egor/.config/autostart 2>/dev/null || true
