#!/usr/bin/env bash
set -u

echo '===== NOW ====='
date -Is
uptime

echo '===== SSH SERVICE ====='
systemctl is-active ssh 2>&1 || true
systemctl is-enabled ssh 2>&1 || true
systemctl status ssh --no-pager -l 2>&1 | tail -n 100 || true

echo '===== SSH LISTEN ====='
ss -ltnp 2>&1 | grep -E '(^State|:22\b)' || true

echo '===== SSH CONFIG TEST ====='
sshd -t 2>&1 && echo SSHD_CONFIG_OK=yes || echo SSHD_CONFIG_OK=no

echo '===== EFFECTIVE SSH SETTINGS ====='
sshd -T 2>/dev/null | grep -E '^(port|listenaddress|passwordauthentication|pubkeyauthentication|permitrootlogin|maxstartups|maxsessions) ' || true

echo '===== FIREWALL 22 ====='
ufw status verbose 2>&1 | grep -E '(^Status|^Состояние|22/tcp|OpenSSH)' || true
iptables -S INPUT 2>&1 | head -n 80 || true

echo '===== RECENT SSH LOGS ====='
journalctl -u ssh --since '-3 hours' --no-pager -n 120 2>&1 || true

echo '===== LOCAL CONNECT TEST ====='
timeout 5 bash -c '</dev/tcp/127.0.0.1/22' 2>&1 && echo LOCAL_TCP_22_OK=yes || echo LOCAL_TCP_22_OK=no

echo '===== DONE ====='
