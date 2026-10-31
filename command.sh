#!/usr/bin/env bash
set -euo pipefail
echo '=== DISK ==='
df -hT
echo '=== TOP ROOT DIRECTORIES (same filesystem) ==='
du -x -h --max-depth=1 / 2>/dev/null | sort -h | tail -25
echo '=== VAR ==='
du -x -h --max-depth=2 /var 2>/dev/null | sort -h | tail -35
echo '=== HOME ==='
du -x -h --max-depth=2 /home 2>/dev/null | sort -h | tail -25
echo '=== OPT SRV ROOT ==='
for d in /opt /srv /root /usr/local /tmp; do du -x -h --max-depth=2 "$d" 2>/dev/null | sort -h | tail -15; done
echo '=== JOURNAL ==='
journalctl --disk-usage || true
echo '=== DOCKER ==='
command -v docker >/dev/null && timeout 15 docker system df || true
echo '=== LARGE FILES >= 500MB ==='
find / -xdev -type f -size +500M -printf '%s %p\n' 2>/dev/null | sort -nr | head -35
