#!/usr/bin/env bash
set -euo pipefail

for f in /usr/local/bin/egor-mate-session /usr/local/bin/orca-egor-launcher /home/egor/.local/share/orca/orca-customizations.py /etc/xdg/autostart/orca-autostart.desktop /etc/xdg/autostart/at-spi-dbus-bus.desktop; do
  echo "===== $f ====="
  if [ -f "$f" ]; then
    sed -n '1,320p' "$f" | grep -Ev '(password|token|secret|private.key|authorization)' || true
  else
    echo MISSING
  fi
done

echo '===== ORCA DEBUG FILES ====='
find /home/egor /run/egor-desktop /tmp -maxdepth 3 -type f \( -iname '*orca*debug*' -o -iname 'orca*.log' -o -iname '*orca*.debug' \) -printf '%p\n' 2>/dev/null | sed -n '1,80p' || true
for f in $(find /home/egor /run/egor-desktop /tmp -maxdepth 3 -type f \( -iname '*orca*debug*' -o -iname 'orca*.log' -o -iname '*orca*.debug' \) 2>/dev/null | head -5); do
  echo "--- tail $f"
  tail -n 120 "$f" 2>/dev/null | grep -Ev '(password|token|secret|private.key|authorization)' || true
done

echo '===== ORCA PROCESS TREE ====='
pstree -aps 30744 2>/dev/null || true

echo '===== ACCESSIBILITY SCHEMAS ====='
gsettings list-keys org.mate.interface 2>/dev/null | grep -E 'access|gtk|toolkit' || true
gsettings list-keys org.gnome.desktop.a11y.applications 2>/dev/null || true

echo 'ORCA_LAUNCHER_DIAGNOSTIC_DONE=yes'
