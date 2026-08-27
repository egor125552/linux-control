#!/usr/bin/env bash
set -euo pipefail

echo '===== APP.JS ====='
sed -n '1,360p' /opt/audio-remote/audio_remote/static/app.js 2>/dev/null \
 | sed -E 's#(token|password|secret|authorization)([^=]*=).*#\1\2<redacted>#Ig' || true

echo '===== INDEX AUDIO ELEMENT ====='
grep -nEi 'audio|autoplay|playsinline|button|connect|start' /opt/audio-remote/audio_remote/static/index.html 2>/dev/null | head -220 || true

echo '===== RECONNECT/TIMER REFERENCES ====='
grep -RInE --exclude='*.env' --exclude='*.pem' --exclude='*.key' \
  'setInterval|setTimeout|restartIce|createOffer|new RTCPeerConnection|connectionstatechange|iceconnectionstatechange|visibilitychange|pageshow|focus|blur|play\(|pause\(|srcObject|ontrack|reconnect|connect\(' \
  /opt/audio-remote/audio_remote/static 2>/dev/null | head -320 || true

echo BROWSER_WEBRTC_LOGIC_INSPECT_DONE=yes
