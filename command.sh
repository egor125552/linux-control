#!/usr/bin/env bash
set -euo pipefail
stamp=$(date +%Y%m%d-%H%M%S)
root=/opt/audio-remote/audio_remote
backup=/root/audio-remote-before-stability-fix-$stamp
mkdir -p "$backup/static"
cp -a "$root/audio.py" "$backup/audio.py"
cp -a "$root/server.py" "$backup/server.py"
cp -a "$root/static/app.js" "$backup/static/app.js"

echo "BACKUP_CREATED=$backup"

cat >"$root/audio.py" <<'PY'
import asyncio
from fractions import Fraction

from aiortc import MediaStreamTrack
from av import AudioFrame


class PulseAudioTrack(MediaStreamTrack):
    kind = "audio"

    def __init__(self, source: str, sample_rate: int = 48_000, frame_ms: int = 20) -> None:
        super().__init__()
        self.source = source
        self.sample_rate = sample_rate
        self.samples = sample_rate * frame_ms // 1000
        self.timestamp = 0
        self.process: asyncio.subprocess.Process | None = None

    async def _start(self) -> None:
        # Keep 20 ms WebRTC frames, but give PulseAudio a modest capture buffer.
        # This absorbs short scheduler hiccups without adding a large delay.
        self.process = await asyncio.create_subprocess_exec(
            "parec",
            f"--device={self.source}",
            "--format=s16le",
            f"--rate={self.sample_rate}",
            "--channels=1",
            "--latency-msec=80",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )

    async def recv(self) -> AudioFrame:
        if self.process is None or self.process.returncode is not None:
            self.process = None
            await self._start()
        assert self.process and self.process.stdout
        try:
            data = await self.process.stdout.readexactly(self.samples * 2)
        except (asyncio.IncompleteReadError, BrokenPipeError):
            # PulseAudio/Xpra can replace its stream during a transient recovery.
            # Restart capture once instead of killing the whole WebRTC sender.
            if self.process and self.process.returncode is None:
                self.process.terminate()
                try:
                    await asyncio.wait_for(self.process.wait(), timeout=0.5)
                except (asyncio.TimeoutError, ProcessLookupError):
                    try:
                        self.process.kill()
                    except ProcessLookupError:
                        pass
            self.process = None
            await self._start()
            assert self.process and self.process.stdout
            data = await self.process.stdout.readexactly(self.samples * 2)

        frame = AudioFrame(format="s16", layout="mono", samples=self.samples)
        frame.planes[0].update(data)
        frame.sample_rate = self.sample_rate
        frame.pts = self.timestamp
        frame.time_base = Fraction(1, self.sample_rate)
        self.timestamp += self.samples
        return frame

    def stop(self) -> None:
        if self.process and self.process.returncode is None:
            self.process.terminate()
        super().stop()
PY

python3 - <<'PY'
p='/opt/audio-remote/audio_remote/server.py'
s=open(p,encoding='utf-8').read()
s=s.replace('tracks: dict[RTCPeerConnection, PulseAudioTrack] = {}\n', 'tracks: dict[RTCPeerConnection, PulseAudioTrack] = {}\ndisconnect_tasks: dict[RTCPeerConnection, asyncio.Task] = {}\n')
old='''    @pc.on("connectionstatechange")\n    async def state_changed() -> None:\n        if pc.connectionState in {"failed", "closed", "disconnected"}:\n            await pc.close()\n            pcs.discard(pc)\n            old_track = tracks.pop(pc, None)\n            if old_track:\n                old_track.stop()\n'''
new='''    async def cleanup_peer() -> None:\n        task = disconnect_tasks.pop(pc, None)\n        if task and task is not asyncio.current_task():\n            task.cancel()\n        if pc.connectionState != "closed":\n            await pc.close()\n        pcs.discard(pc)\n        old_track = tracks.pop(pc, None)\n        if old_track:\n            old_track.stop()\n\n    async def cleanup_after_disconnect() -> None:\n        # ICE can report disconnected briefly during Wi-Fi/VPN/mobile route changes.\n        # Keep sending for a grace period instead of turning a tiny network hiccup\n        # into a hard audio cut and a brand-new peer connection.\n        try:\n            await asyncio.sleep(8)\n            if pc.connectionState == "disconnected":\n                await cleanup_peer()\n        except asyncio.CancelledError:\n            pass\n\n    @pc.on("connectionstatechange")\n    async def state_changed() -> None:\n        state = pc.connectionState\n        if state == "connected":\n            task = disconnect_tasks.pop(pc, None)\n            if task:\n                task.cancel()\n        elif state == "disconnected":\n            old = disconnect_tasks.pop(pc, None)\n            if old:\n                old.cancel()\n            disconnect_tasks[pc] = asyncio.create_task(cleanup_after_disconnect())\n        elif state in {"failed", "closed"}:\n            await cleanup_peer()\n'''
if old not in s:
    raise SystemExit('SERVER_STATE_BLOCK_NOT_FOUND')
