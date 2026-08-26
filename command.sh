#!/usr/bin/env bash
set -euo pipefail

IP_CIDR='169.58.224.216/17'
GW='169.58.128.1'
DEV='eth0'

stamp=$(date +%Y%m%d-%H%M%S)
backup=/root/early-network-backup-$stamp
mkdir -p "$backup"
cp -a /etc/systemd/network "$backup/" 2>/dev/null || true
cp -a /etc/initramfs-tools "$backup/" 2>/dev/null || true
cp -a /etc/default/grub "$backup/grub" 2>/dev/null || true

echo '===== 1. EARLY SYSTEMD-NETWORKD CONFIG ====='
mkdir -p /etc/systemd/network
cat >/etc/systemd/network/05-egor-early-eth0.network <<EOF
[Match]
Name=$DEV

[Network]
Address=$IP_CIDR
Gateway=$GW
IPv6AcceptRA=yes
LinkLocalAddressing=ipv6
ConfigureWithoutCarrier=yes

[Link]
RequiredForOnline=yes
EOF
chmod 0644 /etc/systemd/network/05-egor-early-eth0.network

# Tell NetworkManager not to take eth0 away from networkd.  This preserves
# NetworkManager for the desktop while the server NIC is owned by networkd.
mkdir -p /etc/NetworkManager/conf.d
cat >/etc/NetworkManager/conf.d/10-egor-eth0-unmanaged.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:$DEV
EOF
chmod 0644 /etc/NetworkManager/conf.d/10-egor-eth0-unmanaged.conf

# Start networkd as part of the earliest normal userspace network setup.
systemctl enable systemd-networkd.service >/dev/null
systemctl enable systemd-networkd-wait-online.service >/dev/null 2>&1 || true

# Do NOT restart networking here: current connection is our recovery path.
networkctl reload || true

echo '===== 2. INITRAMFS EARLY NETWORK SCRIPT ====='
mkdir -p /etc/initramfs-tools/scripts/init-premount
cat >/etc/initramfs-tools/scripts/init-premount/egor-early-network <<'EOS'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "${1:-}" in prereqs) prereqs; exit 0;; esac

DEV=eth0
ADDR=169.58.224.216/17
GW=169.58.128.1

# initramfs-tools includes busybox; use whichever ip implementation exists.
IPBIN=""
for x in /usr/bin/ip /sbin/ip /bin/ip; do
    [ -x "$x" ] && IPBIN="$x" && break
done
if [ -z "$IPBIN" ] && command -v ip >/dev/null 2>&1; then
    IPBIN=$(command -v ip)
fi

# Never make boot depend on networking: failure here must not prevent root mount.
if [ -n "$IPBIN" ]; then
    "$IPBIN" link set "$DEV" up 2>/dev/null || true
    "$IPBIN" addr replace "$ADDR" dev "$DEV" 2>/dev/null || true
    "$IPBIN" route replace default via "$GW" dev "$DEV" 2>/dev/null || true
    echo "egor-early-network: $DEV $ADDR via $GW" >/dev/kmsg 2>/dev/null || true
else
    echo 'egor-early-network: no ip utility in initramfs; skipped' >/dev/kmsg 2>/dev/null || true
fi
exit 0
EOS
chmod 0755 /etc/initramfs-tools/scripts/init-premount/egor-early-network

# Ensure the virtio network driver and iproute utility are available in initramfs.
mkdir -p /etc/initramfs-tools/hooks
cat >/etc/initramfs-tools/hooks/egor-early-network-tools <<'EOS'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "${1:-}" in prereqs) prereqs; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions
copy_exec /usr/sbin/ip /usr/sbin/ip 2>/dev/null || copy_exec /usr/bin/ip /usr/bin/ip 2>/dev/null || true
manual_add_modules virtio_net 2>/dev/null || true
EOS
chmod 0755 /etc/initramfs-tools/hooks/egor-early-network-tools

echo '===== 3. REBUILD INITRAMFS ====='
update-initramfs -u -k "$(uname -r)"

echo '===== 4. VALIDATE ====='
systemd-analyze verify /etc/systemd/network/05-egor-early-eth0.network 2>&1 || true
lsinitramfs "/boot/initrd.img-$(uname -r)" | grep -E 'egor-early-network|virtio_net|(/|^)ip$' | sed -n '1,120p' || true

echo '===== 5. CURRENT CONNECTION (UNCHANGED) ====='
ip -brief address show "$DEV"
ip route
systemctl is-active systemd-networkd || true
systemctl is-active NetworkManager || true

echo "BACKUP=$backup"
echo 'Installed. No reboot performed.'
