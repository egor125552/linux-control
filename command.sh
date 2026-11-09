#!/usr/bin/env bash
set -euo pipefail
ROOT='/srv/Zombie Horror Game/Зимний прототип'
echo '=== MANIFEST LOCATIONS ==='
find "$ROOT" -maxdepth 3 -type f -iname '*manifest*.json' -o -iname '*manifest*.js' | sed -n '1,80p'
echo '=== SCENE7 IN MANIFESTS ==='
grep -RIl 'Сцена 7 Александр 001.mp3' "$ROOT/Web" "$ROOT" 2>/dev/null | sed -n '1,40p' || true
echo '=== GENERATORS ==='
grep -RIlE 'file-manifest|manifest.*audio|audio.*manifest' "$ROOT/tools" "$ROOT" 2>/dev/null | grep -E '\.(py|js|mjs|sh)$' | sed -n '1,80p' || true
echo '=== PUBLIC SAMPLE ==='
url='https://169-58-224-216.sslip.io/winter/audio/voices/Сцена%207%20Александр%20001.mp3'
curl -ksS -o /tmp/scene7-public.mp3 -w 'HTTP=%{http_code} SIZE=%{size_download}\n' "$url"
sha256sum "$ROOT/audio/voices/game/Сцена 7 Александр 001.mp3" /tmp/scene7-public.mp3
echo '=== GAME COUNTS ==='
find "$ROOT/audio/voices/game" -maxdepth 1 -type f -name 'Сцена 7 *.mp3' | wc -l
