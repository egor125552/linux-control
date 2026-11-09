#!/usr/bin/env bash
set -euo pipefail
echo '=== CANDIDATE TOOLS ==='
find '/srv/Zombie Horror Game' -type f \( -iname '*.py' -o -iname '*.js' -o -iname '*.mjs' \) 2>/dev/null | while read -r f; do
  if grep -Eqi 'длительн|duration|реплик|phrase|matching|сопостав|longest|больш.*меньш|sort.*reverse|vosk' "$f" 2>/dev/null; then
    printf '%s\n' "$f"
  fi
done | sed -n '1,240p'
echo '=== LIKELY NAMES ==='
find '/srv/Zombie Horror Game' -type f 2>/dev/null | grep -Ei 'реплик|дубл|разрез|анализ|время|duration|match|vosk' | sed -n '1,240p'
