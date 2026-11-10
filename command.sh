#!/usr/bin/env bash
set -euo pipefail
ROOT='/srv/Zombie Horror Game/Зимний прототип'
echo '=== AGENTS ==='
cat "$ROOT/AGENTS.md"
echo '=== JS TREE ==='
find "$ROOT/js" -maxdepth 3 -type f -printf '%P\n' | sort
echo '=== TEST TREE ==='
find "$ROOT/tests" -maxdepth 2 -type f -printf '%P\n' | sort
echo '=== SCENE TEXT FILES ==='
find "$ROOT" -maxdepth 2 -type f \( -iname '*.txt' -o -iname '*.md' \) -printf '%P\n' | sort | sed -n '1,240p'
