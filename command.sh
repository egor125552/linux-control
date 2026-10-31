#!/usr/bin/env bash
set -euo pipefail
systemctl stop desktop-commander-remote.service || true
/usr/local/bin/desktop-commander remote --logout || true
systemctl start desktop-commander-remote.service
sleep 8
echo '=== AUTH LOG ==='
journalctl -u desktop-commander-remote.service --since '2 minutes ago' --no-pager -o cat | tail -n 180
