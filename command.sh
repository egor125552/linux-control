#!/usr/bin/env bash
set -euo pipefail
mate_pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$mate_pid" ] || { echo NO_MATE_SESSION; exit 1; }
getenvp(){ local p="$1" k="$2"; tr '\0' '\n' < "/proc/$p/environ" | sed -n "s/^${k}=//p" | head -1; }
DISPLAY_VAL=$(getenvp "$mate_pid" DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getenvp "$mate_pid" XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
DBUS_VAL=$(getenvp "$mate_pid" DBUS_SESSION_BUS_ADDRESS)
PULSE_SERVER_VAL=$(getenvp "$mate_pid" PULSE_SERVER)
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" PULSE_SERVER="$PULSE_SERVER_VAL")

launcher=/usr/local/bin/orca-egor-launcher
latest_backup=$(ls -1t /root/orca-launcher-before-pulse-cookie-fix-* 2>/dev/null | head -1 || true)
[ -n "$latest_backup" ] || { echo NO_LAUNCHER_BACKUP; exit 1; }
cp -a "$latest_backup" "$launcher"
chmod 0755 "$launcher"
bash -n "$launcher"

echo 'LAUNCHER_RESTORED=yes'

python3 - <<'PY'
p='/usr/local/bin/orca-egor-launcher'
s=open(p,encoding='utf-8').read()
needle='mkdir -p "$(dirname "$DEBUG_FILE")"\n'
insert='''mkdir -p "$(dirname "$DEBUG_FILE")"\n\n# Xpra's PulseAudio server requires a per-session authentication cookie.\n# MATE inherits PULSE_SERVER but not PULSE_COOKIE, so discover the current\n# 256-byte cookie locally at Orca startup without hard-coding or logging it.\nif [ -n "${PULSE_SERVER:-}" ] && [ -z "${PULSE_COOKIE:-}" ]; then\n  pulse_cookie=$(find "$XDG_RUNTIME_DIR" "$HOME/.config/pulse" "$HOME/.pulse" /tmp \\\n    -maxdepth 6 -type f -user "$(id -un)" -size 256c 2>/dev/null \\\n    | grep -E '(^|/)[^/]*cookie[^/]*$' | head -1 || true)\n  if [ -n "$pulse_cookie" ]; then\n    export PULSE_COOKIE="$pulse_cookie"\n  fi\nfi\n'''
if 'pulse_cookie=$(find' not in s:
    if needle not in s:
        raise SystemExit('LAUNCHER_INSERT_POINT_NOT_FOUND')
    s=s.replace(needle,insert,1)
open(p,'w',encoding='utf-8').write(s)
PY
chmod 0755 "$launcher"
bash -n "$launcher"

echo 'LAUNCHER_PATCH_SYNTAX_OK=yes'

echo '===== PERSISTENT COOKIE LOGIC ====='
grep -nE 'PULSE_COOKIE|pulse_cookie|PulseAudio server requires' "$launcher" | sed -E 's#(PULSE_COOKIE=).*#\1<runtime>#; s#(pulse_cookie=).*#\1<runtime>#' || true

# Prove the launcher will discover a working cookie without exposing it.
COOKIE=$(sudo -u egor "${RUNENV[@]}" bash -c '
  pulse_cookie=$(find "$XDG_RUNTIME_DIR" "$HOME/.config/pulse" "$HOME/.pulse" /tmp -maxdepth 6 -type f -user "$(id -un)" -size 256c 2>/dev/null | grep -E "(^|/)[^/]*cookie[^/]*$" | head -1 || true)
  printf "%s" "$pulse_cookie"
')
[ -n "$COOKIE" ] && [ -f "$COOKIE" ] || { echo DISCOVERED_COOKIE_VALID=no; exit 1; }
echo DISCOVERED_COOKIE_VALID=yes
if sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" PULSE_SERVER="$PULSE_SERVER_VAL" PULSE_COOKIE="$COOKIE" pactl info >/dev/null 2>&1; then
  echo DISCOVERED_COOKIE_PULSE_OK=yes
else
  echo DISCOVERED_COOKIE_PULSE_OK=no
  exit 1
fi

# Restart only Orca and its speech backend. MATE, Xpra and PulseAudio stay alive.
for p in $(pgrep -u egor -x orca || true); do
  st=$(ps -o stat= -p "$p" 2>/dev/null | xargs || true)
  case "$st" in Z*) ;; *) kill "$p" 2>/dev/null || true;; esac
done
pkill -u egor -x speech-dispatcher 2>/dev/null || true
pkill -u egor -x sd_rhvoice 2>/dev/null || true
sleep 0.8
if ! pgrep -u egor -x speech-dispatcher >/dev/null 2>&1; then
  rm -f /run/egor-desktop/speech-dispatcher/speechd.sock 2>/dev/null || true
fi

sudo -u egor "${RUNENV[@]}" bash -c '
  export RUNNER_TRACKING_ID=
  setsid -f /usr/local/bin/orca-egor-launcher >"$HOME/.local/state/orca/pulse-cookie-restart.log" 2>&1
'

live=''
for i in $(seq 1 80); do
  for p in $(pgrep -u egor -x orca || true); do
    st=$(ps -o stat= -p "$p" 2>/dev/null | xargs || true)
    case "$st" in Z*) ;; *) live="$p"; break;; esac
  done
  [ -n "$live" ] && break
  sleep 0.25
done
[ -n "$live" ] || { echo LIVE_ORCA=no; tail -n 80 /home/egor/.local/state/orca/pulse-cookie-restart.log 2>/dev/null || true; exit 1; }
sleep 2

echo "LIVE_ORCA_PID=$live"
ORCA_COOKIE=$(getenvp "$live" PULSE_COOKIE)
printf 'ORCA_PULSE_COOKIE_PRESENT='; [ -n "$ORCA_COOKIE" ] && echo yes || echo no
printf 'ORCA_PULSE_COOKIE_EXISTS='; [ -n "$ORCA_COOKIE" ] && [ -f "$ORCA_COOKIE" ] && echo yes || echo no
if [ -n "$ORCA_COOKIE" ] && sudo -u egor env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" PULSE_SERVER="$PULSE_SERVER_VAL" PULSE_COOKIE="$ORCA_COOKIE" pactl info >/dev/null 2>&1; then
  echo ORCA_PULSE_CONNECTIVITY=yes
else
  echo ORCA_PULSE_CONNECTIVITY=no
  exit 1
fi

echo '===== SPEECH BACKEND ====='
ps -u egor -o pid=,ppid=,stat=,comm=,args= | grep -Ei 'speech-dispatcher|sd_rhvoice' || true

echo '===== RHVOICE LATEST AUDIO STATUS ====='
tail -n 100 /run/egor-desktop/speech-dispatcher/log/rhvoice.log 2>/dev/null | grep -Ei 'RHVoice initialized|AUDIO|playback|started successfully|ERROR' | tail -60 || true

echo '===== ORCA START LOG ====='
tail -n 100 /home/egor/.local/state/orca/pulse-cookie-restart.log 2>/dev/null || true

echo ORCA_PULSE_COOKIE_FIX_READY=yes
