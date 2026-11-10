#!/usr/bin/env bash
set -u
echo '=== SERVICE CONFIG (redacted env) ==='
systemctl cat desktop-commander-remote.service | sed -E '/Environment=|EnvironmentFile=|token|secret|key|password/Is/.*/[REDACTED]/'
echo '=== SERVICE STATUS ==='
systemctl show desktop-commander-remote.service -p User -p ExecStart -p Restart -p WorkingDirectory -p ActiveState -p SubState
echo '=== REMOTE CLI HELP ==='
timeout 12 /usr/local/bin/desktop-commander remote --help 2>&1 | head -100 || true
echo '=== AUTH RELATED FILE NAMES ==='
find /root/.config /root/.local /root/.desktop-commander /home -maxdepth 4 -type f \( -iname '*auth*' -o -iname '*desktop*' -o -iname '*remote*' \) 2>/dev/null | head -80
echo '=== RECENT JOURNAL (possible private URLs masked) ==='
journalctl -u desktop-commander-remote.service -n 35 --no-pager 2>&1 | sed -E 's#https?://[^ ]+#<URL>#g; s/(token|code|secret|key)[:=][^ ]+/\\1=[REDACTED]/Ig'
