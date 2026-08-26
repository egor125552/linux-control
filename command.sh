#!/usr/bin/env bash
set -euo pipefail

echo '===== KERNEL VERSION ====='
uname -a
cat /proc/version

echo '===== /BOOT ====='
ls -lh /boot | sed -n '1,120p'

echo '===== PROC TOP LEVEL ====='
find /proc -maxdepth 1 -mindepth 1 -printf '%f\n' 2>/dev/null | sort | sed -n '1,120p'

echo '===== SYS TOP LEVEL ====='
find /sys -maxdepth 1 -mindepth 1 -printf '%f\n' 2>/dev/null | sort

echo '===== KERNEL RUNTIME VALUES ====='
printf 'hostname: '; cat /proc/sys/kernel/hostname
printf 'osrelease: '; cat /proc/sys/kernel/osrelease
printf 'ostype: '; cat /proc/sys/kernel/ostype
printf 'pid_max: '; cat /proc/sys/kernel/pid_max
printf 'threads-max: '; cat /proc/sys/kernel/threads-max
printf 'randomize_va_space: '; cat /proc/sys/kernel/randomize_va_space

echo '===== LOADED MODULES ====='
lsmod | sed -n '1,80p'

echo '===== /SYS/KERNEL ====='
find /sys/kernel -maxdepth 1 -mindepth 1 -printf '%f\n' 2>/dev/null | sort | sed -n '1,120p'

echo '===== INTERRUPTS SUMMARY ====='
cat /proc/interrupts | sed -n '1,35p'

echo '===== FILESYSTEMS ====='
cat /proc/filesystems

echo '===== COMMAND LINE ====='
cat /proc/cmdline
