#!/usr/bin/env bash
set -euo pipefail
ROOT='/srv/Zombie Horror Game/Зимний прототип'
echo '=== SCENE 7 RELATED FILES ==='
find "$ROOT" -maxdepth 4 -type f | grep -Ei 'Сцена 7|сцена 7|Scene 7|scene 7' | sort | sed -n '1,240p'
echo '=== MUSIC MODULES ==='
find "$ROOT/js" -type f | grep -Ei 'музык|music' | sort
echo '=== SCENE 7 REFERENCES IN CODE ==='
grep -RniE 'Сцена 7|scene7|scene-7|scene 7|031 Connor|LAB6_MUSIC|music' "$ROOT/js" "$ROOT/scene" 2>/dev/null | grep -E 'Сцена 7|scene7|scene-7|031 Connor|LAB6_MUSIC|Музыка сцены 7|music.*7' | sed -n '1,260p'
echo '=== MUSIC DIRECTORY ==='
find "$ROOT/audio/music" -maxdepth 1 -type f -printf '%f\n' | sort | sed -n '1,220p'
