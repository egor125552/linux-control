#!/usr/bin/env bash
set -u

# bridge-v2 recheck
echo '===== NOW ====='
date -Is
uptime

echo '===== WG STATUS ====='
systemctl is-active wg-quick@wg0 2>&1 || true
wg show 2>&1 || true

echo '===== UDP 51820 ====='
ss -lunp 2>&1 | grep -E '(^|:)51820\b|State|Local Address' || true

echo '===== INTERNET ====='
ping -c 2 -W 2 1.1.1.1 2>&1 || true

echo '===== DONE ====='
