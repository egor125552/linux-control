#!/usr/bin/env bash
set -euo pipefail

echo '===== NGINX PACKAGE ====='
if command -v nginx >/dev/null 2>&1; then
  echo "nginx binary: $(command -v nginx)"
  nginx -v 2>&1 || true
else
  echo 'nginx binary: NOT FOUND'
fi

echo '===== DPKG ====='
dpkg -l 'nginx*' 2>/dev/null | sed -n '1,120p' || true

echo '===== SYSTEMD ====='
systemctl is-enabled nginx 2>&1 || true
systemctl is-active nginx 2>&1 || true
systemctl status nginx --no-pager -l 2>&1 | sed -n '1,80p' || true

echo '===== LISTENING PORTS ====='
ss -ltnp 2>/dev/null | grep -E ':(80|443)\b' || true

echo '===== CONFIG TEST ====='
nginx -t 2>&1 || true
