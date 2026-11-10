#!/usr/bin/env bash
set -euo pipefail
ROOT='/srv/Zombie Horror Game/Зимний прототип'
MUSIC='/root/Музыка'
echo '=== EXACT TRACKS ==='
find "$MUSIC" -type f \( -iname '*054*Fight with Hank*' -o -iname '*Will You Trust Me*' -o -iname '*032*The Bridge*Connor and Hank*' \) -print | sort
echo '=== METADATA ==='
while IFS= read -r f; do
  echo "FILE=$f"
  ffprobe -v error -show_entries format=duration,size:format_tags=title -of default=nw=1 "$f" || true
done < <(find "$MUSIC" -type f \( -iname '*054*Fight with Hank*' -o -iname '*Will You Trust Me*' -o -iname '*032*The Bridge*Connor and Hank*' \) -print | sort)
echo '=== PROJECT HISTORY REFERENCES ==='
grep -RniF -- '054 - Fight with Hank' "$ROOT" 2>/dev/null | head -100 || true
grep -RniF -- 'Will You Trust Me' "$ROOT" 2>/dev/null | head -100 || true
grep -RniF -- '032 - The Bridge' "$ROOT" 2>/dev/null | head -100 || true
echo '=== MUSIC LIBRARY NEIGHBORS ==='
find "$MUSIC" -maxdepth 1 -type f -printf '%f\n' | sort | grep -E '^(0(2[8-9]|3[0-5]|5[0-8])) ' || true
