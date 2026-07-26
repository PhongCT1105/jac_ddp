#!/usr/bin/env bash
# JacGrid M1 — single-machine job lifecycle over real HTTP.
#
#   jac start platform/coordinator  +  one platform/worker  +  curl/jq
#   submit a 4-item noop job (chunk_size 2 -> 2 tasks), poll to completion,
#   fetch the merged result, and assert every task is VERIFIED and PAID
#   (audit_job + network_status included).
#
# Run:  bash tests/e2e_m1.sh          (from anywhere; repeatable)
# Exit 0 on success; non-zero with a FAIL message otherwise.

TEST_NAME="m1"
PORT="${JACGRID_PORT:-8891}"
BASE="http://127.0.0.1:${PORT}"

# shellcheck source=integration/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/integration/lib.sh"

COORD_LOG="$LOGDIR/${TEST_NAME}_coordinator.log"
WORKER_LOG="$LOGDIR/${TEST_NAME}_worker.log"

trap cleanup EXIT INT TERM
require_tools

echo "== M1: job lifecycle over HTTP (port $PORT) =="

echo "[1/7] clean graph + start coordinator"
start_coordinator
echo "      coordinator ready on $BASE (pid $COORD_PID)"

echo "[2/7] submit noop job: 4 items, chunk_size 2, 0.1 TESTUSD/task, budget 1.0"
job_reply=$(post create_job '{
    "app_id": "e2e-m1",
    "job_type": "noop",
    "payload": {"items": [
        {"id": "i1", "text": "alpha"},
        {"id": "i2", "text": "beta"},
        {"id": "i3", "text": "gamma"},
        {"id": "i4", "text": "delta"}
    ]},
    "partitioning": {"strategy": "chunk", "chunk_size": 2},
    "verification": {"method": "recompute_sample", "sample_rate": 1.0},
    "budget": {"max_total": 1.0, "price_per_task": 0.1, "currency": "TESTUSD"}
}')
JOB_ID=$(echo "$job_reply" | jq -r '.job_id // empty')
[ -n "$JOB_ID" ] || fail "create_job returned no job_id: $job_reply"
[ "$(echo "$job_reply" | jq -r '.task_count')" = "2" ] || fail "expected task_count 2: $job_reply"
[ "$(echo "$job_reply" | jq -r '.status')" = "queued" ] || fail "expected status queued: $job_reply"
echo "      job_id=$JOB_ID task_count=2 status=queued"

echo "[3/7] start one worker"
wpid=$(start_worker "m1-worker" "m1-host" "$WORKER_LOG")
WORKER_PIDS+=("$wpid")   # start_worker runs in a $() subshell; re-register for cleanup
echo "      worker pid $wpid"

echo "[4/7] poll get_job until complete"
status=""
snapshot=""
for _ in $(seq 1 90); do
    snapshot=$(post get_job "{\"job_id\": \"$JOB_ID\"}")
    status=$(echo "$snapshot" | jq -r '.status // empty')
    [ "$status" = "complete" ] && break
    [ "$status" = "failed" ] && fail "job failed: $snapshot"
    sleep 1
done
[ "$status" = "complete" ] || fail "job did not complete within 90s (last status: ${status:-none})"
echo "$snapshot" | jq -e '.progress == 1.0' >/dev/null || fail "progress != 1.0: $snapshot"
[ "$(echo "$snapshot" | jq '[.tasks[] | select(.status == "complete" and .paid == true)] | length')" = "2" ] \
    || fail "expected 2 complete+paid tasks in get_job: $snapshot"
echo "      job complete, progress 1.0, 2/2 tasks complete and paid"

echo "[5/7] get_job_result: merged items + payment receipt"
result=$(post get_job_result "{\"job_id\": \"$JOB_ID\"}")
echo "$result" | jq -e '.results' >/dev/null || fail "get_job_result missing results: $result"
n_results=$(echo "$result" | jq '.results | length')
[ "$n_results" = "4" ] || fail "expected 4 merged result items, got $n_results: $result"
ids=$(echo "$result" | jq -r '[.results[].id] | sort | join(",")')
[ "$ids" = "i1,i2,i3,i4" ] || fail "expected merged ids i1..i4, got: $ids"
[ "$(echo "$result" | jq -r '.receipt.tasks')" = "2" ] || fail "receipt.tasks != 2: $result"
[ "$(echo "$result" | jq -r '.receipt.verified')" = "2" ] || fail "receipt.verified != 2 (all tasks must verify): $result"
echo "$result" | jq -e '.receipt.total_paid == 0.2' >/dev/null \
    || fail "receipt.total_paid != 0.2 (expected price_per_task * 2): $result"
