#!/usr/bin/env bash
set -euo pipefail

stamp=$(date +%Y%m%d-%H%M%S)
backup=/root/orca-mate-accessibility-backup-$stamp
mkdir -p "$backup"
cp -a /usr/local/bin/egor-mate-session "$backup/" 2>/dev/null || true
cp -a /usr/local/bin/orca-egor-launcher "$backup/" 2>/dev/null || true
cp -a /home/egor/.config/autostart "$backup/" 2>/dev/null || true

echo '===== ENABLE ACCESSIBILITY IN LIVE USER SESSION ====='
pid=$(pgrep -u egor -x mate-session | head -1 || true)
if [ -n "$pid" ]; then
  getv() { tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
  DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
  DISPLAY_VAL=$(getv DISPLAY)
  XDG_VAL=$(getv XDG_RUNTIME_DIR)
  [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
  [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
  if [ -n "$DBUS_VAL" ]; then
    sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" \
      gsettings set org.mate.interface accessibility true
    sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" \
      gsettings set org.gnome.desktop.interface toolkit-accessibility true
    sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" \
      gsettings set org.gnome.desktop.a11y.applications screen-reader-enabled true
  fi
fi

# Prevent MATE's stock Orca autostart from racing our controlled launcher.
install -d -o egor -g egor /home/egor/.config/autostart
cat >/home/egor/.config/autostart/orca-autostart.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Orca Screen Reader (managed by egor-mate-session)
Exec=/bin/true
Hidden=true
NoDisplay=true
X-GNOME-Autostart-enabled=false
X-MATE-Autostart-enabled=false
EOF
chown egor:egor /home/egor/.config/autostart/orca-autostart.desktop
chmod 0644 /home/egor/.config/autostart/orca-autostart.desktop

cat >/usr/local/bin/egor-mate-session <<'EOF'
#!/bin/bash
set -u

export LANG=ru_RU.UTF-8
export LANGUAGE=ru_RU:ru
export LC_ALL=ru_RU.UTF-8
export GTK_MODULES=gail:atk-bridge
export NO_AT_BRIDGE=0
export QT_ACCESSIBILITY=1
export XDG_CURRENT_DESKTOP=MATE
export DESKTOP_SESSION=mate

mkdir -p "$HOME/.local/state/orca"

# Make accessibility part of the session itself, rather than relying on a
# separate late autostart toggle.
gsettings set org.mate.interface accessibility true 2>/dev/null || true
gsettings set org.gnome.desktop.interface toolkit-accessibility true 2>/dev/null || true
gsettings set org.gnome.desktop.a11y.applications screen-reader-enabled true 2>/dev/null || true

# Start Orca only after AT-SPI + the main MATE surfaces exist. Starting it
# before panel/Caja were present was the source of the initial "empty" focus.
(
  for i in $(seq 1 80); do
    if pgrep -u "$(id -u)" -x mate-panel >/dev/null 2>&1 && \
       pgrep -u "$(id -u)" -x caja >/dev/null 2>&1 && \
       pgrep -u "$(id -u)" -f at-spi2-registryd >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done
  sleep 0.5
  exec /usr/local/bin/orca-egor-launcher
) &

exec mate-session
EOF
chmod 0755 /usr/local/bin/egor-mate-session

cat >/usr/local/bin/orca-egor-launcher <<'EOF'
#!/bin/bash
set -u

NEW_ORCA=/opt/orca-51/bin/orca
SYSTEM_ORCA=/usr/bin/orca
DEBUG_FILE="$HOME/.local/state/orca/orca-debug.log"
FALLBACK_LOG="$HOME/.local/state/orca/orca-launcher.log"
mkdir -p "$(dirname "$DEBUG_FILE")"

# Do not use --replace on normal startup: there should be exactly one Orca,
# and replacing an already-speaking instance creates a focus gap.
if [ -x "$NEW_ORCA" ]; then
  export PATH="/opt/orca-51/bin:$PATH"
  export LD_LIBRARY_PATH="/opt/orca-51/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export GI_TYPELIB_PATH="/opt/orca-51/lib/x86_64-linux-gnu/girepository-1.0${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
  export PYTHONPATH="/opt/orca-51/lib/python3/dist-packages${PYTHONPATH:+:$PYTHONPATH}"
  export GSETTINGS_SCHEMA_DIR=/opt/orca-51/share/glib-2.0/schemas

  "$NEW_ORCA" --debug-file "$DEBUG_FILE"
  status=$?
  printf '%s Orca 51 exited with status %s; starting system Orca 46.1\n' \
    "$(date --iso-8601=seconds)" "$status" >> "$FALLBACK_LOG"

  unset LD_LIBRARY_PATH GI_TYPELIB_PATH PYTHONPATH GSETTINGS_SCHEMA_DIR
fi

exec "$SYSTEM_ORCA" --debug-file "$DEBUG_FILE"
EOF
chmod 0755 /usr/local/bin/orca-egor-launcher

# Optional inspection support; failure here must not affect the desktop.
DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pyatspi >/dev/null 2>&1 || true

echo '===== VERIFY PERSISTENT SETTINGS ====='
if [ -n "${DBUS_VAL:-}" ]; then
  sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" sh -c '
    printf "mate accessibility: "; gsettings get org.mate.interface accessibility
    printf "toolkit accessibility: "; gsettings get org.gnome.desktop.interface toolkit-accessibility
    printf "screen reader: "; gsettings get org.gnome.desktop.a11y.applications screen-reader-enabled
  '
fi

echo '===== VERIFY STARTUP FILES ====='
bash -n /usr/local/bin/egor-mate-session
bash -n /usr/local/bin/orca-egor-launcher
grep -E 'accessibility true|screen-reader-enabled true|mate-panel|caja|at-spi2-registryd' /usr/local/bin/egor-mate-session
grep -E 'NEW_ORCA|--debug-file|--replace' /usr/local/bin/orca-egor-launcher || true

echo '===== CURRENT DESKTOP UNTOUCHED ====='
systemctl is-active egor-desktop.service
pgrep -a -u egor -x orca || true
pgrep -a -u egor -x mate-panel || true
pgrep -a -u egor -x caja || true

echo "BACKUP=$backup"
echo 'MATE_ORCA_STARTUP_FIXED=yes'
echo 'DESKTOP_RESTART_NOT_PERFORMED=yes'
