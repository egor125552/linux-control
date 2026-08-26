#!/usr/bin/env bash
set -u

section() { printf '\n===== %s =====\n' "$1"; }

section 'IDENTITY / UPTIME'
hostnamectl 2>/dev/null || true
uptime
who -a || true

section 'CPU / MEMORY / PRESSURE'
lscpu | sed -n '1,35p'
free -h
printf '\n-- pressure --\n'
for f in /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io; do echo "[$f]"; cat "$f" 2>/dev/null || true; done

section 'FILESYSTEMS'
df -hT
printf '\n-- biggest top-level dirs --\n'
du -xhd1 / 2>/dev/null | sort -h | tail -20

section 'TOP CPU'
ps aux --sort=-%cpu | head -25

section 'TOP MEMORY'
ps aux --sort=-%mem | head -25

section 'RUNNING SERVICES'
systemctl --type=service --state=running --no-pager --no-legend || true

section 'FAILED UNITS'
systemctl --failed --no-pager || true

section 'ENABLED SERVICES'
systemctl list-unit-files --type=service --state=enabled --no-pager || true

section 'TIMERS'
systemctl list-timers --all --no-pager || true

section 'LISTENING PORTS'
ss -tulpn || true

section 'NETWORK'
ip -br addr || true
ip route || true
ip -6 route || true

section 'WIREGUARD'
wg show || true

section 'FIREWALL'
ufw status verbose || true

section 'CADDY'
systemctl status caddy --no-pager -l || true
caddy validate --config /etc/caddy/Caddyfile 2>&1 || true

section 'CUSTOM SERVICES'
for s in audio-remote egor-desktop; do
  echo "--- $s ---"
  systemctl status "$s" --no-pager -l || true
done

section 'GITHUB RUNNER'
systemctl status actions.runner.egor125552-linux-control.vmi3528738.service --no-pager -l || true

section 'DOCKER / CONTAINERS'
if command -v docker >/dev/null 2>&1; then docker ps -a; else echo 'docker: not installed'; fi
if command -v podman >/dev/null 2>&1; then podman ps -a; else echo 'podman: not installed'; fi

section 'RECENT ERRORS CURRENT BOOT'
journalctl -b -p warning..alert -n 120 --no-pager || true

section 'RECENT SSH AUTH EVENTS'
journalctl -u ssh -n 80 --no-pager || true

section 'KERNEL WARNINGS / ERRORS'
dmesg --level=warn,err 2>/dev/null | tail -100 || true

section 'PACKAGE STATE'
printf 'upgradable count: '
apt list --upgradable 2>/dev/null | tail -n +2 | wc -l
printf 'held packages:\n'
apt-mark showhold || true

section 'DONE'
date -Is
