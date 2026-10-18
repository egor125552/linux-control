#!/usr/bin/env bash
set -u
svc=desktop-commander-remote.service
since=$(date '+%Y-%m-%d %H:%M:%S')
echo '===== STOP OLD RDC SESSION ====='
systemctl stop "$svc" || true
echo '===== SIGN OUT OLD RDC ACCOUNT ====='
/usr/local/bin/desktop-commander remote --logout
logout_status=$?
echo "Logout exit code: $logout_status"
echo '===== START FRESH RDC SIGN IN ====='
systemctl start "$svc"
sleep 9
echo "Service state: $(systemctl is-active "$svc")"
echo '===== DEVICE AUTHORIZATION OUTPUT ====='
journalctl -u "$svc" --since "$since" -o cat --no-pager 2>&1 | tail -n 75
echo '===== END AUTHORIZATION OUTPUT ====='
