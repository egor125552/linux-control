#!/usr/bin/env bash
set -euo pipefail
file=/usr/lib/python3/dist-packages/orca/speechdispatcherfactory.py
stamp=$(date +%Y%m%d-%H%M%S)
backup="/root/speechdispatcherfactory-before-mark-fix-$stamp.py"
cp -a "$file" "$backup"
echo "BACKUP=$backup"

python3 - <<'PY'
p='/usr/lib/python3/dist-packages/orca/speechdispatcherfactory.py'
s=open(p,encoding='utf-8').read()
old='        ssml = SSML.markupText(text, SSMLCapabilities.MARK)\n'
new='        # Ordinary Orca utterances do not install a Speech Dispatcher callback.\n        # Adding INDEX_MARK tags anyway can make speech-dispatcher/RHVoice report\n        # marks to a client which is not listening for them. Keep marks only for\n        # operations such as Say All which actually pass a callback.\n        capabilities = SSMLCapabilities.MARK if kwargs.get("callback") else SSMLCapabilities(0)\n        ssml = SSML.markupText(text, capabilities)\n'
if old not in s:
    raise SystemExit('EXPECTED_MARK_LINE_NOT_FOUND')
s=s.replace(old,new,1)
open(p,'w',encoding='utf-8').write(s)
PY

python3 -m py_compile "$file"
grep -nA8 -B3 'capabilities = SSMLCapabilities.MARK' "$file"

# Restart only Orca, preserving the desktop, Xpra and audio bridge.
launcher_pid=$(pgrep -u egor -f '/usr/local/bin/orca-egor-launcher' | head -1 || true)
mate_pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$mate_pid" ] || { echo NO_MATE_SESSION; exit 1; }

# Stop the current reader cleanly.
pkill -TERM -u egor -x orca 2>/dev/null || true
sleep 1

# Start through the known-good launcher using the live MATE session environment.
python3 - "$mate_pid" <<'PY'
import os, sys, subprocess
pid=sys.argv[1]
raw=open(f'/proc/{pid}/environ','rb').read().split(b'\0')
env={}
for item in raw:
    if b'=' in item:
        k,v=item.split(b'=',1)
        env[k.decode(errors='ignore')]=v.decode(errors='ignore')
env['HOME']='/home/egor'
env.setdefault('DISPLAY',':100')
env.setdefault('XDG_RUNTIME_DIR','/run/egor-desktop')
log=open('/home/egor/.local/state/orca/mark-fix-restart.log','ab',buffering=0)
subprocess.Popen(
    ['/usr/bin/sudo','-u','egor','/usr/local/bin/orca-egor-launcher'],
    env=env,
    stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True,
)
PY
sleep 4

echo '===== NEW ORCA / SPEECH ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,%cpu=,comm=,args= | grep -E '[o]rca|[s]peech-dispatch|[s]d_rhvoice' || true

echo '===== NEW ERRORS ====='
tail -n 80 /run/egor-desktop/speech-dispatcher/log/speech-dispatcher.log 2>/dev/null | grep -Ei 'error|index mark|bad file|неправильный дескриптор|module' || true
tail -n 80 /home/egor/.local/state/orca/mark-fix-restart.log 2>/dev/null || true

echo ORCA_INDEX_MARK_FIX_APPLIED=yes
