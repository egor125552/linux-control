#!/usr/bin/env bash
set -euo pipefail
root=/opt/audio-remote/audio_remote

echo '===== SERVICE ====='
systemctl is-active audio-remote.service
systemctl show audio-remote.service -p MainPID -p NRestarts -p ActiveEnterTimestamp --no-pager

echo '===== CODE CHECK ====='
python3 -m py_compile "$root/audio.py" "$root/server.py"
grep -q -- '--latency-msec=80' "$root/audio.py"
grep -q 'await asyncio.sleep(8)' "$root/server.py"
grep -q 'scheduleReconnect(4000)' "$root/static/app.js"
echo STABILITY_CODE_PRESENT=yes

echo '===== RECENT SERVICE ERRORS ====='
journalctl -u audio-remote.service --since '10 minutes ago' --no-pager 2>/dev/null \
  | grep -Ei 'traceback|error|exception|failed|invalidstate|transactiontimeout' | tail -120 || true

echo '===== CURRENT TRACKS ====='
ps -o pid=,ppid=,stat=,etimes=,args= -u egor | grep '[p]arec --device=Xpra-Speaker.monitor' || true

echo '===== RHVOICE ====='
tail -n 80 /run/egor-desktop/speech-dispatcher/log/rhvoice.log 2>/dev/null \
  | grep -Ei 'Audio output initialized|Audio output initialization error|ERROR AUDIO|playback stream' | tail -30 || true

echo AUDIO_STABILITY_POSTCHECK=yes
