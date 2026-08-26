#!/usr/bin/env bash
set -euo pipefail

stamp=$(date +%Y%m%d-%H%M%S)
backup=/root/netplan-authority-backup-$stamp
mkdir -p "$backup"
cp -a /etc/systemd/network "$backup/" 2>/dev/null || true
cp -a /etc/netplan "$backup/" 2>/dev/null || true
cp -a /etc/systemd/system/egor-dns-fix.service "$backup/" 2>/dev/null || true
cp -a /usr/local/sbin/egor-dns-fix "$backup/" 2>/dev/null || true
cp -a /etc/NetworkManager/conf.d/10-egor-eth0-unmanaged.conf "$backup/" 2>/dev/null || true

# Remove temporary userspace overrides. Keep initramfs early networking intact.
systemctl disable --now egor-dns-fix.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/egor-dns-fix.service
rm -f /usr/local/sbin/egor-dns-fix
rm -f /etc/systemd/network/05-egor-early-eth0.network
rm -f /etc/NetworkManager/conf.d/10-egor-eth0-unmanaged.conf

systemctl daemon-reload

# Restore provider Netplan-generated networkd configuration as the sole normal-userspace authority.
netplan generate
networkctl reload

# Reconfigure only eth0 through networkd. If this fails, do not tear down the live link.
networkctl reconfigure eth0 || true
sleep 2

# Make sure resolved uses the DNS delivered by Netplan/networkd.
systemctl restart systemd-resolved.service
sleep 1

# Validate exact expected provider configuration and live connectivity.
echo '===== ACTIVE NETWORK FILE ====='
networkctl status eth0 --no-pager | sed -n '1,80p'

echo '===== GENERATED NETPLAN NETWORKD ====='
sed -n '1,160p' /run/systemd/network/10-netplan-eth0.network

echo '===== RESOLVED ====='
resolvectl status eth0

echo '===== DNS QUERY ====='
resolvectl query github.com

echo '===== LIVE ADDRESSES ====='
ip -brief addr show eth0

echo '===== ROUTES ====='
ip route
ip -6 route | sed -n '1,40p'

echo '===== HTTPS ====='
curl -4 -I --connect-timeout 10 https://github.com | sed -n '1,5p'

echo '===== EARLY INITRAMFS STILL PRESENT ====='
test -x /etc/initramfs-tools/scripts/init-premount/egor-early-network
lsinitramfs "/boot/initrd.img-$(uname -r)" | grep -q 'scripts/init-premount/egor-early-network'
echo 'INITRAMFS_EARLY_NETWORK=yes'

echo '===== TEMP OVERRIDES REMOVED ====='
test ! -e /etc/systemd/network/05-egor-early-eth0.network
test ! -e /etc/systemd/system/egor-dns-fix.service
test ! -e /usr/local/sbin/egor-dns-fix
echo 'NETPLAN_IS_USERSPACE_AUTHORITY=yes'
echo "BACKUP=$backup"
echo 'REBOOT_NOT_PERFORMED=yes'
