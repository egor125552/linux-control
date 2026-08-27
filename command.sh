#!/usr/bin/env bash
set -euo pipefail
export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'

python3 - <<'PY' >/tmp/silence.raw
import sys
sys.stdout.buffer.write(b'\0\0' * 48000 * 25)
PY
runuser -u egor -- env PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" \
  pacat --playback --raw --device=Xpra-Speaker --format=s16le --rate=48000 --channels=1 </tmp/silence.raw >/tmp/pacat.out 2>/tmp/pacat.err &
player=$!

runuser -u egor -- env PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" \
  /opt/audio-remote/.venv/bin/python - <<'PY'
import asyncio, statistics, time

async def measure(lat):
    p=await asyncio.create_subprocess_exec(
        'parec','--device=Xpra-Speaker.monitor','--format=s16le','--rate=48000','--channels=1',f'--latency-msec={lat}',
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    assert p.stdout
    times=[]
    prev=time.perf_counter()
    try:
        for i in range(220):
            await asyncio.wait_for(p.stdout.readexactly(960*2), timeout=1)
            now=time.perf_counter()
            if i: times.append((now-prev)*1000)
            prev=now
    finally:
        p.terminate()
        try: await asyncio.wait_for(p.wait(),.5)
        except: p.kill()
    s=sorted(times)
    q=lambda x:s[min(len(s)-1,int((len(s)-1)*x))]
    print(f'LAT={lat} mean={statistics.mean(times):.3f} p50={q(.5):.3f} p95={q(.95):.3f} p99={q(.99):.3f} max={max(times):.3f} gt25={sum(x>25 for x in times)} gt30={sum(x>30 for x in times)} gt40={sum(x>40 for x in times)} lt10={sum(x<10 for x in times)}')

async def main():
    for lat in (20,30,40,60,80,100,120):
        await measure(lat)
        await asyncio.sleep(.25)
asyncio.run(main())
PY
wait "$player" || true
cat /tmp/pacat.err || true

echo DONE
