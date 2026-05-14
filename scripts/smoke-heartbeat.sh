#!/usr/bin/env bash
# Plan A verification — re-run the smoke heartbeat after long-path fix.
#
# Creates a fresh smoke issue assigned to Delivery Lead, invokes heartbeat,
# polls until the run finishes or 6 minutes elapse, then prints the verdict.

set -euo pipefail

BASE="http://localhost:3100/api"
COMPANY_ID="bd235017-16ce-4e6f-9c95-2e9b2971829b"
DELIVERY_LEAD_ID="af45bbe9-b5ab-4135-8fb2-8624e05e32a9"
PROJECT_ID="85379338-88ec-4b80-aa11-ca438c78f6ba"

echo "==> 0. confirm health"
curl -sf "$BASE/health" >/dev/null || { echo "paperclip not responding on 3100"; exit 1; }

echo "==> 1. create smoke issue"
ISSUE_ID=$(
  python <<'PY'
import json, urllib.request, urllib.error, os
body = json.dumps({
    "title": "[smoke-2] heartbeat re-verify after long-path fix",
    "description": "Call plugin tool github_list_issues (state=open, perPage=3) on djcowork/djcowork2.0. Summarise the 3 results in one sentence. DO NOT modify any code, DO NOT open a PR.",
    "projectId": os.environ.get("PROJECT_ID"),
    "assigneeAgentId": os.environ.get("DELIVERY_LEAD_ID"),
    "priority": "low"
}).encode()
req = urllib.request.Request(
    f"{os.environ.get('BASE')}/companies/{os.environ.get('COMPANY_ID')}/issues",
    data=body, method="POST", headers={"Content-Type":"application/json"}
)
with urllib.request.urlopen(req) as r:
    d = json.loads(r.read())
    print(d.get("id"))
PY
)
echo "    issue: $ISSUE_ID"

echo "==> 2. invoke heartbeat"
RUN_ID=$(
  python <<'PY'
import json, urllib.request, os
body = json.dumps({"reason": "smoke-2 after long-path fix"}).encode()
req = urllib.request.Request(
    f"{os.environ.get('BASE')}/agents/{os.environ.get('DELIVERY_LEAD_ID')}/heartbeat/invoke",
    data=body, method="POST", headers={"Content-Type":"application/json"}
)
with urllib.request.urlopen(req) as r:
    d = json.loads(r.read())
    print(d.get("id"))
PY
)
echo "    run: $RUN_ID"

echo "==> 3. poll until finished (timeout 6 min)"
START=$(date +%s)
DEADLINE=$((START + 360))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  sleep 8
  RESP=$(curl -s "$BASE/heartbeat-runs/$RUN_ID")
  STATUS=$(echo "$RESP" | python -c "import sys,json; print(json.load(sys.stdin).get('status'))")
  ERR=$(echo "$RESP" | python -c "import sys,json; print(json.load(sys.stdin).get('errorCode') or '')")
  ELAPSED=$(( $(date +%s) - START ))
  echo "    [${ELAPSED}s] status=$STATUS errorCode=$ERR"
  case "$STATUS" in
    completed|succeeded|failed|cancelled|timed_out|aborted)
      break
      ;;
  esac
done

echo "==> 4. final detail"
curl -s "$BASE/heartbeat-runs/$RUN_ID" | python <<'PY'
import sys, json
d = json.load(sys.stdin)
for k in ["status","errorCode","exitCode","signal","finishedAt","stderrExcerpt","stdoutExcerpt","processPid"]:
    v = d.get(k)
    if v: print(f"  {k}: {str(v)[:300]}")
PY
echo
echo "run id: $RUN_ID"
echo "issue id: $ISSUE_ID"
