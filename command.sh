#!/usr/bin/env bash
set -euo pipefail

# retrigger: 2026-08-26 early-network finalize clean run
DEV='eth0'
IP4='169.58.224.216/17'
GW4='169.58.128.1'
IP6='2a02:c207:2352:8738::1/64'
GW6='fe80::1'
DNS1='195.179.224.53'
DNS2='209.126.15.53'

stamp=$(date +%Y%m%d-%H%M%S)
backup=/root/early-network-backup-$stamp
mkdir -p "$backup"
cp -a /etc/systemd/network "$backup/" 2>/dev/null || true
cp -a /etc/initramfs-tools "$backup/" 2>/dev/null || true
cp -a /etc/NetworkManager/conf.d "$backup/networkmanager-conf.d" 2>/dev/null || true

echo '===== EARLY NORMAL USERSPACE NETWORK ====='
mkdir -p /etc/systemd/network
cat >/etc/systemd/network/05-egor-early-eth0.network <<EOF
[Match]
Name=$DEV

[Network]
Address=$IP4
Address=$IP6
DNS=$DNS1
DNS=$DNS2
LinkLocalAddressing=ipv6
ConfigureWithoutCarrier=yes

[Route]
Destination=0.0.0.0/0
Gateway=$GW4

[Route]
Destination=::/0
Gateway=$GW6
GatewayOnLink=yes

[Link]
RequiredForOnline=yes
EOF
chmod 0644 /etc/systemd/network/05-egor-early-eth0.network

mkdir -p /etc/NetworkManager/conf.d
cat >/etc/NetworkManager/conf.d/10-egor-eth0-unmanaged.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:$DEV
EOF
chmod 0644 /etc/NetworkManager/conf.d/10-egor-eth0-unmanaged.conf

systemctl enable systemd-networkd.service >/dev/null
systemctl enable systemd-networkd-wait-online.service >/dev/null 2>&1 || true
networkctl reload || true

echo '===== INITRAMFS NETWORK ====='
mkdir -p /etc/initramfs-tools/scripts/init-premount /etc/initramfs-tools/hooks
cat >/etc/initramfs-tools/scripts/init-premount/egor-early-network <<'EOS'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "${1:-}" in prereqs) prereqs; exit 0;; esac

DEV=eth0
ADDR4=169.58.224.216/17
GW4=169.58.128.1

modprobe virtio_net 2>/dev/null || true

IPBIN=""
for x in /usr/bin/ip /usr/sbin/ip /sbin/ip /bin/ip; do
    [ -x "$x" ] && IPBIN="$x" && break
done
if [ -z "$IPBIN" ] && command -v ip >/dev/null 2>&1; then
    IPBIN=$(command -v ip)
fi

if [ -n "$IPBIN" ]; then
    "$IPBIN" link set "$DEV" up 2>/dev/null || true
    "$IPBIN" addr replace "$ADDR4" dev "$DEV" 2>/dev/null || true
    "$IPBIN" route replace default via "$GW4" dev "$DEV" 2>/dev/null || true
    echo "egor-early-network: IPv4 up on $DEV ($ADDR4 via $GW4)" >/dev/kmsg 2>/dev/null || true
else
    echo 'egor-early-network: ip utility unavailable; continuing boot' >/dev/kmsg 2>/dev/null || true
fi
exit 0
EOS
chmod 0755 /etc/initramfs-tools/scripts/init-premount/egor-early-network

cat >/etc/initramfs-tools/hooks/egor-early-network-tools <<'EOS'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "${1:-}" in prereqs) prereqs; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions
copy_exec /usr/sbin/ip /usr/sbin/ip 2>/dev/null || copy_exec /usr/bin/ip /usr/bin/ip 2>/dev/null || true
copy_exec /usr/sbin/modprobe /usr/sbin/modprobe 2>/dev/null || true
manual_add_modules virtio_net 2>/dev/null || true
EOS
chmod 0755 /etc/initramfs-tools/hooks/egor-early-network-tools

cat >/usr/local/sbin/egor-network-rescue <<'EOS'
#!/bin/sh
sleep 5
if ! ip -4 route show default | grep -q 'via 169.58.128.1.*dev eth0'; then
    logger -t egor-network-rescue 'Early network route missing; reverting custom runtime override'
    rm -f /etc/systemd/network/05-egor-early-eth0.network
    rm -f /etc/NetworkManager/conf.d/10-egor-eth0-unmanaged.conf
    netplan generate || true
    systemctl restart systemd-networkd.service || true
fi
exit 0
EOS
chmod 0755 /usr/local/sbin/egor-network-rescue

cat >/etc/systemd/system/egor-network-rescue.service <<'EOF'
[Unit]
Description=Egor early network rescue guard
After=systemd-networkd.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/egor-network-rescue

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable egor-network-rescue.service >/dev/null

echo '===== REBUILD INITRAMFS ====='
sh -n /etc/initramfs-tools/scripts/init-premount/egor-early-network
sh -n /etc/initramfs-tools/hooks/egor-early-network-tools
update-initramfs -u -k "$(uname -r)"

echo '===== VERIFY PACKED EARLY NETWORK ====='
lsinitramfs "/boot/initrd.img-$(uname -r)" | grep -E 'scripts/init-premount/egor-early-network|virtio_net|usr/(s)?bin/ip|usr/(s)?bin/modprobe' | sed -n '1,120p' || true

echo '===== VERIFY CONFIG CONTENT ====='
sed -n '1,160p' /etc/systemd/network/05-egor-early-eth0.network
networkctl reload

echo '===== CURRENT LIVE NETWORK: MUST STILL BE INTACT ====='
ip -brief addr show "$DEV"
ip route
ip -6 route | sed -n '1,40p'
systemctl is-active systemd-networkd
systemctl is-active NetworkManager || true
systemctl is-enabled egor-network-rescue.service

echo "BACKUP=$backup"
echo 'READY_FOR_REBOOT=yes'
echo 'REBOOT_NOT_PERFORMED=yes'