s=s.replace(old,new,1)
old_shutdown='''async def shutdown(_: web.Application) -> None:\n    await asyncio.gather(*(pc.close() for pc in pcs), return_exceptions=True)\n    for track in tracks.values():\n        track.stop()\n    pcs.clear()\n    tracks.clear()\n'''
new_shutdown='''async def shutdown(_: web.Application) -> None:\n    for task in disconnect_tasks.values():\n        task.cancel()\n    disconnect_tasks.clear()\n    await asyncio.gather(*(pc.close() for pc in pcs), return_exceptions=True)\n    for track in tracks.values():\n        track.stop()\n    pcs.clear()\n    tracks.clear()\n'''
if old_shutdown not in s:
    raise SystemExit('SERVER_SHUTDOWN_BLOCK_NOT_FOUND')
s=s.replace(old_shutdown,new_shutdown,1)
open(p,'w',encoding='utf-8').write(s)
PY

cat >"$root/static/app.js" <<'JS'
const remote = document.querySelector("#remote");
const status = document.querySelector("#status");
const connectButton = document.querySelector("#connect");
const audio = document.querySelector("#audio");

let peer = null;
let socket = null;
let connecting = false;
let reconnectTimer = null;
let reconnectAttempt = 0;
let generation = 0;

function endpoint(name) {
  return new URL(name, window.location.href).toString();
}

function setStatus(message, connected = false) {
  status.textContent = message;
  remote.dataset.connected = String(connected);
}

function waitForIceGathering(pc) {
  if (pc.iceGatheringState === "complete") return Promise.resolve();
  return new Promise((resolve) => {
    const changed = () => {
      if (pc.iceGatheringState === "complete") {
        pc.removeEventListener("icegatheringstatechange", changed);
        resolve();
      }
    };
    pc.addEventListener("icegatheringstatechange", changed);
  });
}

function cancelReconnect() {
  if (reconnectTimer !== null) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
}

function scheduleReconnect(delay = null) {
  if (reconnectTimer !== null || connecting) return;
  const wait = delay ?? Math.min(8000, 500 * (2 ** Math.min(reconnectAttempt, 4)));
  reconnectAttempt += 1;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect(true);
  }, wait);
}

async function closePeer(pc) {
  if (!pc) return;
  try { pc.getReceivers().forEach((r) => r.track?.stop()); } catch {}
  try { pc.close(); } catch {}
}

