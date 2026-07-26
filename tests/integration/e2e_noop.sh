#!/usr/bin/env bash
# JacGrid e2e — the noop job lifecycle over real HTTP (milestone M1).
#
#   jac start platform/coordinator  +  one platform/worker  +  curl/jq
#   submit a 4-item noop job (chunk_size 1 -> 4 tasks), poll to completion,
#   assert every task is VERIFIED and PAID, and that the ledger balances.
#
# Run:  bash tests/integration/e2e_noop.sh
# Exit 0 on success; non-zero with a FAIL message otherwise.

TEST_NAME="noop"
PORT="${JACGRID_PORT:-8891}"
BASE="http://127.0.0.1:${PORT}"

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

COORD_LOG="$LOGDIR/${TEST_NAME}_coordinator.log"
WORKER_LOG="$LOGDIR/${TEST_NAME}_worker.log"

trap cleanup EXIT INT TERM
require_tools

echo "== e2e noop: job lifecycle over HTTP (port $PORT) =="

echo "[1/7] clean graph + start coordinator"
start_coordinator
echo "      coordinator ready on $BASE (pid $COORD_PID)"

echo "[2/7] submit noop job: 4 items, chunk_size 1, 0.1 TESTUSD/task, budget 1.0"
job_reply=$(post create_job '{
    "app_id": "e2e-noop",
    "job_type": "noop",
    "payload": {"items": [
        {"id": "i1", "text": "alpha"},
        {"id": "i2", "text": "beta"},
        {"id": "i3", "text": "gamma"},
        {"id": "i4", "text": "delta"}
    ]},
    "partitioning": {"strategy": "chunk", "chunk_size": 1},
    "verification": {"method": "recompute_sample", "sample_rate": 1.0},
    "budget": {"max_total": 1.0, "price_per_task": 0.1, "currency": "TESTUSD"}
}')
JOB_ID=$(echo "$job_reply" | jq -r '.job_id // empty')
[ -n "$JOB_ID" ] || fail "create_job returned no job_id: $job_reply"
[ "$(echo "$job_reply" | jq -r '.task_count')" = "4" ] || fail "expected task_count 4: $job_reply"
[ "$(echo "$job_reply" | jq -r '.status')" = "queued" ] || fail "expected status queued: $job_reply"
echo "      job_id=$JOB_ID task_count=4 status=queued"

echo "[3/7] start one worker"
wpid=$(start_worker "noop-worker" "noop-host" "$WORKER_LOG")
echo "      worker pid $wpid"

echo "[4/7] poll get_job until complete"
status=""
for _ in $(seq 1 90); do
    snapshot=$(post get_job "{\"job_id\": \"$JOB_ID\"}")
    status=$(echo "$snapshot" | jq -r '.status // empty')
    [ "$status" = "complete" ] && break
    [ "$status" = "failed" ] && fail "job failed: $snapshot"
    sleep 1
done
[ "$status" = "complete" ] || fail "job did not complete within 90s (last status: ${status:-none})"
echo "$snapshot" | jq -e '.progress == 1.0' >/dev/null || fail "progress != 1.0: $snapshot"
[ "$(echo "$snapshot" | jq '[.tasks[] | select(.status == "complete" and .paid == true)] | length')" = "4" ] \
    || fail "expected 4 complete+paid tasks in get_job: $snapshot"
echo "      job complete, progress 1.0, 4/4 tasks complete and paid"

echo "[5/7] get_job_result: merged items + payment receipt"
result=$(post get_job_result "{\"job_id\": \"$JOB_ID\"}")
echo "$result" | jq -e '.results' >/dev/null || fail "get_job_result missing results: $result"
ids=$(echo "$result" | jq -r '[.results[].id] | sort | join(",")')
[ "$ids" = "i1,i2,i3,i4" ] || fail "expected merged ids i1..i4, got: $ids"
[ "$(echo "$result" | jq -r '.receipt.tasks')" = "4" ] || fail "receipt.tasks != 4: $result"
[ "$(echo "$result" | jq -r '.receipt.verified')" = "4" ] || fail "receipt.verified != 4: $result"
echo "$result" | jq -e '.receipt.total_paid == 0.4' >/dev/null || fail "receipt.total_paid != 0.4: $result"
[ "$(echo "$result" | jq '.receipt.payments | length')" = "4" ] || fail "expected 4 payments: $result"
echo "$result" | jq -e '[.receipt.payments[] | select((.tx | startswith("0x")) and .amount == 0.1)] | length == 4' \
    >/dev/null || fail "payments missing tx ids or wrong amount: $result"
echo "      4/4 items merged, 4/4 tasks VERIFIED, total_paid=0.4 TESTUSD, 4 tx receipts"

echo "[6/7] audit_job: full execution tree"
audit=$(post audit_job "{\"job_id\": \"$JOB_ID\"}")
[ "$(echo "$audit" | jq -r '.status')" = "complete" ] || fail "audit: job not complete: $audit"
[ "$(echo "$audit" | jq '.tasks | length')" = "4" ] || fail "audit: expected 4 tasks: $audit"
[ "$(echo "$audit" | jq '[.tasks[] | select(.status != "complete" or .payment == null)] | length')" = "0" ] \
    || fail "audit: found incomplete or unpaid tasks: $audit"
[ "$(echo "$audit" | jq '[.tasks[].attempts[] | select(.verification.outcome != "passed")] | length')" = "0" ] \
    || fail "audit: found non-passed verifications: $audit"
[ "$(echo "$audit" | jq '[.tasks[].attempts[] | select(.result.execution.runtime == null)] | length')" = "0" ] \
    || fail "audit: an attempt is missing the mandatory Contract B execution block: $audit"
[ "$(echo "$audit" | jq '[.tasks[].attempts[] | select(.sandbox == null)] | length')" = "0" ] \
    || fail "audit: an attempt has no Sandbox node: $audit"
echo "      4 tasks -> 4 attempts, all verified, all paid, execution metadata recorded"

echo "[7/7] network_status: ledger balances"
net=$(post network_status '{}')
echo "$net" | jq -e '.workers[] | select(.name == "noop-worker") | .wallet.balance == 0.4' >/dev/null \
    || fail "expected noop-worker wallet 0.4: $(echo "$net" | jq -c '.workers')"
echo "$net" | jq -e '.wallets[] | select(.owner == "coordinator") | .balance == 9999.6' >/dev/null \
    || fail "expected coordinator wallet 9999.6: $(echo "$net" | jq -c '.wallets')"
echo "$net" | jq -e '.workers[] | select(.name == "noop-worker") | .reputation.success == 4' >/dev/null \
    || fail "expected worker reputation success == 4: $(echo "$net" | jq -c '.workers')"
echo "$net" | jq -e --arg j "$JOB_ID" '.jobs[] | select(.job_id == $j) | .status == "complete"' >/dev/null \
    || fail "network_status does not list the job as complete: $net"
echo "      worker earned 0.4, coordinator paid 0.4, reputation 4/0, job listed complete"

echo
echo "PASS: noop job verified end-to-end — submitted, split, dispatched, executed, VERIFIED and PAID"
exit 0
