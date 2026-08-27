#!/usr/bin/env bash
set -euo pipefail

zpid=75350

if [ ! -r "/proc/$zpid/stat" ]; then
  echo ZOMBIE_ALREADY_GONE=yes
  exit 0
fi

state=$(awk '{print $3}' "/proc/$zpid/stat")
ppid=$(awk '{print $4}' "/proc/$zpid/stat")
echo "BEFORE pid=$zpid state=$state ppid=$ppid"
ps -p "$zpid,$ppid" -o pid=,ppid=,stat=,etimes=,comm=,args= || true

if [ "$state" != Z ]; then
  echo TARGET_NOT_ZOMBIE=yes
  exit 0
fi

# A zombie cannot be killed; ask its parent to reap exited children.
kill -s CHLD "$ppid" || true
sleep 1

if [ -e "/proc/$zpid" ]; then
  state2=$(awk '{print $3}' "/proc/$zpid/stat" 2>/dev/null || echo gone)
  echo "AFTER pid=$zpid state=$state2"
  ps -p "$zpid,$ppid" -o pid=,ppid=,stat=,etimes=,comm=,args= || true
  if [ "$state2" = Z ]; then
    echo ZOMBIE_STILL_PRESENT=yes
  fi
else
  echo ZOMBIE_REAPED=yes
fi
