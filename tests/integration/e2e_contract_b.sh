#!/usr/bin/env bash
# JacGrid e2e — Contract B enforcement at submit_result (architecture §5).
#
# "The `execution` block is mandatory — it feeds the Sandbox and Attempt nodes
#  in the Jac graph and the audit timeline."
#
# A submission that omits or mangles it is a PROTOCOL VIOLATION, not a failed
# task: it must be rejected outright, nothing may enter the graph, and the
# Attempt must be left running so the task can still be reassigned. This test
# drives submit_result directly (no worker) to cover the malformed cases, then
# proves a well-formed envelope on the SAME attempt still succeeds.
#
# Run:  bash tests/integration/e2e_contract_b.sh

TEST_NAME="contract_b"
PORT="${JACGRID_PORT:-8894}"
BASE="http://127.0.0.1:${PORT}"

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

COORD_LOG="$LOGDIR/${TEST_NAME}_coordinator.log"

trap cleanup EXIT INT TERM
require_tools

PASSES=0
# expect_rejected <label> <result_envelope-json>
expect_rejected() {
    local label="$1" envelope="$2"
    local reply
    reply=$(post submit_result "$(jq -cn --arg t "$TASK_ID" --argjson e "$envelope" \
        '{task_id:$t, result_envelope:$e}')")
    [ "$(echo "$reply" | jq -r '.error // empty')" = "protocol_violation" ] \
        || fail "$label: expected error=protocol_violation, got: $reply"
    [ "$(echo "$reply" | jq -r '.task_status')" = "running" ] \
        || fail "$label: task must stay running so it can be reassigned, got: $reply"
    local st
    st=$(post get_job "{\"job_id\": \"$JOB_ID\"}" | jq -r '.tasks[0].status')
    [ "$st" = "running" ] || fail "$label: task status changed to '$st' in the graph"
    [ "$(post audit_job "{\"job_id\": \"$JOB_ID\"}" | jq '.tasks[0].attempts[0].result')" = "null" ] \
        || fail "$label: a Result node leaked into the graph"
    PASSES=$((PASSES + 1))
    echo "    rejected: $label"
    echo "              -> $(echo "$reply" | jq -c '.detail')"
}

echo "== e2e contract B: submit_result rejects malformed result envelopes (port $PORT) =="

echo
echo "[1] start coordinator"
start_coordinator
echo "    coordinator ready on $BASE"

echo
echo "[2] register a worker and hand it a task (no worker process — we submit by hand)"
WORKER_ID=$(post register_worker '{"hostname":"cb-host","worker_name":"cb-worker",
    "capabilities":{"job_types":["noop"]}}' | jq -r '.worker_id')
[ -n "$WORKER_ID" ] || fail "could not register worker"
JOB_ID=$(post create_job '{
    "app_id": "e2e-contract-b",
    "job_type": "noop",
    "payload": {"items": [{"id": "c1", "text": "contract"}]},
    "partitioning": {"strategy": "chunk", "chunk_size": 1},
    "verification": {"method": "recompute_sample", "sample_rate": 1.0},
    "budget": {"max_total": 1.0, "price_per_task": 0.1, "currency": "TESTUSD"}
}' | jq -r '.job_id')
[ -n "$JOB_ID" ] || fail "could not create job"
TASK_ID=$(post next_task "{\"worker_id\": \"$WORKER_ID\"}" | jq -r '.task.task_id // empty')
[ -n "$TASK_ID" ] || fail "next_task returned no task"
echo "    worker=$WORKER_ID job=$JOB_ID task=$TASK_ID (attempt running)"

echo
echo "[3] every malformed envelope must be rejected as a protocol violation"

expect_rejected "execution block missing entirely" \
    '{"status":"ok","output":{"results":[{"id":"c1","text":"contract"}]}}'

expect_rejected "execution present but null" \
    '{"status":"ok","output":{"results":[{"id":"c1","text":"contract"}]},"execution":null}'

expect_rejected "execution is a string, not an object" \
    '{"status":"ok","output":{"results":[{"id":"c1","text":"contract"}]},"execution":"stub-runner:v0"}'

expect_rejected "execution missing cpu_seconds and exit_code" \
    '{"status":"ok","output":{"results":[{"id":"c1","text":"contract"}]},
      "execution":{"runtime":"stub:v0","started_at":"2026-07-26T00:00:00Z",
                   "finished_at":"2026-07-26T00:00:01Z","peak_memory_mb":1}}'

