#!/usr/bin/env bash
set -euo pipefail

echo '===== ORCA CONFIG FILES ====='
find /home/egor/.local/share/orca /home/egor/.config/orca /home/egor/.config -maxdepth 3 -type f 2>/dev/null \
 | grep -Ei 'orca|speech|user-settings' | head -120 || true

for f in /home/egor/.local/share/orca/user-settings.conf /home/egor/.local/share/orca/user-settings.conf.bak /home/egor/.config/orca/user-settings.conf; do
  [ -f "$f" ] || continue
  echo "--- $f"
  grep -Ei 'speech|rate|pitch|gain|voice|punctuation|interrupt|verbosity|synthesizer|dispatcher' "$f" | head -220 || true
done

echo '===== SPEECHD LOG METADATA ====='
ls -l --time-style=long-iso /run/egor-desktop/speech-dispatcher/log 2>/dev/null || true

echo '===== CURRENT SPEECHD FULL TAIL ====='
tail -n 260 /run/egor-desktop/speech-dispatcher/log/speech-dispatcher.log 2>/dev/null || true

echo '===== ORCA JOURNAL ====='
journalctl --since '90 minutes ago' --no-pager _UID=$(id -u egor) 2>/dev/null \
 | grep -Ei 'orca|speech-dispatch|rhvoice|at-spi|speech' | tail -260 || true

echo '===== ORCA PYTHON TRACEBACKS ====='
find /home/egor/.local/state/orca /home/egor/.cache -maxdepth 3 -type f 2>/dev/null \
 | while read -r f; do grep -H -Ei 'traceback|exception|speech|dispatcher|broken pipe|bad file descriptor' "$f" 2>/dev/null | tail -40 || true; done \
 | tail -260 || true

echo '===== SPEECHD CLIENTS ====='
ss -xap 2>/dev/null | grep -E 'speechd.sock|speech-dispatch' | head -120 || true

# Show the exact executable/library versions: compatibility bugs matter here.
echo '===== VERSIONS ====='
orca --version 2>/dev/null || true
speech-dispatcher --version 2>/dev/null || true
dpkg-query -W -f='${Package} ${Version}\n' orca speech-dispatcher speech-dispatcher-audio-plugins speech-dispatcher-rhvoice 2>/dev/null || true
/usr/lib/speech-dispatcher-modules/sd_rhvoice --version 2>/dev/null || true

echo ORCA_SETTINGS_DIAG_DONE=yes
