#!/usr/bin/env bash
set -euo pipefail
mate_pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$mate_pid" ] || { echo NO_MATE_SESSION; exit 1; }
getenvp(){ local p="$1" k="$2"; tr '\0' '\n' < "/proc/$p/environ" | sed -n "s/^${k}=//p" | head -1; }
DISPLAY_VAL=$(getenvp "$mate_pid" DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getenvp "$mate_pid" XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
DBUS_VAL=$(getenvp "$mate_pid" DBUS_SESSION_BUS_ADDRESS)
PULSE_SERVER_VAL=$(getenvp "$mate_pid" PULSE_SERVER)
COOKIE=$(find /run/egor-desktop /home/egor/.config/pulse /home/egor/.pulse /tmp -maxdepth 6 -type f -user egor -size 256c 2>/dev/null | grep -E '(^|/)[^/]*cookie[^/]*$' | head -1 || true)
[ -n "$COOKIE" ] && [ -f "$COOKIE" ] || { echo NO_WORKING_COOKIE; exit 1; }
PENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL" PULSE_SERVER="$PULSE_SERVER_VAL" PULSE_COOKIE="$COOKIE")

# First verify the output and monitor are present.
echo '===== PULSE DEVICES ====='
sudo -u egor "${PENV[@]}" pactl list short sinks
sudo -u egor "${PENV[@]}" pactl list short sources

# Generate a known continuous signal, play it through the exact Xpra speaker,
# and record the monitor locally. Any silence here means the server-side audio
# path itself is breaking before WebRTC/network transport.
work=/tmp/egor-audio-continuity
rm -rf "$work" && mkdir -p "$work"
ffmpeg -hide_banner -loglevel error -f lavfi -i 'sine=frequency=523.25:sample_rate=48000:duration=10' -ac 2 -c:a pcm_s16le "$work/tone.wav"

sudo -u egor "${PENV[@]}" timeout 12 parec --device=Xpra-Speaker.monitor --file-format=wav "$work/capture.wav" >/dev/null 2>&1 &
rec=$!
sleep 0.7
sudo -u egor "${PENV[@]}" paplay --device=Xpra-Speaker "$work/tone.wav"
wait "$rec" || true

echo '===== LOCAL CONTINUITY ANALYSIS ====='
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$work/capture.wav" | sed 's/^/CAPTURE_DURATION=/'
# Report silence only; a 10-second tone should have no mid-stream silence.
ffmpeg -hide_banner -nostats -i "$work/capture.wav" -af silencedetect=noise=-45dB:d=0.08 -f null - 2>&1 | grep -E 'silence_(start|end|duration)' || true

# Inspect current speech backend after the cookie repair.
echo '===== RHVOICE CURRENT HEALTH ====='
tail -n 160 /run/egor-desktop/speech-dispatcher/log/rhvoice.log 2>/dev/null | grep -Ei 'audio|playback|error|started|initialized' | tail -80 || true

echo '===== SPEECHD CURRENT HEALTH ====='
find /run/egor-desktop/speech-dispatcher/log -maxdepth 1 -type f -name '*.log' -print0 2>/dev/null \
 | xargs -0 -r grep -H -Ei 'error|audio not initialized|playback stream|broken|underrun|timeout' 2>/dev/null \
 | tail -100 || true

# Inspect only source-code lines relevant to audio transport; never dump env/config secrets.
echo '===== AUDIO REMOTE IMPLEMENTATION HINTS ====='
grep -RInE --exclude='*.env' --exclude='*.pem' --exclude='*.key' --exclude='*.json' \
  'AudioStreamTrack|MediaStreamTrack|AudioFrame|pulse|parec|ffmpeg|sample_rate|samples|pts|time_base|queue|jitter|sleep\(' \
  /opt/audio-remote/audio_remote 2>/dev/null | head -220 || true

echo '===== AUDIO REMOTE RECENT LIVE ERRORS ====='
journalctl -u audio-remote.service --since '30 minutes ago' --no-pager 2>/dev/null \
 | grep -Ei 'error|exception|audio|track|packet|rtp|ice|consent|drop|late|jitter|underflow|overflow' \
 | tail -180 || true

echo AUDIO_CONTINUITY_ISOLATION_DONE=yes
