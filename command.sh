#!/usr/bin/env bash
set -euo pipefail

CONF=/etc/ssh/sshd_config.d/00-disable-password-auth.conf
BACKUP_DIR=/root/ssh-hardening-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"
cp -a /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config"
cp -a /etc/ssh/sshd_config.d "$BACKUP_DIR/sshd_config.d" 2>/dev/null || true

echo '===== SSH CONFIG SOURCES ====='
grep -RniE '^[[:space:]]*(PasswordAuthentication|KbdInteractiveAuthentication|PubkeyAuthentication|PermitRootLogin)[[:space:]]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null || true

echo '===== BEFORE ====='
sshd -T | grep -E '^(pubkeyauthentication|passwordauthentication|permitrootlogin|kbdinteractiveauthentication) ' || true

if ! sshd -T | grep -q '^pubkeyauthentication yes$'; then
  echo 'ERROR: Public-key authentication is not enabled. Refusing to change SSH.' >&2
  exit 1
fi

cat > "$CONF" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
chmod 644 "$CONF"
rm -f /etc/ssh/sshd_config.d/99-disable-password-auth.conf

sshd -t
systemctl reload ssh
sleep 1

echo '===== AFTER ====='
sshd -T | grep -E '^(pubkeyauthentication|passwordauthentication|permitrootlogin|kbdinteractiveauthentication) ' || true

if ! sshd -T | grep -q '^passwordauthentication no$'; then
  echo 'ERROR: PasswordAuthentication is still enabled after reload.' >&2
  exit 2
fi

echo '===== SERVICE ====='
systemctl is-active ssh
ss -ltnp | grep -E '(:22[[:space:]])' || true

echo '===== BACKUP ====='
echo "$BACKUP_DIR"
