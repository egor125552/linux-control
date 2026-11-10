#!/usr/bin/env bash
set -u
echo '=== SERVICE STATUS ==='
systemctl status desktop-commander-remote.service --no-pager -l || true
echo
echo '=== ENABLED / ACTIVE ==='
systemctl is-enabled desktop-commander-remote.service || true
systemctl is-active desktop-commander-remote.service || true
echo
echo '=== UNIT FILE ==='
systemctl cat desktop-commander-remote.service || true
echo
echo '=== PROCESS ==='
pgrep -af 'desktop-commander|remote' || true
echo
echo '=== RECENT JOURNAL ==='
journalctl -u desktop-commander-remote.service -n 120 --no-pager -o cat || true
echo
echo '=== BINARY / VERSION ==='
command -v desktop-commander || true
/usr/local/bin/desktop-commander --version 2>&1 || true
