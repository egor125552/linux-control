#!/usr/bin/env bash
set -euo pipefail

echo '===== CURRENT NETPLAN ====='
find /etc/netplan -maxdepth 1 -type f -print -exec sh -c 'echo "--- $1"; sed -n "1,220p" "$1"' _ {} \; 2>/dev/null || true

echo '===== GENERATED NETWORKD ====='
find /run/systemd/network -maxdepth 1 -type f -print -exec sh -c 'echo "--- $1"; sed -n "1,220p" "$1"' _ {} \; 2>/dev/null || true

echo '===== NETWORK OWNERSHIP ====='
networkctl status eth0 --no-pager 2>/dev/null | sed -n '1,180p' || true
nmcli -f GENERAL,IP4,IP6 device show eth0 2>/dev/null | sed -n '1,180p' || true

echo '===== INITRAMFS NETWORK SUPPORT ====='
dpkg -l initramfs-tools busybox-initramfs 2>/dev/null || true
find /etc/initramfs-tools -maxdepth 3 -type f -print 2>/dev/null | sort | sed -n '1,220p'
grep -RniE 'DEVICE=|IP=|ip=|BOOT=' /etc/initramfs-tools /etc/default 2>/dev/null | sed -n '1,180p' || true

echo '===== ROUTE / LINK ====='
ip -brief addr show eth0
ip route
ip -6 route | sed -n '1,80p'

echo '===== DNS ====='
resolvectl status eth0 2>/dev/null | sed -n '1,120p' || true

echo '===== BOOT TIMING NETWORK ====='
systemd-analyze blame --no-pager | grep -Ei 'network|cloud-init|wait-online' | sed -n '1,80p' || true
