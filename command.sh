#!/usr/bin/env bash
set -euo pipefail
echo '=== UPLOAD ROUTES ==='
sed -n '410,620p' '/srv/Zombie Horror Game/Server/voice_upload.py'
echo '=== CADDY ==='
grep -RniE '18920|voice|upload|argon' /etc/caddy /etc/nginx 2>/dev/null | head -160 || true
echo '=== MAPS ==='
find '/srv/Zombie Horror Game/Зимний прототип/scene/maps' -maxdepth 1 -type f -printf '%f\n' | sort | tail -100
echo '=== SAMPLE MAPS ==='
for f in '/srv/Zombie Horror Game/Зимний прототип/scene/maps/'*.json; do
  echo "----- $f -----"
  sed -n '1,180p' "$f"
  break
done
