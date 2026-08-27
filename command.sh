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

work=/tmp/egor-audio-continuity
rm -rf "$work" && mkdir -p "$work"
python3 - <<'PY'
import math, wave, struct
rate=48000
dur=10.0
amp=12000
with wave.open('/tmp/egor-audio-continuity/tone.wav','wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
    for i in range(int(rate*dur)):
        s=int(amp*math.sin(2*math.pi*523.25*i/rate))
        w.writeframesraw(struct.pack('<hh',s,s))
PY

sudo -u egor "${PENV[@]}" timeout 12 parec --device=Xpra-Speaker.monitor --file-format=wav "$work/capture.wav" >/dev/null 2>&1 &
rec=$!
sleep 0.6
sudo -u egor "${PENV[@]}" paplay --device=Xpra-Speaker "$work/tone.wav"
wait "$rec" || true

python3 - <<'PY'
import wave, struct
p='/tmp/egor-audio-continuity/capture.wav'
with wave.open(p,'rb') as w:
    rate=w.getframerate(); ch=w.getnchannels(); n=w.getnframes(); raw=w.readframes(n)
vals=struct.unpack('<'+'h'*(len(raw)//2),raw)
mono=[]
for i in range(0,len(vals),ch):
    mono.append(max(abs(x) for x in vals[i:i+ch]))
threshold=250
silent=[v<threshold for v in mono]
# Find silence runs >= 80 ms, excluding leading/trailing silence around the 10s playback.
runs=[]; start=None
for i,s in enumerate(silent):
    if s and start is None: start=i
    if not s and start is not None:
        if i-start >= int(rate*0.08): runs.append((start/rate,(i-start)/rate))
        start=None
if start is not None and len(silent)-start >= int(rate*0.08): runs.append((start/rate,(len(silent)-start)/rate))
duration=len(mono)/rate
mid=[r for r in runs if r[0] > 0.4 and r[0]+r[1] < duration-0.4]
print(f'CAPTURE_DURATION={duration:.3f}')
print(f'SILENCE_RUNS_TOTAL={len(runs)}')
print(f'MIDSTREAM_SILENCE_RUNS={len(mid)}')
for st,d in mid[:20]: print(f'MID_SILENCE start={st:.3f} duration={d:.3f}')
PY

echo '===== RHVOICE CURRENT HEALTH ====='
tail -n 180 /run/egor-desktop/speech-dispatcher/log/rhvoice.log 2>/dev/null | grep -Ei 'audio|playback|error|started|initialized' | tail -100 || true

echo '===== AUDIO REMOTE IMPLEMENTATION HINTS ====='
grep -RInE --exclude='*.env' --exclude='*.pem' --exclude='*.key' --exclude='*.json' \
  'AudioStreamTrack|MediaStreamTrack|AudioFrame|pulse|parec|sample_rate|samples|pts|time_base|queue|jitter|sleep\(' \
  /opt/audio-remote/audio_remote 2>/dev/null | head -260 || true

echo '===== AUDIO REMOTE RECENT LIVE ERRORS ====='
journalctl -u audio-remote.service --since '45 minutes ago' --no-pager 2>/dev/null \
 | grep -Ei 'error|exception|audio|track|packet|rtp|ice|consent|drop|late|jitter|underflow|overflow' \
 | tail -220 || true

echo AUDIO_CONTINUITY_MEASURED=yes
