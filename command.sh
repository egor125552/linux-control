#!/usr/bin/env bash
set -u
BASE=/opt/orca-51/lib/python3/dist-packages/orca
cd "$BASE" || exit 1

show_symbols() {
  f="$1"
  echo "===== $f : symbols ====="
  grep -nE '^class |^[[:space:]]+def |^def ' "$f" 2>/dev/null | head -220 || true
}

for f in event_manager.py script_manager.py script.py speech.py speech_manager.py speech_generator.py generator.py ax_object.py ax_utilities_event.py focus_manager.py; do
  [ -f "$f" ] && show_symbols "$f"
done

echo '===== EVENT MANAGER IMPORTANT BLOCKS ====='
grep -nE 'enqueue|_dequeue|_process|processEvent|registerListener|deregisterListener|event_queue|Queue|idle_add|timeout_add' event_manager.py 2>/dev/null | head -180 || true
sed -n '1,420p' event_manager.py 2>/dev/null || true

echo '===== SCRIPT MANAGER IMPORTANT BLOCKS ====='
grep -nE 'getScript|setActiveScript|activeScript|appScript|script' script_manager.py 2>/dev/null | head -180 || true
sed -n '1,360p' script_manager.py 2>/dev/null || true

echo '===== SPEECH FRONT DOOR ====='
sed -n '1,360p' speech.py 2>/dev/null || true

echo '===== SPEECH MANAGER HOT METHODS ====='
grep -nE 'def .*speak|def .*interrupt|def .*update|def .*voice|def .*server|speechd|SpeechServer|speak\(' speech_manager.py 2>/dev/null | head -220 || true

echo '===== SPEECH GENERATOR HOT METHODS ====='
grep -nE '^    def generate|^    def _generate|generateSpeech|cache|cached|memo|format' speech_generator.py 2>/dev/null | head -260 || true

echo '===== LIVE PROCESS MAPS / FD / THREADS ====='
pid=$(pgrep -n -x orca || pgrep -n -f '/orca($| )' || true)
echo "pid=$pid"
if [ -n "$pid" ]; then
  ps -p "$pid" -o pid,ppid,user,%cpu,%mem,rss,vsz,nlwp,etime,cmd
  printf 'fds='; ls "/proc/$pid/fd" 2>/dev/null | wc -l
  printf 'threads='; ls "/proc/$pid/task" 2>/dev/null | wc -l
  grep -E 'VmRSS|VmSize|RssAnon|RssFile|RssShmem|VmData|VmStk|VmExe|VmLib|Threads' "/proc/$pid/status" || true
fi

echo '===== BYTECODE / SYNTAX ====='
python3 -m compileall -q "$BASE" && echo 'compileall: OK' || echo 'compileall: FAILED'
