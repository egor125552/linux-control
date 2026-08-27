#!/usr/bin/env bash
set -euo pipefail
mate_pid=$(pgrep -u egor -x mate-session | head -1 || true)
pulse_pid=$(pgrep -u egor -x pulseaudio | head -1 || true)
xpra_pid=$(ps -o ppid= -p "$pulse_pid" 2>/dev/null | xargs || true)
[ -n "$mate_pid" ] && [ -n "$pulse_pid" ] && [ -n "$xpra_pid" ] || { echo MISSING_PROCESS; exit 1; }
getenvp(){ local p="$1" k="$2"; tr '\0' '\n' < "/proc/$p/environ" | sed -n "s/^${k}=//p" | head -1; }

echo "XPRA_PID=$xpra_pid"
for who in xpra pulse mate; do
  case "$who" in xpra) p=$xpra_pid;; pulse) p=$pulse_pid;; mate) p=$mate_pid;; esac
  cookie=$(getenvp "$p" PULSE_COOKIE)
  server=$(getenvp "$p" PULSE_SERVER)
  printf '%s PULSE_COOKIE present: ' "$who"; [ -n "$cookie" ] && echo yes || echo no
  printf '%s PULSE_SERVER present: ' "$who"; [ -n "$server" ] && echo yes || echo no
  if [ -n "$cookie" ]; then
    printf '%s cookie exists: ' "$who"; [ -f "$cookie" ] && echo yes || echo no
    printf '%s cookie path hash: ' "$who"; printf '%s' "$cookie" | sha256sum | cut -c1-16
    if [ -f "$cookie" ]; then printf '%s cookie file hash: ' "$who"; sha256sum "$cookie" | cut -c1-16; fi
  fi
done

echo '===== SAFE COOKIE FILE CANDIDATES ====='
# Do not reveal filenames/paths: show only existence, size and hash prefixes.
i=0
while IFS= read -r f; do
  i=$((i+1))
  printf 'candidate%d size=' "$i"; stat -c %s "$f" 2>/dev/null || echo '?'
  printf 'candidate%d hash=' "$i"; sha256sum "$f" 2>/dev/null | cut -c1-16 || true
done < <(find /run/egor-desktop /home/egor/.config/pulse /home/egor/.pulse /tmp -maxdepth 5 -type f \( -name cookie -o -name '*cookie*' \) -user egor 2>/dev/null | head -30)
echo "COOKIE_CANDIDATE_COUNT=$i"

echo '===== XPRA COMMAND / CONFIG PULSE REFERENCES ====='
tr '\0' ' ' < "/proc/$xpra_pid/cmdline" 2>/dev/null | sed -E 's/(cookie[= ]+)[^ ]+/\1<redacted>/Ig' || true; echo
systemctl cat egor-desktop.service 2>/dev/null | grep -Ei 'xpra|pulse|sound' | sed -E 's/(cookie[= ]+)[^ ]+/\1<redacted>/Ig' || true

echo XPRA_COOKIE_SOURCE_INSPECT_DONE=yes
