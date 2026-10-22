#!/usr/bin/env bash
set -Eeuo pipefail
echo '=== VPS BROWSER REGRESSION: MICROPHONE AND VOICE DRAFT FOCUS ==='
ROOT=/var/tmp/bulbam-accesspilot-server
WORK="$(find "$ROOT" -maxdepth 1 -mindepth 1 -type d -name 'source.*' -print | sort | head -n 1)"
if [[ -z "$WORK" || ! -d "$WORK/.git" ]];then
  echo 'No dedicated AccessPilot source checkout';exit 3
fi
cd "$WORK"
git fetch -q --depth 1 origin feature/accesspilot-virtual-accessibility
git -c advice.detachedHead=false checkout --force --detach FETCH_HEAD
echo "SOURCE_SHA=$(git rev-parse --short HEAD)"
echo "RDC_VERSION=$(node -p "require('/usr/local/lib/node_modules/@wonderwhy-er/desktop-commander/package.json').version")"
echo "RDC_SERVICE=$(systemctl is-active desktop-commander-remote.service || true)"
ACCESSPILOT_BROWSER_TESTS=1 npx vitest run test/accesspilot-bulbam-wcag.test.js test/accesspilot-voice-draft-focus.test.js --maxWorkers=1 --reporter=verbose
echo '=== VPS BROWSER REGRESSIONS COMPLETE ==='
