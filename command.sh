#!/bin/bash
set -u
echo 'SERVER STATUS'
hostname
date -Is
df -h /
for s in desktop-commander-remote.service actions.runner.egor125552-linux-control.vmi3528738.service xray-vless.service caddy.service wg-quick@wg0.service audio-remote.service egor-desktop.service; do printf '%s: ' "$s"; systemctl is-active "$s" || true; done
echo 'SOCKETS'
ss -lntup | grep -E '(:(443|8443|51820|2053|2087|4433|10080)[[:space:]])' | head -n 15 || true
echo 'PANEL'
command -v x-ui || true
echo 'DONE'
