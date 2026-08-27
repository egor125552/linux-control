#!/usr/bin/env bash
set -euo pipefail
stamp=$(date +%Y%m%d-%H%M%S)
cp -a /usr/local/bin/orca-egor-launcher "/root/orca-egor-launcher-before-no46-$stamp"

python3 - <<'PY'
p='/usr/local/bin/orca-egor-launcher'
s=open(p,encoding='utf-8').read()
# Rebuild only the tail after environment setup so there is exactly one Orca target.
marker='# Do not use --replace on normal startup:'
pos=s.find(marker)
if pos < 0:
    raise SystemExit('LAUNCHER_MARKER_NOT_FOUND')
prefix=s[:pos]
tail='''# Orca 51 is the only permitted screen reader in this session.\n# No fallback to the distro Orca 46.1 is allowed.\nexport PATH="/opt/orca-51/bin:$PATH"\nexport LD_LIBRARY_PATH="/opt/orca-51/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\nexport GI_TYPELIB_PATH="/opt/orca-51/lib/x86_64-linux-gnu/girepository-1.0${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"\nexport PYTHONPATH="/opt/orca-51/lib/python3/dist-packages${PYTHONPATH:+:$PYTHONPATH}"\nexport GSETTINGS_SCHEMA_DIR=/opt/orca-51/share/glib-2.0/schemas\n\nexec /opt/orca-51/bin/orca --debug-file "$DEBUG_FILE"\n'''
s=prefix+tail
# Remove obsolete variables if present in the preserved prefix.
s=s.replace('SYSTEM_ORCA=/opt/orca-51/bin/orca\n','')
s=s.replace('NEW_ORCA=/opt/orca-51/bin/orca\n','')
s=s.replace('FALLBACK_LOG="$HOME/.local/state/orca/orca-launcher.log"\n','')
open(p,'w',encoding='utf-8').write(s)
PY
chmod 0755 /usr/local/bin/orca-egor-launcher
bash -n /usr/local/bin/orca-egor-launcher

echo '===== FINAL LAUNCHER ====='
sed -n '1,220p' /usr/local/bin/orca-egor-launcher

echo '===== NO 46 FALLBACK ASSERTIONS ====='
! grep -Eq 'SYSTEM_ORCA|/usr/bin/orca|46\.1|fallback|starting system Orca' /usr/local/bin/orca-egor-launcher
grep -q 'exec /opt/orca-51/bin/orca' /usr/local/bin/orca-egor-launcher
grep -q '^Hidden=true$' /home/egor/.config/autostart/orca-autostart.desktop
echo NO_ORCA46_FALLBACK=yes

echo '===== CURRENT LIVE ORCA ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep '[o]rca' || true
live=$(pgrep -u egor -x orca | while read p; do st=$(awk '{print $3}' /proc/$p/stat 2>/dev/null || true); [ "$st" != Z ] && echo "$p"; done | tail -1)
[ -n "$live" ]
grep -q '/opt/orca-51/' /proc/$live/maps
echo "LIVE_ORCA51_PID=$live"
echo ORCA51_ONLY=yes
