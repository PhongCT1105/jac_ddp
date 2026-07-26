#!/usr/bin/env bash
# End-to-end proof for connection-agent in mock mode (no coordinator needed).
#
# Serves the app, seeds the 100-profile pool, creates a fresh profile, then
# drives the full product flow over curl exactly as a browser would:
#   create_profile -> find_matches -> poll match_status until complete -> get_matches
# and asserts matches + a non-zero compute receipt come back.
#
# Usage: ./tests/e2e_mock.sh   (run from apps/connection-agent/, or anywhere —
# paths below are resolved relative to this script).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$APP_DIR/../.." && pwd)"
JAC_BIN="$REPO_ROOT/.venv/bin/jac"
PORT="${E2E_PORT:-8097}"
BASE="http://127.0.0.1:$PORT"

if [ ! -x "$JAC_BIN" ]; then
  echo "error: $JAC_BIN not found — is the venv set up? (see jac-baseline.md)" >&2
  exit 1
fi

pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; exit 1; }

SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "== connection-agent e2e (mock mode) =="
echo "app dir: $APP_DIR"
echo "port:    $PORT"

rm -rf "$APP_DIR/.jac/data"

echo "-- starting server (JACGRID_MODE=mock) --"
(
  cd "$APP_DIR"
  JACGRID_MODE=mock "$JAC_BIN" start main.sv.jac --no_client --port "$PORT"
) > /tmp/connection-agent-e2e.log 2>&1 &
SERVER_PID=$!

echo "-- waiting for /healthz --"
for i in $(seq 1 30); do
  if curl -s -o /dev/null "$BASE/healthz"; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "server never came up — log:" >&2
    cat /tmp/connection-agent-e2e.log >&2
    exit 1
  fi
  sleep 1
done
pass "server is healthy"

call() {
  # call <walker> <json-body>
  curl -s -X POST "$BASE/walker/$1" -H "Content-Type: application/json" -d "$2"
}

report_of() {
  # extracts data.reports[0] from a 0.16 response envelope
  python3 -c '
import json, sys
d = json.load(sys.stdin)
reports = (d.get("data") or {}).get("reports") or d.get("reports") or []
print(json.dumps(reports[0] if reports else {}))
'
}

echo "-- seed_profiles --"
SEED_REP=$(call seed_profiles '{}' | report_of)
echo "  $SEED_REP"
SEEDED=$(echo "$SEED_REP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("seeded", 0))')
ALREADY=$(echo "$SEED_REP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("already_seeded", 0))')
if [ "$SEEDED" -gt 0 ] || [ "$ALREADY" -gt 0 ]; then
  pass "profile pool is seeded ($SEEDED seeded / $ALREADY already present)"
else
  fail "seed_profiles reported nothing seeded and nothing already present"
fi

echo "-- create_profile --"
CREATE_REP=$(call create_profile '{"name":"E2E Tester","bio":"Python backend engineer building distributed systems and developer tools.","tags":{"skills":["python","distributed-systems"],"interests":["devtools"],"looking_for":["ml"]}}' | report_of)
echo "  $CREATE_REP"
PROFILE_ID=$(echo "$CREATE_REP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
[ -n "$PROFILE_ID" ] || fail "create_profile did not return an id"
pass "created profile $PROFILE_ID"

echo "-- find_matches --"
FIND_REP=$(call find_matches "{\"profile_id\":\"$PROFILE_ID\"}" | report_of)
echo "  $FIND_REP"
JOB_ID=$(echo "$FIND_REP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["job_id"])')
[ -n "$JOB_ID" ] || fail "find_matches did not return a job_id"
pass "submitted embedding job $JOB_ID"

echo "-- match_status (poll until complete) --"
STATUS="queued"
for i in $(seq 1 8); do
  STATUS_REP=$(call match_status "{\"profile_id\":\"$PROFILE_ID\"}" | report_of)
  STATUS=$(echo "$STATUS_REP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status","?"))')
  echo "  poll #$i -> status=$STATUS"
  if [ "$STATUS" = "complete" ]; then
    break
  fi
  sleep 0.3
done
[ "$STATUS" = "complete" ] || fail "job never reached complete (last status: $STATUS)"
pass "job completed after polling"

echo "-- get_matches --"
MATCHES_REP=$(call get_matches "{\"profile_id\":\"$PROFILE_ID\",\"top_n\":3}" | report_of)
echo "$MATCHES_REP" | python3 -m json.tool

MATCH_COUNT=$(echo "$MATCHES_REP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("matches",[])))')
TOTAL_PAID=$(echo "$MATCHES_REP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("receipt",{}).get("total_paid",0))')

[ "$MATCH_COUNT" -gt 0 ] || fail "get_matches returned zero matches"
pass "got $MATCH_COUNT matches"

python3 -c "import sys; sys.exit(0 if float('$TOTAL_PAID') > 0 else 1)" || fail "receipt total_paid was not > 0"
pass "compute receipt total_paid = $TOTAL_PAID TESTUSD"

echo
echo "== ALL CHECKS PASSED =="
