#!/usr/bin/env bash
set -euo pipefail

launcher=/usr/local/bin/orca-egor-launcher
stamp=$(date +%Y%m%d-%H%M%S)
cp -a "$launcher" "/root/orca-egor-launcher-before-pulse-fix-$stamp"

python3 - <<'PY'
p='/usr/local/bin/orca-egor-launcher'
s=open(p,encoding='utf-8').read()
start=s.find("# Xpra's PulseAudio server requires a per-session authentication cookie.")
end=s.find('# Orca 51 is the only permitted screen reader in this session.')
if start < 0 or end < 0 or end <= start:
    raise SystemExit('PULSE_BLOCK_MARKERS_NOT_FOUND')
block=r'''# Xpra owns the audio server for this desktop session.  Orca may be started
# outside MATE's inherited environment, so provide the server and its cookie
# explicitly instead of assuming PULSE_SERVER/PULSE_COOKIE already exist.
XPRA_PULSE_SOCKET=/run/egor-desktop/xpra/100/pulse/native
if [ -S "$XPRA_PULSE_SOCKET" ]; then
  export PULSE_SERVER="unix:$XPRA_PULSE_SOCKET"
fi

if [ -z "${PULSE_COOKIE:-}" ]; then
  literal_cookie="$HOME/.config/pulse/\$PULSE_COOKIE"
  if [ -r "$literal_cookie" ]; then
    export PULSE_COOKIE="$literal_cookie"
  else
    pulse_cookie=$(find "$HOME/.config/pulse" "$HOME/.pulse" /run/egor-desktop /tmp \
      -maxdepth 8 -type f -user "$(id -un)" -size 256c 2>/dev/null \
      | grep -Ei '(^|/)[^/]*cookie[^/]*$' | head -1 || true)
    if [ -n "$pulse_cookie" ]; then
      export PULSE_COOKIE="$pulse_cookie"
    fi
  fi
fi

'''
s=s[:start]+block+s[end:]
open(p,'w',encoding='utf-8').write(s)
PY

chmod 0755 "$launcher"
bash -n "$launcher"

echo '===== FIXED LAUNCHER PULSE BLOCK ====='
sed -n '1,80p' "$launcher"

echo '===== STATIC ASSERTIONS ====='
grep -q 'XPRA_PULSE_SOCKET=/run/egor-desktop/xpra/100/pulse/native' "$launcher"
grep -q 'literal_cookie=' "$launcher"
grep -q 'export PULSE_SERVER=' "$launcher"
grep -q 'export PULSE_COOKIE=' "$launcher"
echo LAUNCHER_PULSE_FIX_INSTALLED=yes

echo '===== CURRENT SPEECH STACK ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -E '[s]peech-dispatcher|[s]d_rhvoice|[o]rca' || true

echo '===== RHVOICE STATUS ====='
tail -n 12 /home/egor/.cache/speech-dispatcher/log/rhvoice.log 2>/dev/null || true
