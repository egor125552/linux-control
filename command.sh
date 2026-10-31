#!/usr/bin/env bash
set -euo pipefail
echo '=== REMOTE DESKTOP COMMANDER AUTH ==='
echo "HOST=$(hostname)"
echo '--- service before ---'
systemctl status desktop-commander-remote.service --no-pager -l || true
echo '--- cli help ---'
npx -y @wonderwhy-er/desktop-commander@latest remote --help 2>&1 | head -n 120 || true
echo '--- restart service ---'
systemctl restart desktop-commander-remote.service
sleep 6
echo '--- recent journal ---'
journalctl -u desktop-commander-remote.service --since '2 minutes ago' --no-pager -o cat | tail -n 220
