#!/usr/bin/env bash
set -u
echo "===== TARGET ====="
hostname; id
echo "===== RDC PROCESS ====="
ps -eo pid,ppid,user,etime,args | grep -Ei '[d]esktop.commander|[r]emote.device|[n]px .*remote' | head -n 24 || true
echo "===== RDC SERVICES ====="
systemctl list-units --all --type=service --no-pager 2>/dev/null | grep -Ei 'desktop|commander|remote' | head -n 24 || true
echo "===== RUNTIMES ====="
command -v node || true
command -v npx || true
echo "===== USER HOMES ====="
getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1 " -> " $6}' | head -n 12
echo "===== DONE ====="
