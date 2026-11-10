#!/usr/bin/env bash
set -u
echo '=== STOP REMOTE AGENT ==='
systemctl stop desktop-commander-remote.service
echo '=== LOGOUT ==='
timeout 20 /usr/local/bin/desktop-commander remote --logout 2>&1 | sed -E 's#https?://[^ ]+#<URL>#g' || true
echo '=== START REMOTE AGENT ==='
systemctl start desktop-commander-remote.service
sleep 7
echo '=== STATUS ==='
systemctl is-active desktop-commander-remote.service || true
echo '=== NEW AUTH OUTPUT ==='
journalctl -u desktop-commander-remote.service --since '90 seconds ago' --no-pager -o cat | tail -90
