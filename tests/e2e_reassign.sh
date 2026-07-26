#!/usr/bin/env bash
# JacGrid M3 — failure recovery (demo Beat 3).
#
#   Worker A (slow: 20s/task) picks up the only task  ->  kill -9 A
#   ->  detect_failures(dead_after=6) declares A dead and requeues the task
#   ->  worker B picks it up (A is excluded), completes it, gets paid
#   ->  the dead attempt earns NOTHING.
#
# Run:  bash tests/e2e_reassign.sh          (from anywhere; repeatable)
# Exit 0 on success; non-zero with a FAIL message otherwise.

TEST_NAME="reassign"
PORT="${JACGRID_PORT:-8892}"
BASE="http://127.0.0.1:${PORT}"

# shellcheck source=integration/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/integration/lib.sh"

COORD_LOG="$LOGDIR/${TEST_NAME}_coordinator.log"
WORKER_A_LOG="$LOGDIR/${TEST_NAME}_worker_a.log"
WORKER_B_LOG="$LOGDIR/${TEST_NAME}_worker_b.log"

trap cleanup EXIT INT TERM
require_tools

echo "== M3: failure recovery — kill a worker mid-task, watch the grid heal =="

echo
echo "[1] clean graph + start coordinator on port $PORT"
start_coordinator
echo "    coordinator ready on $BASE (pid $COORD_PID)"

echo
echo "[2] submit a 1-task noop job (pays 0.1 TESTUSD on completion)"
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
echo "[3] start worker-a — SLOW: every task takes it 20 seconds"
WORKER_A_PID=$(start_worker "worker-a" "host-a" "$WORKER_A_LOG" \
    JACGRID_TASK_DELAY=20 JACGRID_IDLE_LIMIT=60)
WORKER_PIDS+=("$WORKER_A_PID")   # start_worker runs in a $() subshell; re-register for cleanup
echo "    worker-a pid $WORKER_A_PID"

echo
echo "[4] wait until worker-a is holding the task"
running=""
for _ in $(seq 1 60); do
    kill -0 "$WORKER_A_PID" 2>/dev/null || fail "worker-a exited before picking up the task"
    st=$(post get_job "{\"job_id\": \"$JOB_ID\"}" | jq -r '.tasks[0].status // empty')
    if [ "$st" = "running" ]; then
        running=1
        break
    fi
    sleep 1
done
[ -n "$running" ] || fail "task never entered running state (worker-a did not pick it up)"

WORKER_A_ID=$(post network_status '{}' | jq -r '.workers[] | select(.name == "worker-a") | .worker_id')
[ -n "$WORKER_A_ID" ] || fail "could not resolve worker-a's worker_id from network_status"
echo "    task is RUNNING on worker-a ($WORKER_A_ID) — it will sit on it for 20s"

echo
echo "[5] simulating machine failure: kill -9 worker-a mid-task"
kill -9 "$WORKER_A_PID" 2>/dev/null
echo "    worker-a is gone — no result, no heartbeat will ever arrive"

echo
echo "[6] 8s of silence, then the failure sweep: detect_failures(dead_after=6)"
sleep 8
sweep=$(post detect_failures '{"dead_after": 6}')
echo "$sweep" | jq -e --arg w "$WORKER_A_ID" '.dead_workers | index($w)' >/dev/null \
    || fail "sweep did not declare worker-a dead: $sweep"
action=$(echo "$sweep" | jq -r '.reassigned[0].action // empty')
[ "$action" = "requeued" ] || fail "expected the orphaned task to be requeued, sweep said: $sweep"
echo "$sweep" | jq -e --arg w "$WORKER_A_ID" '.reassigned[0].excluded_workers | index($w)' >/dev/null \
    || fail "requeued task does not exclude worker-a: $sweep"
echo "    coordinator declared worker-a DEAD and requeued its task"
echo "    excluded_workers now contains worker-a — it can never get this task again"

echo
echo "[7] start worker-b — the healthy replacement"
WORKER_B_PID=$(start_worker "worker-b" "host-b" "$WORKER_B_LOG")
WORKER_PIDS+=("$WORKER_B_PID")   # start_worker runs in a $() subshell; re-register for cleanup
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
echo "[9] audit_job: prove the whole story"
audit=$(post audit_job "{\"job_id\": \"$JOB_ID\"}")
[ "$(echo "$audit" | jq -r '.status')" = "complete" ] || fail "audit: job not complete: $audit"

task=$(echo "$audit" | jq -c '.tasks[0]')
echo "$task" | jq -e --arg w "$WORKER_A_ID" '.excluded_workers | index($w)' >/dev/null \
    || fail "audit: task does not exclude worker-a: $task"
[ "$(echo "$task" | jq -r '.attempt_count')" = "2" ] || fail "audit: expected exactly 2 attempts: $task"

a1_worker=$(echo "$task" | jq -r '.attempts[0].worker.name')
a1_status=$(echo "$task" | jq -r '.attempts[0].status')
a2_worker=$(echo "$task" | jq -r '.attempts[1].worker.name')
a2_status=$(echo "$task" | jq -r '.attempts[1].status')
[ "$a1_worker" = "worker-a" ] && [ "$a1_status" = "failed" ] \
    || fail "audit: attempt 1 should be worker-a/failed, got $a1_worker/$a1_status: $task"
[ "$a2_worker" = "worker-b" ] && [ "$a2_status" = "complete" ] \
    || fail "audit: attempt 2 should be worker-b/complete, got $a2_worker/$a2_status: $task"
echo "$task" | jq -e '.attempts[1].verification.outcome == "passed"' >/dev/null \
    || fail "audit: worker-b's result did not verify: $task"

paid_to=$(echo "$task" | jq -r '.payment.worker // empty')
[ "$paid_to" = "worker-b" ] || fail "audit: payment should go to worker-b, went to '${paid_to:-nobody}': $task"
echo "$audit" | jq -e '.receipt.total_paid == 0.1 and (.receipt.payments | length == 1)' >/dev/null \
    || fail "audit: expected exactly one 0.1 payment: $audit"
a_reason=$(echo "$task" | jq -r '.attempts[0].reason')
echo "    attempt 1: worker-a  -> FAILED   ($a_reason)"
echo "    attempt 2: worker-b  -> COMPLETE (verification passed)"
echo "    payment  : 0.1 TESTUSD -> worker-b only"

echo
echo "[10] wallets: the dead worker earned nothing"
net=$(post network_status '{}')
echo "$net" | jq -e '.workers[] | select(.name == "worker-a") | .wallet.balance == 0' >/dev/null \
    || fail "worker-a should have earned 0: $(echo "$net" | jq -c '.workers')"
echo "$net" | jq -e '.workers[] | select(.name == "worker-b") | .wallet.balance == 0.1' >/dev/null \
    || fail "worker-b should have earned 0.1: $(echo "$net" | jq -c '.workers')"
echo "$net" | jq -e '.wallets[] | select(.owner == "coordinator") | .balance == 9999.9' >/dev/null \
    || fail "coordinator should have paid exactly 0.1: $(echo "$net" | jq -c '.wallets')"
echo "    worker-a balance: 0.0  (killed mid-task — no pay for the dead attempt)"
echo "    worker-b balance: 0.1  (did the work, got the money)"

echo
echo "PASS: M3 failure recovery verified — worker killed, task reassigned, job completed, only the finisher paid"
exit 0
