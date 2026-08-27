#!/usr/bin/env bash
set -euo pipefail

echo '===== AUDIO REMOTE TREE ====='
find /opt/audio-remote -maxdepth 3 -type f | sort | sed -n '1,220p'

echo '===== ENV KEYS ONLY ====='
if [ -r /etc/audio-remote.env ]; then sed -E 's/^([^#=]+)=.*/\1=<redacted>/' /etc/audio-remote.env; fi

echo '===== SOURCE RELEVANT LINES ====='
grep -RnsEi --exclude-dir=.venv --exclude='*.pyc' 'pulse|sound|audio|frame|sample|rate|buffer|latenc|queue|opus|webrtc|MediaStreamTrack|recv|sleep|packet|ptime|jitter|48000|24000|960|480|120' /opt/audio-remote 2>/dev/null | head -n 500 || true

echo '===== SERVER SOURCE ====='
for f in /opt/audio-remote/audio_remote/*.py; do echo "--- $f ---"; sed -n '1,280p' "$f"; done

echo '===== PULSE XPRA CONFIG ====='
sed -n '1,260p' /etc/xpra/pulse/xpra.pa 2>/dev/null || true

echo '===== PULSE DAEMON CONF ====='
grep -nEv '^\s*(#|;|$)' /etc/pulse/daemon.conf 2>/dev/null || true

echo '===== AUDIO REMOTE PACKAGE VERSIONS ====='
/opt/audio-remote/.venv/bin/python - <<'PY'
import importlib.metadata as m
for n in ['aiortc','av','aioice','numpy','sounddevice','pulsectl']:
    try: print(n, m.version(n))
    except: pass
PY

echo DONE
