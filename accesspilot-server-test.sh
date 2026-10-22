#!/usr/bin/env bash
# Run the universal AccessPilot on an isolated Bulbam fixture on this VPS.
# Never connects to the production Bulbam account/database.
set -Eeuo pipefail
umask 077
echo '=== ACCESSPILOT ON VPS ==='
hostname
node --version
ROOT=/var/tmp/bulbam-accesspilot-server
mkdir -p "$ROOT"
WORK=$(mktemp -d "$ROOT/source.XXXXXXXX")
REPORT="$ROOT/reports"
git clone --quiet --depth 1 --single-branch --branch feature/accesspilot-virtual-accessibility \
  https://github.com/egor125552/Bulbam.git "$WORK"
cd "$WORK"
echo 'SOURCE COMMIT:'
git rev-parse --short HEAD
echo 'INSTALLING TEST DEPENDENCIES'
npm ci --legacy-peer-deps --no-audit --no-fund
npx playwright install chromium
mkdir -p "$REPORT"
echo 'RUNNING UNIVERSAL TEST EXCLUSIVELY ON ISOLATED TEST DATA'
set +e
timeout 2100s env ACCESSPILOT_SCENARIOS=signed-out,signed-in \
  ACCESSPILOT_MAX_ACTIONS=650 ACCESSPILOT_MAX_STATES=240 \
  ACCESSPILOT_FAKE_MEDIA=1 \
  nice -n 10 npm run test:accessibility -- --output "$REPORT"
RESULT=$?
set -e
echo "ACCESSPILOT_EXIT_CODE=$RESULT"
echo 'RESULTS:'
if test -f "$REPORT/accesspilot-combined.json"; then
  node tools/accesspilot/merge-reports.js --config tools/accesspilot/accesspilot.project.json --output "$REPORT"
  node --input-type=module - "$REPORT/accesspilot-combined.json" <<'NODE'
import {readFileSync} from "node:fs";
const r=JSON.parse(readFileSync(process.argv[2],"utf8"));
console.log("Summary",JSON.stringify(r.summary));
console.log("Control coverage",JSON.stringify({
  total:r.coverage?.total,attempted:r.coverage?.attempted,
  activated:r.coverage?.activated,neverVisible:r.coverage?.neverVisible?.length
}));
console.log("Unique issues",r.findings.uniqueIssues,"Occurrences",r.findings.occurrences);
for(const issue of r.findings.groups)
  console.log("ISSUE",issue.code,issue.selector,issue.occurrences,issue.screens.join(" | "));
NODE
fi
echo "REPORT_DIRECTORY=$REPORT"
echo '=== END ACCESSPILOT VPS TEST ==='
exit "$RESULT"