[ "$(echo "$result" | jq '.receipt.payments | length')" = "2" ] || fail "expected 2 payments: $result"
echo "$result" | jq -e '[.receipt.payments[] | select((.tx | startswith("0x")) and .amount == 0.1)] | length == 2' \
    >/dev/null || fail "payments missing tx ids or wrong amount: $result"
echo "      4/4 items merged, 2/2 tasks VERIFIED, total_paid=0.2 TESTUSD, 2 tx receipts"

echo "[6/7] audit_job: full execution tree"
audit=$(post audit_job "{\"job_id\": \"$JOB_ID\"}")
[ "$(echo "$audit" | jq -r '.status')" = "complete" ] || fail "audit: job not complete: $audit"
[ "$(echo "$audit" | jq '.tasks | length')" = "2" ] || fail "audit: expected 2 tasks: $audit"
[ "$(echo "$audit" | jq '[.tasks[] | select(.status != "complete" or .payment == null)] | length')" = "0" ] \
    || fail "audit: found incomplete or unpaid tasks: $audit"
[ "$(echo "$audit" | jq '[.tasks[].attempts[] | select(.verification.outcome != "passed")] | length')" = "0" ] \
    || fail "audit: found non-passed verifications: $audit"
[ "$(echo "$audit" | jq '[.tasks[].attempts[] | select(.result.execution.runtime == null)] | length')" = "0" ] \
    || fail "audit: an attempt is missing the mandatory Contract B execution block: $audit"
execution_runtimes=$(echo "$audit" | jq -r '[.tasks[].attempts[].result.execution.runtime] | unique | join(",")')
if [ "${JACGRID_SANDBOX:-0}" = "1" ]; then
    [ "$(echo "$audit" | jq '[.tasks[].attempts[] | select(.result.execution.runtime == "stub-runner:v0")] | length')" = "0" ] \
        || fail "audit: sandbox run recorded stub execution.runtime: $audit"
else
    [ "$(echo "$audit" | jq '[.tasks[].attempts[] | select(.result.execution.runtime != "stub-runner:v0")] | length')" = "0" ] \
        || fail "audit: fallback run recorded non-stub execution.runtime: $audit"
fi
echo "$audit" | jq -e '.receipt.total_paid == 0.2' >/dev/null || fail "audit receipt total_paid != 0.2: $audit"
echo "      2 tasks -> 2 attempts, all verified, all paid, execution.runtime=$execution_runtimes"

echo "[7/7] network_status: ledger + liveness sanity"
net=$(post network_status '{}')
echo "$net" | jq -e '.server_time and .thresholds.dead_after' >/dev/null || fail "network_status malformed: $net"
echo "$net" | jq -e '.workers[] | select(.name == "m1-worker") | .wallet.balance == 0.2' >/dev/null \
    || fail "expected m1-worker wallet 0.2: $(echo "$net" | jq -c '.workers')"
echo "$net" | jq -e '.wallets[] | select(.owner == "coordinator") | .balance == 9999.8' >/dev/null \
    || fail "expected coordinator wallet 9999.8: $(echo "$net" | jq -c '.wallets')"
echo "$net" | jq -e '.workers[] | select(.name == "m1-worker") | .reputation.success == 2' >/dev/null \
    || fail "expected m1-worker reputation success == 2: $(echo "$net" | jq -c '.workers')"
echo "$net" | jq -e --arg j "$JOB_ID" '.jobs[] | select(.job_id == $j) | .status == "complete"' >/dev/null \
    || fail "network_status does not list the job as complete: $net"
echo "      worker earned 0.2, coordinator paid 0.2, reputation 2/0, job listed complete"

echo
echo "PASS: M1 job lifecycle verified end-to-end over HTTP"
exit 0
