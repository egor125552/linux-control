#!/usr/bin/env bash
set -euo pipefail

echo '===== INSTALLED BRAILLE PACKAGES ====='
dpkg-query -W -f='${Package}\t${Status}\t${Version}\n' 2>/dev/null | grep -Ei 'brltty|brlapi|braille' || true

echo '===== BRLTTY SERVICE ====='
systemctl status brltty.service --no-pager -l 2>/dev/null || true
systemctl status brltty-udev.service --no-pager -l 2>/dev/null || true

echo '===== ORCA BRAILLE SETTING ====='
sudo -u egor env HOME=/home/egor dbus-run-session gsettings get org.gnome.orca braille-enabled 2>/dev/null || true

echo '===== APT SIMULATE REMOVE BRLTTY ====='
apt-get -s remove --purge brltty 2>/dev/null || true

echo '===== APT SIMULATE REMOVE PYTHON BRLAPI ====='
apt-get -s remove --purge python3-brlapi 2>/dev/null || true
