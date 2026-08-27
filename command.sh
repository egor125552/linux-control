#!/usr/bin/env bash
set -euo pipefail

echo '===== APP CONNECTION LOGIC ====='
sed -n '1,240p' /opt/audio-remote/audio_remote/static/app.js

echo '===== CURRENT WEBRTC CONNECTIONS ====='
journalctl -u audio-remote.service --since '-20 min' --no-pager -n 300 2>&1 || true

echo DONE
