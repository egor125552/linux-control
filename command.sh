#!/usr/bin/env bash
set -u

echo '===== SYSTEM ====='
date -Is
hostname
uname -a
uptime

echo '===== WIREGUARD ====='
systemctl is-active wg-quick@wg0 2>&1 || true
systemctl status wg-quick@wg0 --no-pager -l 2>&1 | tail -n 80 || true
wg show 2>&1 || true
ip -details addr show dev wg0 2>&1 || true

echo '===== ROUTES ====='
ip route show 2>&1 || true
ip rule show 2>&1 || true

echo '===== LISTENING UDP ====='
ss -lunp 2>&1 | grep -E '(^|:)51820\b|State|Local Address' || true

echo '===== FORWARDING ====='
sysctl net.ipv4.ip_forward 2>&1 || true
sysctl net.ipv6.conf.all.forwarding 2>&1 || true

echo '===== FIREWALL ====='
command -v ufw >/dev/null && ufw status verbose 2>&1 || true
command -v nft >/dev/null && nft list ruleset 2>&1 || true
iptables -S 2>&1 || true
iptables -t nat -S 2>&1 || true

echo '===== RECENT WG LOGS ====='
journalctl -u wg-quick@wg0 --since '-2 hours' --no-pager -n 120 2>&1 || true

echo '===== NETWORK TEST ====='
ping -c 2 -W 2 1.1.1.1 2>&1 || true
getent hosts google.com 2>&1 | head -n 5 || true

echo '===== DONE ====='