async function connect(isRecovery = false) {
  if (connecting) return;
  if (peer && peer.connectionState === "connected") return;
  connecting = true;
  cancelReconnect();
  const myGeneration = ++generation;
  setStatus(isRecovery ? "Восстанавливаю звук…" : "Подключение звука и клавиатуры…");

  const oldPeer = peer;
  const oldSocket = socket;
  const pc = new RTCPeerConnection();
  let ws = null;

  try {
    ws = new WebSocket(endpoint("keys").replace("https:", "wss:"));
    pc.addTransceiver("audio", { direction: "recvonly" });

    pc.addEventListener("track", async (event) => {
      if (myGeneration !== generation) return;
      const stream = new MediaStream([event.track]);
      audio.srcObject = stream;
      try { await audio.play(); } catch {}
    });

    pc.addEventListener("connectionstatechange", () => {
      if (myGeneration !== generation) return;
      const state = pc.connectionState;
      if (state === "connected") {
        peer = pc;
        socket = ws;
        reconnectAttempt = 0;
        cancelReconnect();
        setStatus("Подключено. Все клавиши управляют Linux.", true);
        remote.focus();
        if (oldPeer && oldPeer !== pc) closePeer(oldPeer);
        if (oldSocket && oldSocket !== ws) {
          try { oldSocket.close(); } catch {}
        }
      } else if (state === "disconnected") {
        // Do not destroy a usable stream on a transient ICE hiccup.
        setStatus("Связь нестабильна, восстанавливаю…", true);
        scheduleReconnect(4000);
      } else if (state === "failed" || state === "closed") {
        setStatus("Связь восстанавливается…");
        scheduleReconnect(300);
      }
    });

    await pc.setLocalDescription(await pc.createOffer());
    await waitForIceGathering(pc);
    const response = await fetch(endpoint("offer"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(pc.localDescription),
    });
    if (!response.ok) throw new Error("offer rejected");
    await pc.setRemoteDescription(await response.json());
    peer = pc;
    socket = ws;
  } catch {
    if (myGeneration === generation) {
      setStatus("Связь восстанавливается…");
      scheduleReconnect();
    }
    await closePeer(pc);
    try { ws?.close(); } catch {}
  } finally {
    connecting = false;
  }
}

function forwardKey(event) {
  if (!socket || socket.readyState !== WebSocket.OPEN) return;
  socket.send(JSON.stringify({
    type: event.type,
    code: event.code,
    shiftKey: event.shiftKey,
    ctrlKey: event.ctrlKey,
    altKey: event.altKey,
    metaKey: event.metaKey,
  }));
}

connectButton.addEventListener("click", () => connect(false));
remote.addEventListener("keydown", async (event) => {
  if (!peer || peer.connectionState !== "connected") {
    event.preventDefault();
    await connect(false);
    return;
  }
  event.preventDefault();
  forwardKey(event);
});
remote.addEventListener("keyup", (event) => {
  if (peer?.connectionState !== "connected") return;
  event.preventDefault();
  forwardKey(event);
});

// Losing browser focus must not tear down the keyboard WebSocket or audio.
// Safari/VoiceOver causes frequent focus transitions which are not network loss.
window.addEventListener("pageshow", () => {
  if (!peer || ["failed", "closed"].includes(peer.connectionState)) scheduleReconnect(100);
});
document.addEventListener("visibilitychange", () => {
  if (!document.hidden && (!peer || ["failed", "closed"].includes(peer.connectionState))) {
    scheduleReconnect(100);
  }
});

remote.focus();
JS

python3 -m py_compile "$root/audio.py" "$root/server.py"
# Cheap JS structural checks without requiring node.
grep -q 'scheduleReconnect' "$root/static/app.js"
grep -q 'state === "disconnected"' "$root/static/app.js"
! grep -q 'window.addEventListener("blur", () => socket?.close())' "$root/static/app.js"

echo '===== PATCH SUMMARY ====='
grep -nE 'latency-msec|IncompleteReadError|cleanup_after_disconnect|asyncio.sleep\(8\)|state == "disconnected"' "$root/audio.py" "$root/server.py" | head -80
grep -nE 'scheduleReconnect|disconnected|visibilitychange|pageshow|blur' "$root/static/app.js" | head -120

systemctl restart audio-remote.service
sleep 2
systemctl is-active audio-remote.service
systemctl status audio-remote.service --no-pager -n 35 | grep -Ev '(token|password|secret|authorization|private)' || true
journalctl -u audio-remote.service --since '2 minutes ago' --no-pager | grep -Ei 'traceback|error|exception|failed' | tail -80 || true

echo AUDIO_REMOTE_STABILITY_FIX_APPLIED=yes
