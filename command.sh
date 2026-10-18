#!/usr/bin/env bash
set -u
echo '===== LINUX CONTROL LIVE CHECK ====='
date -Is
hostname
uptime
echo '===== RUNNER ====='
whoami
echo '===== WIREGUARD ====='
if command -v wg >/dev/null 2>&1; then
  wg show wg0 latest-handshakes 2>&1 | awk '{ print "Peer handshake timestamp:", $2 }' | head -n 12
  wg show wg0 listen-port 2>&1 || true
else
  echo 'wg command unavailable'
fi
echo '===== WG INTERFACE ====='
ip -brief address show wg0 2>&1 || true
echo '===== WG SERVICE ====='
systemctl is-active wg-quick@wg0 2>&1 || true
echo '===== UDP 51820 ====='
ss -lun 2>&1 | grep -E '(^State|:51820\b)' || true
echo '===== SSH ====='
systemctl is-active ssh 2>&1 || true
echo '===== DONE ====='
