#!/usr/bin/env bash
set -u
echo '===== LINUX CONTROL READY ====='
date -Is
hostname
echo '===== RDC SERVICE ====='
systemctl is-active desktop-commander-remote.service 2>&1 || true
echo '===== VPN SERVICE ====='
systemctl is-active wg-quick@wg0.service 2>&1 || true
echo '===== DONE ====='
