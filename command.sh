#!/usr/bin/env bash
set -euo pipefail
stamp=$(date +%Y%m%d-%H%M%S)
backup=/root/orca51-force-backup-$stamp
mkdir -p "$backup"
cp -a /usr/local/bin/orca-egor-launcher "$backup/" 2>/dev/null || true
cp -a /home/egor/.config/autostart/orca-autostart.desktop "$backup/" 2>/dev/null || true
cp -a /etc/xdg/autostart/orca-autostart.desktop "$backup/" 2>/dev/null || true

echo "BACKUP=$backup"

test -x /opt/orca-51/bin/orca
/opt/orca-51/bin/orca --version || true

# Disable distro Orca autostart for this user. Our launcher is the only authority.
mkdir -p /home/egor/.config/autostart
cat >/home/egor/.config/autostart/orca-autostart.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Orca system autostart disabled
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
chown egor:egor /home/egor/.config/autostart/orca-autostart.desktop

# Force the custom launcher to execute Orca 51 by absolute path.
python3 - <<'PY'
p='/usr/local/bin/orca-egor-launcher'
s=open(p,encoding='utf-8').read()
# Replace any ordinary Orca exec/invocation with the exact 51 binary.
repls = [
    ('exec orca ', 'exec /opt/orca-51/bin/orca '),
    ('exec orca\n', 'exec /opt/orca-51/bin/orca\n'),
    ('/usr/bin/orca', '/opt/orca-51/bin/orca'),
]
for a,b in repls:
    s=s.replace(a,b)
# If launcher uses a variable, pin it explicitly near the top.
if 'ORCA_BIN=' in s:
    import re
    s=re.sub(r'^ORCA_BIN=.*$', 'ORCA_BIN=/opt/orca-51/bin/orca', s, flags=re.M)
elif '/opt/orca-51/bin/orca' not in s:
    lines=s.splitlines()
    insert=1 if lines and lines[0].startswith('#!') else 0
    lines.insert(insert, 'ORCA_BIN=/opt/orca-51/bin/orca')
    s='\n'.join(lines)+'\n'
    s=s.replace('"$ORCA_BIN"', '/opt/orca-51/bin/orca')
open(p,'w',encoding='utf-8').write(s)
PY
chmod 0755 /usr/local/bin/orca-egor-launcher
bash -n /usr/local/bin/orca-egor-launcher

echo '===== LAUNCHER ORCA REFERENCES ====='
grep -nE 'orca|ORCA_BIN' /usr/local/bin/orca-egor-launcher | head -120

# Stop every live Orca process. Zombies cannot be killed and are harmless here.
for p in $(pgrep -u egor -x orca || true); do
  state=$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)
  [ "$state" = Z ] && continue
  kill -TERM "$p" 2>/dev/null || true
done
sleep 1
for p in $(pgrep -u egor -x orca || true); do
  state=$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true)
  [ "$state" = Z ] && continue
  kill -KILL "$p" 2>/dev/null || true
done
sleep 1

mate_pid=$(pgrep -u egor -x mate-session | head -1)
python3 - "$mate_pid" <<'PY'
import os,sys,subprocess
pid=sys.argv[1]
env={}
for item in open(f'/proc/{pid}/environ','rb').read().split(b'\0'):
    if b'=' in item:
        k,v=item.split(b'=',1)
        env[k.decode(errors='ignore')]=v.decode(errors='ignore')
env['HOME']='/home/egor'
env.setdefault('DISPLAY',':100')
env.setdefault('XDG_RUNTIME_DIR','/run/egor-desktop')
log=open('/home/egor/.local/state/orca/orca51-force.log','ab',buffering=0)
subprocess.Popen(['/usr/bin/sudo','-u','egor','/usr/local/bin/orca-egor-launcher'],env=env,stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
PY
sleep 5

echo '===== LIVE ORCA ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep '[o]rca' || true

live=$(pgrep -u egor -x orca | while read p; do st=$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true); [ "$st" != Z ] && echo "$p"; done | tail -1)
[ -n "$live" ] || { echo NO_LIVE_ORCA; exit 1; }

echo "LIVE_PID=$live"
echo -n 'EXE='; readlink -f /proc/$live/exe || true
echo '===== MAPS ORCA PATHS ====='
grep -E '/opt/orca-51|/usr/lib/python3/dist-packages/orca' /proc/$live/maps 2>/dev/null | head -40 || true

echo '===== CMDLINE ====='
tr '\0' ' ' </proc/$live/cmdline; echo

echo '===== VERSION THROUGH EXACT BINARY ====='
/opt/orca-51/bin/orca --version || true

echo '===== 46 AUTOSTART BLOCK ====='
cat /home/egor/.config/autostart/orca-autostart.desktop

echo ORCA51_FORCED=yes
