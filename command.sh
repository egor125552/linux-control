#!/usr/bin/env bash
set -euo pipefail

echo '===== SPEECH DISPATCHER LOG TAIL ====='
tail -n 100 /home/egor/.cache/speech-dispatcher/log/speech-dispatcher.log 2>/dev/null || true

echo '===== RHVOICE LOG TAIL ====='
tail -n 80 /home/egor/.cache/speech-dispatcher/log/rhvoice.log 2>/dev/null || true

echo '===== SPEECH CONFIG RELEVANT ====='
grep -nEi 'timeout|autospawn|communication|socket|loglevel|addmodule|defaultmodule' /home/egor/.config/speech-dispatcher/speechd.conf 2>/dev/null || true
