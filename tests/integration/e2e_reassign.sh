#!/usr/bin/env bash
# JacGrid e2e — failure recovery (milestone M3, demo Beat 3).
#
#   worker-a (slow) picks up a task -> kill -9 worker-a -> detect_failures
#   declares it dead and requeues the task excluding it -> worker-b finishes
#   the job -> only worker-b is paid.
#
# Run:  bash tests/integration/e2e_reassign.sh
# Exit 0 on success; non-zero with a FAIL message otherwise.

TEST_NAME="reassign"
PORT="${JACGRID_PORT:-8892}"
BASE="http://127.0.0.1:${PORT}"

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

COORD_LOG="$LOGDIR/${TEST_NAME}_coordinator.log"
WORKER_A_LOG="$LOGDIR/${TEST_NAME}_worker_a.log"
WORKER_B_LOG="$LOGDIR/${TEST_NAME}_worker_b.log"

trap cleanup EXIT INT TERM
require_tools

echo "== e2e reassign: kill a worker mid-task, watch the grid heal (port $PORT) =="

echo
echo "[1] clean graph + start coordinator"
start_coordinator
echo "    coordinator ready on $BASE (pid $COORD_PID)"

echo
echo "[2] submit a single-task noop job worth 0.1 TESTUSD"
job_reply=$(post create_job '{
    "app_id": "e2e-reassign",
    "job_type": "noop",
    "payload": {"items": [
        {"id": "r1", "text": "resilience"},
        {"id": "r2", "text": "recovery"}
    ]},
    "partitioning": {"strategy": "chunk", "chunk_size": 2},
    "verification": {"method": "recompute_sample", "sample_rate": 1.0},
    "budget": {"max_total": 1.0, "price_per_task": 0.1, "currency": "TESTUSD"}
}')
JOB_ID=$(echo "$job_reply" | jq -r '.job_id // empty')
[ -n "$JOB_ID" ] || fail "create_job returned no job_id: $job_reply"
[ "$(echo "$job_reply" | jq -r '.task_count')" = "1" ] || fail "expected task_count 1: $job_reply"
echo "    job_id=$JOB_ID (1 task)"

echo
echo "[3] start worker-a — deliberately slow (20s per task)"
WORKER_A_PID=$(start_worker "worker-a" "host-a" "$WORKER_A_LOG" \
    JACGRID_TASK_DELAY=20 JACGRID_IDLE_LIMIT=60)
echo "    worker-a pid $WORKER_A_PID"

echo
echo "[4] wait until worker-a is holding the task"
running=""
for _ in $(seq 1 60); do
    kill -0 "$WORKER_A_PID" 2>/dev/null || fail "worker-a exited before picking up the task"
    st=$(post get_job "{\"job_id\": \"$JOB_ID\"}" | jq -r '.tasks[0].status // empty')
    if [ "$st" = "running" ]; then running=1; break; fi
    sleep 1
done
[ -n "$running" ] || fail "task never entered running state (worker-a did not pick it up)"

WORKER_A_ID=$(post network_status '{}' | jq -r '.workers[] | select(.name == "worker-a") | .worker_id')
[ -n "$WORKER_A_ID" ] || fail "could not resolve worker-a's worker_id"
echo "    task RUNNING on worker-a ($WORKER_A_ID), which will sit on it for 20s"

echo
echo "[5] simulate machine failure: kill -9 worker-a mid-task"
kill -9 "$WORKER_A_PID" 2>/dev/null
wait "$WORKER_A_PID" 2>/dev/null
echo "    worker-a is gone — no result and no heartbeat will ever arrive"

echo
echo "[6] 8s of silence, then run the failure sweep with dead_after=6"
sleep 8
sweep=$(post detect_failures '{"dead_after": 6}')
echo "$sweep" | jq -e --arg w "$WORKER_A_ID" '.dead_workers | index($w)' >/dev/null \
    || fail "sweep did not declare worker-a dead: $sweep"
