#!/usr/bin/env bash
set -euo pipefail

echo '===== BOOT SUMMARY ====='
systemd-analyze time || true
systemd-analyze critical-chain --no-pager || true

echo '===== DEFAULT TARGET ====='
systemctl get-default || true

echo '===== KERNEL CMDLINE ====='
cat /proc/cmdline

echo '===== GRUB DEFAULT ====='
sed -n '1,220p' /etc/default/grub 2>/dev/null || true

echo '===== GRUB MENU ENTRIES ====='
grep -E '^menuentry ' /boot/grub/grub.cfg 2>/dev/null | sed -n '1,80p' || true

echo '===== FSTAB ====='
cat /etc/fstab 2>/dev/null || true

echo '===== INITRAMFS CONTENT TOP ====='
lsinitramfs /boot/initrd.img-$(uname -r) 2>/dev/null | sed -n '1,220p' || true

echo '===== INITRAMFS HOOKS / SCRIPTS ====='
lsinitramfs /boot/initrd.img-$(uname -r) 2>/dev/null | grep -E '(^|/)(scripts|hooks|init|systemd|udev|cryptroot|local-top|local-premount|local-bottom)' | sed -n '1,180p' || true

echo '===== ENABLED SERVICES ====='
systemctl list-unit-files --type=service --state=enabled --no-pager | sed -n '1,220p' || true

echo '===== RUNNING SERVICES ====='
systemctl list-units --type=service --state=running --no-pager | sed -n '1,220p' || true

echo '===== BOOT TARGET WANTS ====='
for d in /etc/systemd/system/*.target.wants; do
  [ -d "$d" ] || continue
  echo "--- $d"
  find "$d" -maxdepth 1 -type l -printf '%f -> %l\n' | sort
 done

echo '===== IMPORTANT CUSTOM SERVICES ====='
for u in caddy.service wg-quick@wg0.service ssh.service sshd.service egor-desktop.service audio-remote.service; do
  echo "--- $u"
  systemctl status "$u" --no-pager -l 2>&1 | sed -n '1,35p' || true
  systemctl cat "$u" 2>&1 | sed -n '1,100p' || true
 done

echo '===== GITHUB RUNNER SERVICES ====='
systemctl list-units --type=service --all --no-pager | grep -Ei 'actions|runner|github' || true
for u in $(systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -Ei 'actions|runner|github' | head -20); do
  echo "--- $u"
  systemctl status "$u" --no-pager -l 2>&1 | sed -n '1,40p' || true
  systemctl cat "$u" 2>&1 | sed -n '1,100p' || true
 done

echo '===== NETWORK ====='
systemctl status systemd-networkd NetworkManager networking --no-pager -l 2>&1 | sed -n '1,140p' || true
ip -brief address || true
ip route || true

echo '===== PID 1 ====='
ps -p 1 -o pid,ppid,user,comm,args
cat /proc/1/cmdline | tr '\0' ' '; echo
