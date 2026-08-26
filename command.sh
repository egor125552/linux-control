#!/usr/bin/env bash
set -euo pipefail

echo '===== CPU / VM ====='
lscpu

echo '===== CPU MODEL LINES ====='
grep -m 8 -E 'model name|cpu MHz|cache size|siblings|cpu cores' /proc/cpuinfo || true

echo '===== VCPU COUNT ====='
echo "nproc: $(nproc)"
echo "online CPUs: $(cat /sys/devices/system/cpu/online 2>/dev/null || true)"

echo '===== VIRTUALIZATION ====='
systemd-detect-virt || true
hostnamectl 2>/dev/null | sed -n '1,40p' || true

echo '===== MEMORY ====='
free -h

echo '===== STORAGE ====='
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS

echo '===== LOAD / UPTIME ====='
uptime

echo '===== KERNEL ====='
uname -a
