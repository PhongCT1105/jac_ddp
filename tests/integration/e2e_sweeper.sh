#!/usr/bin/env bash
# JacGrid e2e — periodic failure detection with NO live worker (spec §2.4).
#
# The strict version of the reassignment test. Here the ONLY worker dies while
# holding a task, and then:
#   * nobody calls detect_failures by hand,
#   * no other worker ever polls next_task or sends a heartbeat.
# The implicit sweeps inside next_task/heartbeat therefore cannot fire. If the
# task still gets requeued, it can only be the out-of-process sweeper.
#
# This is the test that would fail if we relied on the coordinator's own
# @schedule support, which does not commit graph writes on jac-scale 0.2.31.
#
# Run:  bash tests/integration/e2e_sweeper.sh

TEST_NAME="sweeper"
PORT="${JACGRID_PORT:-8893}"
BASE="http://127.0.0.1:${PORT}"

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

COORD_LOG="$LOGDIR/${TEST_NAME}_coordinator.log"
WORKER_LOG="$LOGDIR/${TEST_NAME}_worker_a.log"
SWEEPER_LOG="$LOGDIR/${TEST_NAME}_sweeper.log"

trap cleanup EXIT INT TERM
require_tools

echo "== e2e sweeper: heal a dead grid with no worker left alive (port $PORT) =="

echo
echo "[1] start coordinator (dead_after=6s)"
start_coordinator
echo "    coordinator ready on $BASE"

echo
echo "[2] submit a single-task noop job"
job_reply=$(post create_job '{
    "app_id": "e2e-sweeper",
    "job_type": "noop",
    "payload": {"items": [{"id": "s1", "text": "sweep me"}]},
    "partitioning": {"strategy": "chunk", "chunk_size": 1},
    "verification": {"method": "recompute_sample", "sample_rate": 1.0},
    "budget": {"max_total": 1.0, "price_per_task": 0.1, "currency": "TESTUSD"}
}')
JOB_ID=$(echo "$job_reply" | jq -r '.job_id // empty')
[ -n "$JOB_ID" ] || fail "create_job returned no job_id: $job_reply"
echo "    job_id=$JOB_ID"

echo
echo "[3] start the ONLY worker — slow, so it will still be holding the task"
WORKER_PID=$(start_worker "lonely" "lonely-host" "$WORKER_LOG" \
    JACGRID_TASK_DELAY=60 JACGRID_IDLE_LIMIT=60 JACGRID_DEAD_AFTER=6)
echo "    worker pid $WORKER_PID"

running=""
for _ in $(seq 1 60); do
    kill -0 "$WORKER_PID" 2>/dev/null || fail "worker exited before picking up the task"
    st=$(post get_job "{\"job_id\": \"$JOB_ID\"}" | jq -r '.tasks[0].status // empty')
    if [ "$st" = "running" ]; then running=1; break; fi
    sleep 1
done
[ -n "$running" ] || fail "task never entered running state"
WORKER_ID=$(post network_status '{}' | jq -r '.workers[] | select(.name == "lonely") | .worker_id')
echo "    task RUNNING on the only worker ($WORKER_ID)"

echo
echo "[4] kill it. the grid now has ZERO live workers"
kill -9 "$WORKER_PID" 2>/dev/null
wait "$WORKER_PID" 2>/dev/null
echo "    worker gone; nothing will ever poll next_task or heartbeat again"

echo
echo "[5] confirm the task is STILL stuck (no sweeper running yet)"
sleep 10
stuck=$(post get_job "{\"job_id\": \"$JOB_ID\"}" | jq -r '.tasks[0].status')
[ "$stuck" = "running" ] \
    || fail "expected the task to still be stuck at 'running' before the sweeper starts, got '$stuck'"
echo "    after 10s of silence the task is still 'running' — nothing self-heals on its own"

echo
echo "[6] start the sweeper (JACGRID_MODE=sweeper, every 2s) and touch NOTHING else"
SWEEPER_PID=$(start_sweeper "$SWEEPER_LOG" JACGRID_SWEEP_INTERVAL=2 JACGRID_MAX_LOOPS=40)
echo "    sweeper pid $SWEEPER_PID"

echo
echo "[7] wait for the sweeper alone to requeue the orphaned task"
requeued=""
for _ in $(seq 1 40); do
    st=$(post get_job "{\"job_id\": \"$JOB_ID\"}" | jq -r '.tasks[0].status // empty')
    if [ "$st" = "queued" ]; then requeued=1; break; fi
    sleep 1
done
[ -n "$requeued" ] || fail "sweeper did not requeue the task within 40s (still '$st')"
echo "    task is back to 'queued' — requeued with no worker and no manual call"

echo
echo "[8] prove the sweeper did it, and that the dead worker is excluded"
grep -q "sweeper:" "$SWEEPER_LOG" || fail "sweeper log has no sweep activity: $(tail -5 "$SWEEPER_LOG")"
echo "    sweeper log: $(grep -m1 'sweeper:' "$SWEEPER_LOG" | cut -c1-120)"
audit=$(post audit_job "{\"job_id\": \"$JOB_ID\"}")
echo "$audit" | jq -e --arg w "$WORKER_ID" '.tasks[0].excluded_workers | index($w)' >/dev/null \
    || fail "requeued task does not exclude the dead worker: $audit"
[ "$(echo "$audit" | jq -r '.tasks[0].attempts[0].status')" = "failed" ] \
    || fail "the dead worker's attempt should be failed: $audit"
echo "    dead worker excluded, its attempt marked failed"

echo
echo "[9] a fresh worker now finishes the job"
NEW_PID=$(start_worker "rescuer" "rescue-host" "$LOGDIR/${TEST_NAME}_worker_b.log")
status=""
for _ in $(seq 1 60); do
    status=$(post get_job "{\"job_id\": \"$JOB_ID\"}" | jq -r '.status // empty')
    [ "$status" = "complete" ] && break
    [ "$status" = "failed" ] && fail "job failed instead of recovering"
    sleep 1
done
[ "$status" = "complete" ] || fail "job did not complete after rescue (last: ${status:-none})"
echo "$audit" >/dev/null
net=$(post network_status '{}')
echo "$net" | jq -e '.workers[] | select(.name == "rescuer") | .wallet.balance == 0.1' >/dev/null \
    || fail "rescuer should have earned 0.1: $(echo "$net" | jq -c '.workers')"
echo "$net" | jq -e '.workers[] | select(.name == "lonely") | .wallet.balance == 0' >/dev/null \
    || fail "the dead worker should have earned 0"
echo "    job complete; rescuer paid 0.1, dead worker paid 0.0"

echo
echo "PASS: periodic sweep verified — an all-dead grid recovered with only the sweeper running"
exit 0
