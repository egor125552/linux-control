#!/usr/bin/env bash
set -euo pipefail

export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'

echo '===== LOCAL CAPTURE TIMING TEST ====='
# Feed silence into the real sink so the monitor stays active without making sound.
python3 - <<'PY' >/tmp/silence.raw
import sys
sys.stdout.buffer.write(b'\0\0' * 48000 * 6)
PY
runuser -u egor -- env PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" \
  pacat --playback --raw --device=Xpra-Speaker --format=s16le --rate=48000 --channels=1 </tmp/silence.raw >/tmp/pacat.out 2>/tmp/pacat.err &
player=$!

runuser -u egor -- env PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" \
  /opt/audio-remote/.venv/bin/python - <<'PY'
import asyncio, statistics, sys, time
sys.path.insert(0, '/opt/audio-remote')
from audio_remote.audio import PulseAudioTrack

async def main():
    t = PulseAudioTrack('Xpra-Speaker.monitor')
    times=[]
    sizes=[]
    prev=time.perf_counter()
    try:
        for i in range(220):
            f=await asyncio.wait_for(t.recv(), timeout=1.0)
            now=time.perf_counter()
            if i:
                times.append((now-prev)*1000)
            prev=now
            sizes.append(f.samples)
    finally:
        t.stop()
    s=sorted(times)
    def p(q):
        return s[min(len(s)-1, int((len(s)-1)*q))]
    print('frames', len(times)+1)
    print('samples_unique', sorted(set(sizes)))
    print('interval_ms_mean', round(statistics.mean(times),3))
    print('interval_ms_p50', round(p(.50),3))
    print('interval_ms_p95', round(p(.95),3))
    print('interval_ms_p99', round(p(.99),3))
    print('interval_ms_max', round(max(times),3))
    print('over_25ms', sum(x>25 for x in times))
    print('over_30ms', sum(x>30 for x in times))
    print('over_40ms', sum(x>40 for x in times))
    print('under_10ms', sum(x<10 for x in times))

asyncio.run(main())
PY

wait "$player" || true
cat /tmp/pacat.err || true

echo '===== PULSE LATENCY DURING/AFTER TEST ====='
runuser -u egor -- env PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" pactl list sinks | sed -n '/Имя: Xpra-Speaker/,/Форматы:/p' || true

echo '===== RECENT PULSE WARNINGS ====='
journalctl -u egor-desktop.service --since '-5 min' --no-pager | grep -Ei 'asyncq|overrun|underrun|drop|buffer|latenc|pulse' | tail -n 120 || true

echo DONE