[ "$(echo "$sweep" | jq -r '.reassigned[0].action // empty')" = "requeued" ] \
    || fail "expected the orphaned task to be requeued: $sweep"
echo "$sweep" | jq -e --arg w "$WORKER_A_ID" '.reassigned[0].excluded_workers | index($w)' >/dev/null \
    || fail "requeued task does not exclude worker-a: $sweep"
echo "    worker-a declared DEAD, its task requeued with worker-a on the excluded list"

echo
echo "[7] start worker-b — healthy replacement"
WORKER_B_PID=$(start_worker "worker-b" "host-b" "$WORKER_B_LOG")
echo "    worker-b pid $WORKER_B_PID"

echo
echo "[8] poll get_job until the reassigned task completes"
status=""
for _ in $(seq 1 90); do
    status=$(post get_job "{\"job_id\": \"$JOB_ID\"}" | jq -r '.status // empty')
    [ "$status" = "complete" ] && break
    [ "$status" = "failed" ] && fail "job failed instead of recovering: $(post get_job "{\"job_id\": \"$JOB_ID\"}")"
    sleep 1
done
[ "$status" = "complete" ] || fail "job did not complete within 90s after reassignment (last: ${status:-none})"
echo "    job COMPLETE — the grid healed itself"

echo
echo "[9] audit_job: the whole story in the graph"
audit=$(post audit_job "{\"job_id\": \"$JOB_ID\"}")
[ "$(echo "$audit" | jq -r '.status')" = "complete" ] || fail "audit: job not complete: $audit"
task=$(echo "$audit" | jq -c '.tasks[0]')
echo "$task" | jq -e --arg w "$WORKER_A_ID" '.excluded_workers | index($w)' >/dev/null \
    || fail "audit: task does not exclude worker-a: $task"
[ "$(echo "$task" | jq -r '.attempt_count')" = "2" ] || fail "audit: expected exactly 2 attempts: $task"
[ "$(echo "$task" | jq -r '.attempts[0].worker.name')" = "worker-a" ] \
    && [ "$(echo "$task" | jq -r '.attempts[0].status')" = "failed" ] \
    || fail "audit: attempt 1 should be worker-a/failed: $task"
[ "$(echo "$task" | jq -r '.attempts[1].worker.name')" = "worker-b" ] \
    && [ "$(echo "$task" | jq -r '.attempts[1].status')" = "complete" ] \
    || fail "audit: attempt 2 should be worker-b/complete: $task"
echo "$task" | jq -e '.attempts[1].verification.outcome == "passed"' >/dev/null \
    || fail "audit: worker-b's result did not verify: $task"
[ "$(echo "$task" | jq -r '.payment.worker // empty')" = "worker-b" ] \
    || fail "audit: payment should go to worker-b: $task"
echo "$audit" | jq -e '.receipt.total_paid == 0.1 and (.receipt.payments | length == 1)' >/dev/null \
    || fail "audit: expected exactly one 0.1 payment: $audit"
echo "    attempt 1: worker-a -> FAILED   ($(echo "$task" | jq -r '.attempts[0].reason'))"
echo "    attempt 2: worker-b -> COMPLETE (verification passed)"
echo "    payment  : 0.1 TESTUSD -> worker-b only"

echo
echo "[10] wallets: the dead worker earned nothing"
net=$(post network_status '{}')
echo "$net" | jq -e '.workers[] | select(.name == "worker-a") | .wallet.balance == 0' >/dev/null \
    || fail "worker-a should have earned 0: $(echo "$net" | jq -c '.workers')"
echo "$net" | jq -e '.workers[] | select(.name == "worker-b") | .wallet.balance == 0.1' >/dev/null \
    || fail "worker-b should have earned 0.1: $(echo "$net" | jq -c '.workers')"
echo "    worker-a balance 0.0 (killed mid-task, no payment for a dead attempt)"
echo "    worker-b balance 0.1 (did the work, got the money)"

echo
echo "PASS: failure recovery verified — worker killed, task reassigned, job completed, only the finisher paid"
exit 0
