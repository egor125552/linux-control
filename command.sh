#!/usr/bin/env bash
set -euo pipefail

cat >/usr/local/sbin/egor-dns-fix <<'EOF'
#!/bin/sh
set -eu
resolvectl dns eth0 195.179.224.53 209.126.15.53
resolvectl domain eth0 '~.'
EOF
chmod 0755 /usr/local/sbin/egor-dns-fix

cat >/etc/systemd/system/egor-dns-fix.service <<'EOF'
[Unit]
Description=Persist DNS for eth0
After=systemd-networkd.service systemd-resolved.service
Wants=systemd-resolved.service
Before=actions.runner.egor125552-linux-control.vmi3528738.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/egor-dns-fix
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable egor-dns-fix.service >/dev/null
systemctl start egor-dns-fix.service

# Keep DNS declared in the persistent networkd config too.
if [ -f /etc/systemd/network/05-egor-early-eth0.network ]; then
  grep -q '^DNS=195.179.224.53$' /etc/systemd/network/05-egor-early-eth0.network || sed -i '/^Address=2a02:c207:2352:8738::1\/64$/a DNS=195.179.224.53\nDNS=209.126.15.53' /etc/systemd/network/05-egor-early-eth0.network
fi

networkctl reload || true

echo '===== DNS STATUS ====='
resolvectl status eth0

echo '===== DNS QUERY ====='
resolvectl query github.com

echo '===== HTTPS ====='
curl -4 -I --connect-timeout 10 https://github.com | sed -n '1,5p'

echo '===== SERVICE ====='
systemctl is-enabled egor-dns-fix.service
systemctl is-active egor-dns-fix.service

echo 'DNS_PERSISTENCE_READY=yes'
