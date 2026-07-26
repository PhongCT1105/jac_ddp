#!/usr/bin/env bash
# Focused verifier-integrity proof:
# 1) a structurally valid but wrong 384-d embedding fails real recomputation
#    and receives no payment;
# 2) a genuine sandbox-produced retry passes with matching runtime and pays.
set -uo pipefail

TEST_NAME="embedding_verification"
PORT="${JACGRID_PORT:-8896}"
BASE="http://127.0.0.1:${PORT}"
EXPECTED_EMBEDDING_RUNTIME="${EXPECTED_EMBEDDING_RUNTIME:-connection-embedding:1.0.0}"
if [ "$EXPECTED_EMBEDDING_RUNTIME" = "connection-embedding:1.0.0" ]; then
    MISMATCH_RUNTIME="connection-embedding-fallback:1.0.0"
else
    MISMATCH_RUNTIME="connection-embedding:1.0.0"
fi

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

COORD_LOG="$LOGDIR/${TEST_NAME}_coordinator.log"
WORKER_LOG="$LOGDIR/${TEST_NAME}_worker_correct.log"

trap cleanup EXIT INT TERM
require_tools

echo "== e2e embedding verification integrity (port $PORT) =="
echo "[1/5] start coordinator"
start_coordinator

echo "      reject verification methods that could bypass recomputation"
for invalid_spec in \
    '{"method":"output_hash","expected_hash":"deadbeef"}' \
    '{"method":"unknown_method"}'; do
    rejected="$(post create_job "$(jq -cn --argjson verification "$invalid_spec" '{
      app_id:"e2e-verification-bypass",job_type:"embedding",
      payload:{model:"all-MiniLM-L6-v2",items:[{id:"bypass-1",text:"must recompute"}]},
      partitioning:{strategy:"chunk",chunk_size:1},
      verification:$verification,
      budget:{max_total:1.0,price_per_task:0.1,currency:"TESTUSD"}
    }')")"
    [ "$(printf '%s' "$rejected" | jq -r '.error // empty')" = "invalid_request" ] \
        || fail "embedding verification bypass was accepted: $invalid_spec -> $rejected"
done
noop_hashless="$(post create_job '{
  "app_id":"e2e-verification-bypass","job_type":"noop",
  "payload":{"items":[{"id":"hashless-1","text":"must have expected hash"}]},
  "partitioning":{"strategy":"chunk","chunk_size":1},
  "verification":{"method":"output_hash"},
  "budget":{"max_total":1.0,"price_per_task":0.1,"currency":"TESTUSD"}
}')"
[ "$(printf '%s' "$noop_hashless" | jq -r '.error // empty')" = "invalid_request" ] \
    || fail "hashless output_hash job was accepted: $noop_hashless"

echo "[2/5] submit one embedding task and assign it to a manual tamper worker"
TAMPER_WORKER_ID="$(post register_worker '{
    "hostname":"tamper-host",
    "worker_name":"tamper-worker",
    "capabilities":{"job_types":["embedding"],"runtime":"manual-tamper:v1"}
}' | jq -r '.worker_id // empty')"
[ -n "$TAMPER_WORKER_ID" ] || fail "could not register tamper worker"

JOB_ID="$(post create_job '{
    "app_id":"e2e-embedding-verifier",
    "job_type":"embedding",
    "payload":{"model":"all-MiniLM-L6-v2","items":[
        {"id":"verify-1","text":"distributed graph compute and reliable systems"}
    ]},
    "partitioning":{"strategy":"chunk","chunk_size":1},
    "verification":{"method":"recompute_sample","sample_rate":1.0},
    "budget":{"max_total":1.0,"price_per_task":0.1,"currency":"TESTUSD"}
}' | jq -r '.job_id // empty')"
[ -n "$JOB_ID" ] || fail "could not create embedding job"
TASK_REPLY="$(post next_task "$(jq -cn --arg id "$TAMPER_WORKER_ID" '{worker_id:$id}')")"
TASK_ID="$(printf '%s' "$TASK_REPLY" | jq -r '.task.task_id // empty')"
[ -n "$TASK_ID" ] || fail "tamper worker did not receive the task"
printf '%s' "$TASK_REPLY" | jq -e '
  .task.workload.id == "connection-embedding" and
  .task.workload.version == "1.0.0" and
  (.task.workload.manifest_sha256 | type == "string" and length > 10) and
  (.task.workload.package_sha256 | type == "string" and length > 10) and
  (.task.workload.runtime_tags | index("connection-embedding:1.0.0")) != null and
  .task.workload.verification.tolerance == 0.001
