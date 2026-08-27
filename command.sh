#!/usr/bin/env bash
set -euo pipefail

echo '===== ORCA PROCESSES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep '[o]rca' || true

echo '===== ORCA ZOMBIES AND PARENTS ====='
found=0
while read -r pid ppid stat comm args; do
  [ -n "${pid:-}" ] || continue
  case "$stat" in
    Z*)
      found=1
      echo "ZOMBIE pid=$pid ppid=$ppid comm=$comm args=$args"
      if [ -d "/proc/$ppid" ]; then
        ps -p "$ppid" -o pid=,ppid=,stat=,etimes=,comm=,args= || true
      else
        echo "PARENT_MISSING pid=$ppid"
      fi
      ;;
  esac
done < <(ps -u egor -o pid=,ppid=,stat=,comm=,args= | grep '[o]rca' || true)

if [ "$found" -eq 0 ]; then
  echo NO_ORCA_ZOMBIES=yes
fi

echo '===== AUDIO SERVICES ====='
ps -u egor -o pid=,ppid=,stat=,etimes=,comm=,args= | grep -E '[p]ipewire|[w]ireplumber|[p]ulseaudio|[s]peech-dispatcher' || true
