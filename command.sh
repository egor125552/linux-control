#!/usr/bin/env bash
set -euo pipefail
BASE=/srv/zero-line-audio/sonniss-2026
mkdir -p "$BASE/tests"
URL='https://downloads.sonniss.com/Sonniss.com-GDC2026-GameAudioBundle1of5.zip'
GDRIVE='https://drive.google.com/uc?export=download&id=1ndDWhCoq0NgkrJH6ku5MSA65zinEby9r'
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/141 Safari/537.36'
echo '=== CURL DIRECT DEFAULT ==='
curl -I -L --max-time 20 "$URL" || true
echo '=== CURL DIRECT BROWSER + REFERER ==='
curl -I -L --http1.1 -A "$UA" -e 'https://gdc.sonniss.com/' --max-time 20 "$URL" || true
echo '=== CURL RANGE 1MB BROWSER + REFERER ==='
rm -f "$BASE/tests/curl-range.bin"
curl -L --fail --http1.1 -A "$UA" -e 'https://gdc.sonniss.com/' -r 0-1048575 --max-time 60 -o "$BASE/tests/curl-range.bin" "$URL" || true
ls -lh "$BASE/tests/curl-range.bin" 2>/dev/null || true
file "$BASE/tests/curl-range.bin" 2>/dev/null || true
echo '=== WGET DIRECT BROWSER ==='
rm -f "$BASE/tests/wget-range.bin"
wget --server-response --timeout=30 --tries=1   --user-agent="$UA"   --referer='https://gdc.sonniss.com/'   --header='Range: bytes=0-1048575'   -O "$BASE/tests/wget-range.bin" "$URL" 2>&1 || true
ls -lh "$BASE/tests/wget-range.bin" 2>/dev/null || true
file "$BASE/tests/wget-range.bin" 2>/dev/null || true
echo '=== GOOGLE DRIVE CURL ==='
rm -f "$BASE/tests/gdrive.bin" "$BASE/tests/gcookie.txt"
curl -L --fail -A "$UA" -c "$BASE/tests/gcookie.txt" -b "$BASE/tests/gcookie.txt"   --max-time 60 -r 0-1048575 -o "$BASE/tests/gdrive.bin" "$GDRIVE" || true
ls -lh "$BASE/tests/gdrive.bin" 2>/dev/null || true
file "$BASE/tests/gdrive.bin" 2>/dev/null || true
echo '=== OFFICIAL TORRENT ==='
TOR='https://downloads.sonniss.com/GameAudioGDCPart9.torrent'
rm -f "$BASE/tests/sonniss.torrent"
curl -L --fail -A "$UA" -e 'https://gdc.sonniss.com/' --max-time 30 -o "$BASE/tests/sonniss.torrent" "$TOR" || true
ls -lh "$BASE/tests/sonniss.torrent" 2>/dev/null || true
file "$BASE/tests/sonniss.torrent" 2>/dev/null || true
if [ -s "$BASE/tests/sonniss.torrent" ]; then
  if ! command -v aria2c >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq aria2
  fi
  echo '=== TORRENT CONTENTS ==='
  aria2c --show-files "$BASE/tests/sonniss.torrent" || true
fi