' >/dev/null || fail "task envelope did not freeze immutable workload identity/policy: $TASK_REPLY"

echo "[3/5] submit a wrong but structurally valid 384-d vector"
WRONG_VECTOR="$(jq -cn '[range(0;384) | 0.0]')"
TAMPER_REPLY="$(post submit_result "$(jq -cn \
    --arg task "$TASK_ID" \
    --arg runtime "$MISMATCH_RUNTIME" \
    --argjson vector "$WRONG_VECTOR" \
    '{
      task_id:$task,
      result_envelope:{
        task_id:$task,
        status:"ok",
        output:{results:[{id:"verify-1",embedding:$vector}]},
        execution:{
          runtime:$runtime,
          started_at:"2026-07-26T00:00:00Z",
          finished_at:"2026-07-26T00:00:01Z",
          peak_memory_mb:1.0,
          cpu_seconds:0.01,
          exit_code:0
        },
        error:null
      }
    }')")"
printf '%s' "$TAMPER_REPLY" | jq -e '
  .verification.outcome == "failed" and
  .verification.detail.recompute == true and
  (.verification.detail.recomputed_compared // 0) > 0 and
  (.verification.detail.problems | any(.reason == "cosine_below_tolerance")) and
  (.verification.detail.problems | any(.reason == "runtime_mismatch")) and
  .payment == null
' >/dev/null || fail "tampered vector was not rejected by real recomputation: $TAMPER_REPLY"

TAMPER_AUDIT="$(post audit_job "$(jq -cn --arg id "$JOB_ID" '{job_id:$id}')")"
printf '%s' "$TAMPER_AUDIT" | jq -e '
  .tasks[0].payment == null and
  .tasks[0].attempts[0].verification.outcome == "failed" and
  .tasks[0].attempts[0].verification.detail.recompute == true
' >/dev/null || fail "tampered attempt leaked a payment or lacked recompute evidence: $TAMPER_AUDIT"

echo "      also prove a real recompute workload error fails closed"
ERROR_JOB_ID="$(post create_job '{
    "app_id":"e2e-embedding-verifier",
    "job_type":"embedding",
    "payload":{"model":"all-MiniLM-L6-v2","items":[{"id":"invalid-no-text"}]},
    "partitioning":{"strategy":"chunk","chunk_size":1},
    "verification":{"method":"recompute_sample","sample_rate":1.0},
    "budget":{"max_total":1.0,"price_per_task":0.1,"currency":"TESTUSD"}
}' | jq -r '.job_id // empty')"
[ -n "$ERROR_JOB_ID" ] || fail "could not create recompute-error job"
ERROR_TASK_ID="$(post next_task "$(jq -cn --arg id "$TAMPER_WORKER_ID" '{worker_id:$id}')" \
    | jq -r '.task.task_id // empty')"
[ -n "$ERROR_TASK_ID" ] || fail "tamper worker did not receive recompute-error task"
ERROR_REPLY="$(post submit_result "$(jq -cn \
    --arg task "$ERROR_TASK_ID" \
    --arg runtime "$EXPECTED_EMBEDDING_RUNTIME" \
    --argjson vector "$WRONG_VECTOR" \
    '{
      task_id:$task,
      result_envelope:{
        task_id:$task,
        status:"ok",
        output:{results:[{id:"invalid-no-text",embedding:$vector}]},
        execution:{
          runtime:$runtime,
          started_at:"2026-07-26T00:00:00Z",
          finished_at:"2026-07-26T00:00:01Z",
          peak_memory_mb:1.0,
          cpu_seconds:0.01,
          exit_code:0
        },
        error:null
      }
    }')")"
printf '%s' "$ERROR_REPLY" | jq -e '
  .verification.outcome == "failed" and
  .verification.detail.recompute == true and
  .verification.detail.recompute_status == "error" and
  (.verification.detail.problems | any(.reason == "recompute_error")) and
  .payment == null
' >/dev/null || fail "recompute error did not fail closed without payment: $ERROR_REPLY"

