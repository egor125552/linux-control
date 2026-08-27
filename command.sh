#!/usr/bin/env bash
set -euo pipefail

printf '===== CPU SNAPSHOT =====\n'
ps -eo pid,ppid,ni,pri,psr,stat,%cpu,%mem,comm,args --sort=-%cpu | head -35

printf '===== ORCA / SPEECH PROCESS DETAIL =====\n'
for p in $(pgrep -u egor -f 'orca|speech-dispatcher|speech-dispatch|sd_rhvoice|RHVoice' || true); do
  [ -d "/proc/$p" ] || continue
  ps -p "$p" -o pid=,ppid=,ni=,pri=,psr=,stat=,%cpu=,%mem=,etimes=,comm=,args=
  printf 'threads='; ls "/proc/$p/task" 2>/dev/null | wc -l
  printf 'voluntary/nonvoluntary='; awk '/voluntary_ctxt_switches|nonvoluntary_ctxt_switches/{printf "%s=%s ",$1,$2} END{print ""}' "/proc/$p/status" 2>/dev/null || true
done

printf '===== SYSTEM PRESSURE =====\n'
uptime
cat /proc/loadavg
for f in cpu io memory; do echo "-- $f"; cat "/proc/pressure/$f" 2>/dev/null || true; done

printf '===== SPEECHD CONFIG =====\n'
grep -Ev '^[[:space:]]*(#|;|$)' /home/egor/.config/speech-dispatcher/speechd.conf 2>/dev/null \
  | grep -Ei 'DefaultModule|DefaultLanguage|DefaultVoiceType|AudioOutputMethod|AudioPulseServer|Rate|Pitch|Volume|PauseContext|Timeout|MaxHistory|LogLevel' || true

printf '===== RHVOICE MODULE CONFIG =====\n'
for f in /home/egor/.config/speech-dispatcher/modules/rhvoice.conf /etc/speech-dispatcher/modules/rhvoice.conf; do
  [ -f "$f" ] || continue
  echo "FILE=$f"
  grep -Ev '^[[:space:]]*(#|;|$)' "$f" | head -220
done

printf '===== ORCA SPEECH SETTINGS =====\n'
# Only public/non-secret desktop preferences relevant to speech.
sudo -u egor env HOME=/home/egor DBUS_SESSION_BUS_ADDRESS="$(tr '\0' '\n' < /proc/$(pgrep -u egor -x mate-session | head -1)/environ | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -1)" \
  gsettings list-recursively org.gnome.orca 2>/dev/null | grep -Ei 'speech|rate|pitch|voice|verbosity|punctuation' | head -200 || true

printf '===== RHVOICE RECENT LOG =====\n'
tail -n 260 /run/egor-desktop/speech-dispatcher/log/rhvoice.log 2>/dev/null || true

printf '===== SPEECH DISPATCHER RECENT LOGS =====\n'
for f in /run/egor-desktop/speech-dispatcher/log/*.log; do
  [ -f "$f" ] || continue
  echo "--- $f"
  tail -n 120 "$f" | grep -Ei 'speak|stop|cancel|pause|resume|audio|error|warning|timeout|buffer|underrun|overrun' | tail -100 || true
done

printf '===== PROCESS SCHEDULER =====\n'
for p in $(pgrep -u egor -f 'orca|speech-dispatcher|speech-dispatch|sd_rhvoice' || true); do
  echo "PID=$p"
  chrt -p "$p" 2>/dev/null || true
  ionice -p "$p" 2>/dev/null || true
done

echo ORCA_CHOP_DIAG_DONE=yes
