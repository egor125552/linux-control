#!/usr/bin/env bash
set -euo pipefail

echo '===== AUDIO.PY ====='
sed -n '1,240p' /opt/audio-remote/audio_remote/audio.py 2>/dev/null || true

echo '===== SERVER.PY WEBRTC RELEVANT ====='
sed -n '1,320p' /opt/audio-remote/audio_remote/server.py 2>/dev/null \
 | sed -E 's#(token|password|secret|authorization)([^=]*=).*#\1\2<redacted>#Ig' || true

echo '===== OTHER WEBRTC FILES ====='
for f in /opt/audio-remote/audio_remote/*.py; do
  case "$f" in */audio.py|*/server.py) continue;; esac
  if grep -qE 'RTCPeerConnection|addTrack|connectionState|iceConnectionState|PulseAudioTrack|peer' "$f" 2>/dev/null; then
    echo "FILE=$f"
    grep -nE 'RTCPeerConnection|addTrack|connectionState|iceConnectionState|PulseAudioTrack|peer|close\(' "$f" | head -220
  fi
done

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

work=/tmp/egor-audio-continuity
rm -rf "$work" && mkdir -p "$work" && chown egor:egor "$work"
sudo -u egor python3 - <<'PY'
import math, wave, struct
rate=48000; dur=10.0; amp=12000
with wave.open('/tmp/egor-audio-continuity/tone.wav','wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
    frames=bytearray()
    for i in range(int(rate*dur)):
        s=int(amp*math.sin(2*math.pi*523.25*i/rate))
        frames += struct.pack('<hh',s,s)
    w.writeframes(frames)
PY

sudo -u egor "${PENV[@]}" bash -c 'timeout 12 parec --device=Xpra-Speaker.monitor --file-format=wav > /tmp/egor-audio-continuity/capture.wav' &
rec=$!
sleep 0.6
sudo -u egor "${PENV[@]}" paplay --device=Xpra-Speaker "$work/tone.wav"
wait "$rec" || true

if [ -s "$work/capture.wav" ]; then
  echo CAPTURE_CREATED=yes
  python3 - <<'PY'
import wave, struct
p='/tmp/egor-audio-continuity/capture.wav'
with wave.open(p,'rb') as w:
    rate=w.getframerate(); ch=w.getnchannels(); raw=w.readframes(w.getnframes())
vals=struct.unpack('<'+'h'*(len(raw)//2),raw)
mono=[max(abs(x) for x in vals[i:i+ch]) for i in range(0,len(vals),ch)]
threshold=250
runs=[]; start=None
for i,v in enumerate(mono):
    s=v<threshold
    if s and start is None: start=i
    elif not s and start is not None:
        if i-start >= int(rate*0.08): runs.append((start/rate,(i-start)/rate))
        start=None
if start is not None and len(mono)-start >= int(rate*0.08): runs.append((start/rate,(len(mono)-start)/rate))
dur=len(mono)/rate
# The tone begins about 0.6 sec after recording and lasts 10 sec.
mid=[r for r in runs if r[0] > 0.8 and r[0]+r[1] < 10.4]
print(f'CAPTURE_DURATION={dur:.3f}')
print(f'MIDSTREAM_SILENCE_RUNS={len(mid)}')
for st,d in mid[:30]: print(f'MID_SILENCE start={st:.3f} duration={d:.3f}')
PY
else
  echo CAPTURE_CREATED=no
fi

echo '===== CURRENT CONNECTION COUNTS ====='
ps -ef | grep -E '[p]arec|[a]udio_remote' || true
ss -uapn 2>/dev/null | grep -E 'python|audio-remote' | head -120 || true

echo WEBRTC_AUDIO_TRANSPORT_INSPECT_DONE=yes
