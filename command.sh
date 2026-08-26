#!/usr/bin/env bash
set -euo pipefail

echo '===== DESKTOP SERVICE ====='
systemctl status egor-desktop.service --no-pager -l || true
systemctl cat egor-desktop.service || true

echo '===== DESKTOP / ORCA PROCESSES ====='
ps -eo user,pid,ppid,etimes,cmd | grep -E 'xpra|Xvfb|mate-session|mate-panel|marco|caja|orca|at-spi|dbus-daemon|speech-dispatcher' | grep -v grep || true

echo '===== DESKTOP SERVICE LOG ====='
journalctl -u egor-desktop.service -b --no-pager -n 180 | sed -n '1,180p' || true

echo '===== USER AUTOSTART FILES ====='
find /home/egor/.config/autostart -maxdepth 1 -type f -name '*.desktop' -print 2>/dev/null || true
for f in /home/egor/.config/autostart/*.desktop; do
  [ -f "$f" ] || continue
  echo "--- $f"
  sed -n '1,160p' "$f"
done

echo '===== ORCA FILES ====='
find /home/egor/.local/share/orca /home/egor/.config/orca -maxdepth 2 -type f -printf '%p\n' 2>/dev/null | sed -n '1,120p' || true
for f in /home/egor/.local/share/orca/user-settings.conf /home/egor/.config/orca/user-settings.conf; do
  [ -f "$f" ] || continue
  echo "--- $f"
  sed -n '1,220p' "$f" | grep -Ev '(password|token|secret|key)' || true
done

echo '===== ACCESSIBILITY SETTINGS FROM USER DB ====='
sudo -u egor env HOME=/home/egor dbus-run-session -- sh -c '
  echo -n "mate accessibility: "; gsettings get org.mate.interface accessibility 2>&1 || true
  echo -n "gnome screen-reader: "; gsettings get org.gnome.desktop.a11y.applications screen-reader-enabled 2>&1 || true
  echo -n "toolkit accessibility: "; gsettings get org.gnome.desktop.interface toolkit-accessibility 2>&1 || true
  echo -n "mate session required: "; gsettings get org.mate.session required-components 2>&1 || true
' || true

echo '===== INSTALLED ACCESSIBILITY PACKAGES ====='
dpkg-query -W -f='${Package}\t${Version}\n' 2>/dev/null | grep -E '^(orca|at-spi2|libatk|speech-dispatcher|mate-session-manager|mate-panel|caja|marco|xpra)' | sort || true

echo '===== DESKTOP STARTUP FILE CANDIDATES ====='
for f in /usr/local/bin/egor-desktop /usr/local/sbin/egor-desktop /home/egor/start-desktop.sh /home/egor/.xsession /home/egor/.xinitrc; do
  [ -f "$f" ] || continue
  echo "--- $f"
  sed -n '1,240p' "$f" | grep -Ev '(password|token|secret|private.key|authorization)' || true
done

echo '===== MATE ACCESSIBILITY AUTOSTART SYSTEM FILES ====='
grep -RIlE 'orca|at-spi|accessib' /etc/xdg/autostart /usr/share/mate/autostart 2>/dev/null | sed -n '1,100p' || true

echo 'ACCESSIBILITY_DIAGNOSTIC_DONE=yes'
