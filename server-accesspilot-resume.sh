#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
echo "=== VPS ACCESSPILOT: REGRESSION AND RESUME ==="
echo "HOST=$(hostname)"
ROOT=/var/tmp/bulbam-accesspilot-server
REPORT="$ROOT/reports"
mkdir -p "$REPORT"
WORK="$(find "$ROOT" -maxdepth 1 -mindepth 1 -type d -name 'source.*' -print | sort | head -n 1)"
if [[ -z "$WORK" || ! -d "$WORK/.git" ]];then
  echo "No dedicated temporary source; creating fresh test checkout."
  WORK="$(mktemp -d "$ROOT/source.XXXXXXXX")"
  git clone --quiet --depth 1 --single-branch --branch feature/accesspilot-virtual-accessibility https://github.com/egor125552/Bulbam.git "$WORK"
fi
cd "$WORK"
git fetch --quiet --depth 1 origin feature/accesspilot-virtual-accessibility
git -c advice.detachedHead=false checkout --force --detach FETCH_HEAD
echo "SOURCE=$(git rev-parse --short HEAD)"
echo "RDC_PACKAGE_VERSION=$(node -p "require('/usr/local/lib/node_modules/@wonderwhy-er/desktop-commander/package.json').version")"
echo "RDC_SERVICE=$(systemctl is-active desktop-commander-remote.service || true)"
echo "LATEST RDC STATUS (NO CODES OR TOKENS):"
journalctl -u desktop-commander-remote.service --since "20 minutes ago" -o cat --no-pager |grep -Ei 'session invalid|device startup failed|waiting for authorization|device code has expired|connected to remote mcp|invalid refresh token|authenticat' |sed -E 's/(Invalid Refresh Token:).*/\1 [REDACTED]/;s/(session invalid:).*/\1 [REDACTED]/' |tail -n 15 || true
echo "RUN BROWSER REGRESSION"
ACCESSPILOT_BROWSER_TESTS=1 npx vitest run test/accesspilot-bulbam-wcag.test.js --reporter=dot
echo "RESUME SIGNED IN FROM CHECKPOINT"
set +e
timeout 600s env ACCESSPILOT_SCENARIOS=signed-in ACCESSPILOT_MAX_ACTIONS=95 ACCESSPILOT_MAX_STATES=180 ACCESSPILOT_FAKE_MEDIA=1 \
  nice -n 10 node tools/accesspilot/cli.js --config tools/accesspilot/accesspilot.project.json --output "$REPORT" --resume
RESULT=$?
set -e
echo "CRAWL_EXIT_CODE=$RESULT"
node tools/accesspilot/merge-reports.js --config tools/accesspilot/accesspilot.project.json --output "$REPORT"
node --input-type=module - "$REPORT/accesspilot-combined.json" <<'NODE'
import {readFileSync} from 'node:fs';
const r=JSON.parse(readFileSync(process.argv[2],'utf8'));
console.log('FINAL_SUMMARY',JSON.stringify(r.summary));
console.log('FINAL_COVERAGE',JSON.stringify({total:r.coverage?.total,attempted:r.coverage?.attempted,activated:r.coverage?.activated,neverVisible:r.coverage?.neverVisible?.length}));
for(const issue of r.findings.groups)console.log('FINAL_ISSUE',issue.code,issue.selector,issue.occurrences);
NODE
echo "=== END VPS ACCESSPILOT ==="
exit "$RESULT"