echo "      malformed vector on a deterministic non-sampled item still fails"
SHAPE_JOB_ID="$(post create_job '{
    "app_id":"e2e-embedding-verifier",
    "job_type":"embedding",
    "payload":{"model":"all-MiniLM-L6-v2","items":[
      {"id":"shape-1","text":"first shape item"},
      {"id":"shape-2","text":"second shape item"}
    ]},
    "partitioning":{"strategy":"chunk","chunk_size":2},
    "verification":{"method":"recompute_sample","sample_rate":0.5},
    "budget":{"max_total":1.0,"price_per_task":0.1,"currency":"TESTUSD"}
}' | jq -r '.job_id // empty')"
SHAPE_REPLY="$(post next_task "$(jq -cn --arg id "$TAMPER_WORKER_ID" '{worker_id:$id}')")"
SHAPE_TASK_ID="$(printf '%s' "$SHAPE_REPLY" | jq -r '.task.task_id // empty')"
[ -n "$SHAPE_TASK_ID" ] || fail "shape task was not assigned"
NON_SAMPLED_INDEX="$(python3 - "$SHAPE_TASK_ID" <<'PY'
import random, sys
indexes = [0, 1]
random.Random(sys.argv[1]).shuffle(indexes)
print(indexes[1])
PY
)"
NON_SAMPLED_ID="shape-$((NON_SAMPLED_INDEX + 1))"
SHAPE_OUTPUT="$(jq -cn --arg bad "$NON_SAMPLED_ID" '
  [range(0;384) | 0.0] as $zero
  | {results:[
      {id:"shape-1",embedding:(if $bad == "shape-1" then (["not-a-number"] + $zero[1:]) else $zero end)},
      {id:"shape-2",embedding:(if $bad == "shape-2" then (["not-a-number"] + $zero[1:]) else $zero end)}
    ]}')"
SHAPE_RESULT="$(post submit_result "$(jq -cn \
  --arg task "$SHAPE_TASK_ID" --arg runtime "$EXPECTED_EMBEDDING_RUNTIME" \
  --argjson output "$SHAPE_OUTPUT" '{
    task_id:$task,
    result_envelope:{
      task_id:$task,status:"ok",output:$output,
      execution:{runtime:$runtime,started_at:"2026-07-26T00:00:00Z",
                 finished_at:"2026-07-26T00:00:01Z",peak_memory_mb:1,
                 cpu_seconds:0.01,exit_code:0},
      error:null
    }}')")"
printf '%s' "$SHAPE_RESULT" | jq -e --arg bad "$NON_SAMPLED_ID" '
  .verification.outcome == "failed" and
  (.verification.detail.problems
    | any(.id == $bad and .reason == "embedding_non_numeric"))
  and .payment == null
' >/dev/null || fail "malformed non-sampled vector was not rejected: $SHAPE_RESULT"

echo "[4/5] start a real sandbox worker for the requeued task"
start_worker "correct-sandbox-worker" "correct-host" "$WORKER_LOG" \
    JACGRID_SANDBOX=1 \
    JACGRID_SEATBELT=0 \
    WORKER_JOB_TYPES=embedding \
    JACGRID_IDLE_LIMIT=30 >/dev/null

FINAL_STATUS=""
for _ in $(seq 1 240); do
    FINAL_STATUS="$(post get_job "$(jq -cn --arg id "$JOB_ID" '{job_id:$id}')")"
    state="$(printf '%s' "$FINAL_STATUS" | jq -r '.status // empty')"
    [ "$state" = "complete" ] && break
    [ "$state" = "failed" ] && fail "sandbox retry failed: $FINAL_STATUS"
    sleep 0.5
done
[ "${state:-}" = "complete" ] || fail "sandbox retry did not complete: $FINAL_STATUS"

echo "[5/5] prove matching runtime, genuine comparison, and payment"
FINAL_AUDIT="$(post audit_job "$(jq -cn --arg id "$JOB_ID" '{job_id:$id}')")"
printf '%s' "$FINAL_AUDIT" | jq -e --arg runtime "$EXPECTED_EMBEDDING_RUNTIME" '
  .tasks[0].payment.amount == 0.1 and
  ([.tasks[0].attempts[] | select(.status == "complete")] | length) == 1 and
  ([.tasks[0].attempts[]
    | select(.status == "complete")
    | .sandbox.runtime == $runtime and
      .verification.outcome == "passed" and
      .verification.detail.recompute == true and
      .verification.detail.recomputed_compared > 0 and
      .verification.detail.original_runtime == $runtime and
      .verification.detail.recompute_runtime == $runtime] | all)
' >/dev/null || fail "correct sandbox result lacked matching recompute/payment proof: $FINAL_AUDIT"
printf '%s' "$FINAL_AUDIT" | jq -e '
  [.tasks[0].attempts[]
   | select(.status == "complete")
   | .verification.detail
   | .tolerance == 0.001 and .cosine_threshold == 0.999] | all
' >/dev/null || fail "correct sandbox result lacked matching recompute/payment proof: $FINAL_AUDIT"

echo "PASS: tampered 384-d vector rejected with no payment"
echo "PASS: sandbox result recomputed with runtime=$EXPECTED_EMBEDDING_RUNTIME and paid 0.1 TESTUSD"
