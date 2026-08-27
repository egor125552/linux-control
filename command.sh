#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

entry=/opt/orca-51/bin/orca
stamp=$(date +%Y%m%d-%H%M%S)
backup=/root/orca51-entry-before-zombie-fix-$stamp
cp -a "$entry" "$backup"

python3 - <<'PY'
p='/opt/orca-51/bin/orca'
s=open(p,encoding='utf-8').read()
old='''    orcas = [int(p) for p in pids.split()]\n    pid = os.getpid()\n    return [p for p in orcas if p != pid]\n'''
new='''    orcas = [int(p) for p in pids.split()]\n    pid = os.getpid()\n\n    def is_zombie(other_pid: int) -> bool:\n        try:\n            with open(f"/proc/{other_pid}/stat", "r", encoding="utf-8") as stat_file:\n                stat = stat_file.read()\n            # /proc/<pid>/stat: state is the first field after the final ") ".\n            return stat.rsplit(") ", 1)[1].split()[0] == "Z"\n        except (OSError, IndexError):\n            return False\n\n    return [p for p in orcas if p != pid and not is_zombie(p)]\n'''
if old not in s:
    raise SystemExit('TARGET_BLOCK_NOT_FOUND')
s=s.replace(old,new,1)
open(p,'w',encoding='utf-8').write(s)
PY
chmod 0755 "$entry"
python3 -m py_compile "$entry"

echo '===== PATCHED OTHER_ORCAS ====='
sed -n '208,245p' "$entry"

# Stop only non-zombie Orca processes which are currently stuck in --replace cleanup.
for p in $(pgrep -u egor -x orca || true); do
  st=$(ps -o stat= -p "$p" 2>/dev/null | xargs || true)
  case "$st" in Z*) ;; *) kill "$p" 2>/dev/null || true;; esac
done
sleep 0.8

debugfile=/home/egor/.local/state/orca/virtual-cursor-final.log
rm -f "$debugfile"
sudo -u egor "${RUNENV[@]}" bash -c '
  export RUNNER_TRACKING_ID=
  export PATH="/opt/orca-51/bin:$PATH"
  export LD_LIBRARY_PATH="/opt/orca-51/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export GI_TYPELIB_PATH="/opt/orca-51/lib/x86_64-linux-gnu/girepository-1.0${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
  export PYTHONPATH="/opt/orca-51/lib/python3/dist-packages${PYTHONPATH:+:$PYTHONPATH}"
  export GSETTINGS_SCHEMA_DIR=/opt/orca-51/share/glib-2.0/schemas
  setsid -f /opt/orca-51/bin/orca --debug --debug-file /home/egor/.local/state/orca/virtual-cursor-final.log >/home/egor/.local/state/orca/virtual-cursor-final-stderr.log 2>&1
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
[ -n "$live" ] || { echo LIVE_ORCA=no; cat /home/egor/.local/state/orca/virtual-cursor-final-stderr.log 2>/dev/null || true; exit 1; }
sleep 2

echo "LIVE_ORCA_PID=$live"
echo '===== PROCESS STATES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep '[o]rca' || true

echo '===== EXTENSION STARTUP ====='
grep -Ei 'EXTENSION LOADER|EGOR ACCESSIBILITY|Failed to load|Failed to instantiate|Traceback|Exception|ERROR|CRITICAL' "$debugfile" | tail -n 240 || true

echo '===== STDERR ====='
cat /home/egor/.local/state/orca/virtual-cursor-final-stderr.log 2>/dev/null || true

if grep -q 'EGOR ACCESSIBILITY: VoiceOver-like virtual cursor active' "$debugfile"; then
  echo VOICEOVER_CURSOR_EXTENSION_LOADED=yes
else
  echo VOICEOVER_CURSOR_EXTENSION_LOADED=no
  cp -a "$backup" "$entry"
  chmod 0755 "$entry"
  echo ENTRYPOINT_RESTORED_AFTER_FAILURE=yes
  exit 1
fi

echo "ENTRYPOINT_BACKUP=$backup"
echo ORCA_ZOMBIE_FIX_AND_VIRTUAL_CURSOR_READY=yes
