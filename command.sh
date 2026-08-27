#!/usr/bin/env bash
set -euo pipefail

app=/opt/audio-remote/audio_remote/static/app.js
stamp=$(date +%Y%m%d-%H%M%S)
cp -a "$app" "/opt/audio-remote/audio_remote/static/app.js.before-reconnect-$stamp"
python3 - <<'PY'
p='/opt/audio-remote/audio_remote/static/app.js'
s=open(p,encoding='utf-8').read()
old='''  const pc = new RTCPeerConnection();\n  let ws = null;\n\n  try {'''
new='''  const pc = new RTCPeerConnection();\n  let ws = null;\n  let retryAfterFailure = false;\n\n  try {'''
if old not in s:
    raise SystemExit('RECONNECT_DECLARATION_MARKER_NOT_FOUND')
s=s.replace(old,new,1)
old2='''  } catch {\n    if (myGeneration === generation) {\n      setStatus("Связь восстанавливается…");\n      scheduleReconnect();\n    }\n    await closePeer(pc);\n    try { ws?.close(); } catch {}\n  } finally {\n    connecting = false;\n  }'''
new2='''  } catch {\n    if (myGeneration === generation) {\n      setStatus("Связь восстанавливается…");\n      retryAfterFailure = true;\n    }\n    await closePeer(pc);\n    try { ws?.close(); } catch {}\n  } finally {\n    connecting = false;\n    if (retryAfterFailure && myGeneration === generation) scheduleReconnect();\n  }'''
if old2 not in s:
    raise SystemExit('RECONNECT_CATCH_MARKER_NOT_FOUND')
s=s.replace(old2,new2,1)
open(p,'w',encoding='utf-8').write(s)
PY
chown egor:egor "$app"

echo '===== PATCHED RECONNECT BLOCK ====='
grep -n -A18 -B5 'retryAfterFailure' "$app"

if command -v node >/dev/null 2>&1; then
  node --check "$app"
  echo JS_SYNTAX_OK=yes
else
  echo JS_SYNTAX_CHECK_SKIPPED=node_missing
fi

echo '===== SERVICE STILL ACTIVE ====='
systemctl is-active audio-remote.service
systemctl show audio-remote.service -p MainPID --no-pager

echo RECONNECT_FIX_INSTALLED=yes