expect_rejected "execution.runtime empty" \
    '{"status":"ok","output":{"results":[{"id":"c1","text":"contract"}]},
      "execution":{"runtime":"","started_at":"2026-07-26T00:00:00Z",
                   "finished_at":"2026-07-26T00:00:01Z","peak_memory_mb":1,
                   "cpu_seconds":0.1,"exit_code":0}}'

expect_rejected "status outside the Contract B vocabulary" \
    '{"status":"finished","output":{"results":[{"id":"c1","text":"contract"}]},
      "execution":{"runtime":"stub:v0","started_at":"2026-07-26T00:00:00Z",
                   "finished_at":"2026-07-26T00:00:01Z","peak_memory_mb":1,
                   "cpu_seconds":0.1,"exit_code":0}}'

expect_rejected "output is a list, not an object" \
    '{"status":"ok","output":[{"id":"c1"}],
      "execution":{"runtime":"stub:v0","started_at":"2026-07-26T00:00:00Z",
                   "finished_at":"2026-07-26T00:00:01Z","peak_memory_mb":1,
                   "cpu_seconds":0.1,"exit_code":0}}'

expect_rejected "ok status with null output" \
    '{"status":"ok","output":null,
      "execution":{"runtime":"stub:v0","started_at":"2026-07-26T00:00:00Z",
                   "finished_at":"2026-07-26T00:00:01Z","peak_memory_mb":1,
                   "cpu_seconds":0.1,"exit_code":0}}'

expect_rejected "execution.started_at empty" \
    '{"status":"ok","output":{},
      "execution":{"runtime":"stub:v0","started_at":"",
                   "finished_at":"2026-07-26T00:00:01Z","peak_memory_mb":1,
                   "cpu_seconds":0.1,"exit_code":0}}'

expect_rejected "execution.finished_at is not a string" \
    '{"status":"ok","output":{},
      "execution":{"runtime":"stub:v0","started_at":"2026-07-26T00:00:00Z",
                   "finished_at":42,"peak_memory_mb":1,
                   "cpu_seconds":0.1,"exit_code":0}}'

expect_rejected "execution.peak_memory_mb rejects bool" \
    '{"status":"ok","output":{},
      "execution":{"runtime":"stub:v0","started_at":"2026-07-26T00:00:00Z",
                   "finished_at":"2026-07-26T00:00:01Z","peak_memory_mb":true,
                   "cpu_seconds":0.1,"exit_code":0}}'

expect_rejected "execution.cpu_seconds rejects negative" \
    '{"status":"ok","output":{},
      "execution":{"runtime":"stub:v0","started_at":"2026-07-26T00:00:00Z",
                   "finished_at":"2026-07-26T00:00:01Z","peak_memory_mb":1,
                   "cpu_seconds":-0.1,"exit_code":0}}'

expect_rejected "execution.exit_code rejects string" \
    '{"status":"ok","output":{},
      "execution":{"runtime":"stub:v0","started_at":"2026-07-26T00:00:00Z",
                   "finished_at":"2026-07-26T00:00:01Z","peak_memory_mb":1,
                   "cpu_seconds":0.1,"exit_code":"0"}}'

echo "    $PASSES malformed envelopes rejected; graph untouched every time"

