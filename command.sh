#!/usr/bin/env bash
set -u
echo '=== HOST ==='
hostname; whoami; date -u
echo '=== REMOTE PROCESSES ==='
ps -eo pid,ppid,user,args | grep -Ei 'desktop.commander|desktop-commander|wonderwhy|remote.*mcp' | grep -v grep || true
echo '=== SYSTEM SERVICES ==='
systemctl list-units --all --type=service --no-pager | grep -Ei 'desktop|commander' || true
echo '=== USER SERVICES ==='
for u in root ubuntu egor; do id "$u" >/dev/null 2>&1 || continue; echo "USER=$u"; systemctl --user --machine="$u@" list-units --all --type=service --no-pager 2>/dev/null | grep -Ei 'desktop|commander' || true; done
echo '=== INSTALLATION ==='
command -v node || true; command -v npx || true
find /etc/systemd/system /root/.config/systemd/user /home -maxdepth 5 \( -iname '*desktop*commander*' -o -iname '*wonderwhy*' \) 2>/dev/null | head -60
