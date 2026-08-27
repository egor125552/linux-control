#!/usr/bin/env bash
set -euo pipefail

src=/opt/audio-remote/audio_remote/audio.py
stamp=$(date +%Y%m%d-%H%M%S)
cp -a "$src" "/opt/audio-remote/audio_remote/audio.py.before-pacing-$stamp"
cat > "$src" <<'PY'
import asyncio
import logging
from fractions import Fraction

from aiortc import MediaStreamTrack
from av import AudioFrame

logger = logging.getLogger(__name__)


class PulseAudioTrack(MediaStreamTrack):
    kind = "audio"

    def __init__(
        self,
        source: str,
        sample_rate: int = 48_000,
        frame_ms: int = 20,
        capture_latency_ms: int = 20,
        prebuffer_ms: int = 60,
    ) -> None:
        super().__init__()
        self.source = source
        self.sample_rate = sample_rate
        self.frame_ms = frame_ms
        self.frame_seconds = frame_ms / 1000
        self.samples = sample_rate * frame_ms // 1000
        self.frame_bytes = self.samples * 2
        self.silence = b"\0" * self.frame_bytes
        self.timestamp = 0
        self.capture_latency_ms = capture_latency_ms
        self.prebuffer_frames = max(1, prebuffer_ms // frame_ms)
        self.queue: asyncio.Queue[bytes] = asyncio.Queue(maxsize=max(6, self.prebuffer_frames * 2))
        self.process: asyncio.subprocess.Process | None = None
        self.reader_task: asyncio.Task | None = None
        self.ready = asyncio.Event()
        self.next_send_time: float | None = None
        self.dropped_frames = 0
        self.silence_frames = 0

    async def _start_process(self) -> None:
        self.process = await asyncio.create_subprocess_exec(
            "parec",
            f"--device={self.source}",
            "--format=s16le",
            f"--rate={self.sample_rate}",
            "--channels=1",
            f"--latency-msec={self.capture_latency_ms}",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )

    async def _stop_process(self) -> None:
        process = self.process
        self.process = None
        if not process or process.returncode is not None:
            return
        process.terminate()
        try:
            await asyncio.wait_for(process.wait(), timeout=0.5)
        except (asyncio.TimeoutError, ProcessLookupError):
            try:
                process.kill()
            except ProcessLookupError:
                pass

    async def _capture_loop(self) -> None:
        while self.readyState == "live":
            try:
                if self.process is None or self.process.returncode is not None:
                    await self._start_process()
                assert self.process and self.process.stdout
                data = await self.process.stdout.readexactly(self.frame_bytes)
            except asyncio.CancelledError:
                break
            except (asyncio.IncompleteReadError, BrokenPipeError, ProcessLookupError):
                await self._stop_process()
                await asyncio.sleep(0.05)
                continue

            if self.queue.full():
                try:
                    self.queue.get_nowait()
                    self.dropped_frames += 1
                except asyncio.QueueEmpty:
                    pass
            self.queue.put_nowait(data)
            if self.queue.qsize() >= self.prebuffer_frames:
                self.ready.set()

    async def _ensure_capture(self) -> None:
        if self.reader_task is None or self.reader_task.done():
            self.reader_task = asyncio.create_task(self._capture_loop())

    async def recv(self) -> AudioFrame:
        await self._ensure_capture()
        loop = asyncio.get_running_loop()

        if self.next_send_time is None:
            # A small reserve smooths PulseAudio bursts, but never block the RTP
            # stream for long if the sink is currently silent or suspended.
            try:
                await asyncio.wait_for(self.ready.wait(), timeout=0.12)
            except asyncio.TimeoutError:
                pass
            self.next_send_time = loop.time()
        else:
            self.next_send_time += self.frame_seconds
            now = loop.time()
            # After a real scheduler pause, resume from "now" instead of trying
            # to catch up by dumping stale RTP packets in a burst.
            if now - self.next_send_time > self.frame_seconds * 2:
                self.next_send_time = now
            elif self.next_send_time > now:
                await asyncio.sleep(self.next_send_time - now)

        # Keep only a modest reserve. If the sender was paused, stale speech is
        # worse than dropping it because it makes Orca read old UI events later.
        keep = self.prebuffer_frames + 1
        while self.queue.qsize() > keep:
            try:
                self.queue.get_nowait()
                self.dropped_frames += 1
            except asyncio.QueueEmpty:
                break

        try:
            data = self.queue.get_nowait()
        except asyncio.QueueEmpty:
            data = self.silence
            self.silence_frames += 1

        frame = AudioFrame(format="s16", layout="mono", samples=self.samples)
        frame.planes[0].update(data)
        frame.sample_rate = self.sample_rate
        frame.pts = self.timestamp
        frame.time_base = Fraction(1, self.sample_rate)
        self.timestamp += self.samples
        return frame

    def stop(self) -> None:
        if self.reader_task and not self.reader_task.done():
            self.reader_task.cancel()
        if self.process and self.process.returncode is None:
            try:
                self.process.terminate()
            except ProcessLookupError:
                pass
        super().stop()
PY

chown egor:egor "$src"
/opt/audio-remote/.venv/bin/python -m py_compile "$src"

echo '===== PACED TRACK TIMING TEST ====='
export PULSE_SERVER='unix:/run/egor-desktop/xpra/100/pulse/native'
export PULSE_COOKIE='/home/egor/.config/pulse/$PULSE_COOKIE'
python3 - <<'PY' >/tmp/silence.raw
import sys
sys.stdout.buffer.write(b'\0\0' * 48000 * 8)
PY
runuser -u egor -- env PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" \
  pacat --playback --raw --device=Xpra-Speaker --format=s16le --rate=48000 --channels=1 </tmp/silence.raw >/dev/null 2>/tmp/pacat.err &
player=$!

runuser -u egor -- env PULSE_SERVER="$PULSE_SERVER" PULSE_COOKIE="$PULSE_COOKIE" \
  /opt/audio-remote/.venv/bin/python - <<'PY'
import asyncio, statistics, sys, time
sys.path.insert(0, '/opt/audio-remote')
from audio_remote.audio import PulseAudioTrack

async def main():
    t=PulseAudioTrack('Xpra-Speaker.monitor')
    intervals=[]
    prev=None
    try:
        for _ in range(250):
            await t.recv()
            now=time.perf_counter()
            if prev is not None: intervals.append((now-prev)*1000)
            prev=now
    finally:
        t.stop()
    s=sorted(intervals)
    q=lambda x:s[min(len(s)-1,int((len(s)-1)*x))]
    print('mean', round(statistics.mean(intervals),3))
    print('p50', round(q(.5),3), 'p95', round(q(.95),3), 'p99', round(q(.99),3), 'max', round(max(intervals),3))
    print('gt25', sum(x>25 for x in intervals), 'gt30', sum(x>30 for x in intervals), 'gt40', sum(x>40 for x in intervals), 'lt10', sum(x<10 for x in intervals))
    print('queue', t.queue.qsize(), 'drops', t.dropped_frames, 'silence_frames', t.silence_frames)
asyncio.run(main())
PY
wait "$player" || true
cat /tmp/pacat.err || true

echo '===== LIVE SERVICE UNCHANGED ====='
systemctl is-active audio-remote.service
systemctl show audio-remote.service -p MainPID -p ActiveEnterTimestamp --no-pager

echo PATCH_TESTED_NOT_RESTARTED=yes