echo
echo "[4] the task survived all of it and is still assigned + reassignable"
[ "$(post get_job "{\"job_id\": \"$JOB_ID\"}" | jq -r '.tasks[0].status')" = "running" ] \
    || fail "task should still be running"
audit=$(post audit_job "{\"job_id\": \"$JOB_ID\"}")
[ "$(echo "$audit" | jq '.tasks[0].attempts | length')" = "1" ] \
    || fail "expected exactly 1 attempt, no phantom attempts: $audit"
[ "$(echo "$audit" | jq -r '.tasks[0].attempts[0].status')" = "running" ] \
    || fail "the attempt must still be running so the timeout path can reassign it"
[ "$(echo "$audit" | jq -r '.tasks[0].payment')" = "null" ] \
    || fail "nothing may have been paid: $audit"
echo "    1 attempt, still running, no Result, no Verification, no Payment"

echo
echo "[5] a WELL-FORMED envelope on the same attempt is accepted, verified and paid"
good=$(post submit_result "$(jq -cn --arg t "$TASK_ID" '{
    task_id: $t,
    result_envelope: {
        status: "ok",
        output: {results: [{id: "c1", text: "contract"}]},
        execution: {runtime: "stub-runner:v0", started_at: "2026-07-26T00:00:00Z",
                    finished_at: "2026-07-26T00:00:01Z", peak_memory_mb: 12,
                    cpu_seconds: 0.42, exit_code: 0},
        error: null
    }}')")
[ "$(echo "$good" | jq -r '.task_status')" = "complete" ] \
    || fail "well-formed submission was not accepted: $good"
[ "$(echo "$good" | jq -r '.verification.outcome')" = "passed" ] \
    || fail "well-formed submission did not verify: $good"
echo "$good" | jq -e '.payment.amount == 0.1' >/dev/null \
    || fail "well-formed submission was not paid: $good"
echo "    accepted -> verification passed -> 0.1 TESTUSD paid"
final=$(post audit_job "{\"job_id\": \"$JOB_ID\"}")
echo "$final" | jq -e '.tasks[0].attempts[0].result.execution.runtime == "stub-runner:v0"' >/dev/null \
    || fail "the execution block did not reach the audit timeline: $final"
echo "    execution metadata is in the audit timeline, as the contract requires"

echo
echo "[6] output:null is valid for a timeout envelope and fails without payment"
TIMEOUT_JOB_ID=$(post create_job '{
    "app_id": "e2e-contract-b",
    "job_type": "noop",
    "payload": {"items": [{"id": "timeout-1", "text": "timeout"}]},
    "partitioning": {"strategy": "chunk", "chunk_size": 1},
    "verification": {"method": "recompute_sample", "sample_rate": 1.0},
    "budget": {"max_total": 1.0, "price_per_task": 0.1, "currency": "TESTUSD"}
}' | jq -r '.job_id')
TIMEOUT_TASK_ID=$(post next_task "{\"worker_id\": \"$WORKER_ID\"}" | jq -r '.task.task_id // empty')
[ -n "$TIMEOUT_TASK_ID" ] || fail "timeout task was not assigned"
timeout_reply=$(post submit_result "$(jq -cn --arg t "$TIMEOUT_TASK_ID" '{
    task_id:$t,
    result_envelope:{
      task_id:$t,status:"timeout",output:null,
      execution:{runtime:"noop-runner:1.0.0",started_at:"2026-07-26T00:00:00Z",
                 finished_at:"2026-07-26T00:00:02Z",peak_memory_mb:2,
                 cpu_seconds:0.2,exit_code:-9},
      error:"wall limit exceeded"
    }}')")
[ "$(echo "$timeout_reply" | jq -r '.error // empty')" != "protocol_violation" ] \
    || fail "legitimate timeout envelope was rejected as protocol violation: $timeout_reply"
[ "$(echo "$timeout_reply" | jq -r '.verification.outcome')" = "failed" ] \
    || fail "timeout did not fail verification: $timeout_reply"
[ "$(echo "$timeout_reply" | jq '.payment')" = "null" ] \
    || fail "timeout attempt was paid: $timeout_reply"
timeout_audit=$(post audit_job "{\"job_id\": \"$TIMEOUT_JOB_ID\"}")
echo "$timeout_audit" | jq -e '.tasks[0].payment == null and .tasks[0].attempts[0].result.status == "timeout"' \
    >/dev/null || fail "timeout result was not safely persisted without payment: $timeout_audit"
echo "    timeout accepted as Contract B failure, requeued, and unpaid"

echo
echo "PASS: Contract B enforced — $PASSES malformed envelopes rejected without touching the graph, well-formed one accepted"
exit 0
