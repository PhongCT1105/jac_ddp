#!/usr/bin/env bash
# Real LAN proof: coordinator via this Mac's non-loopback IPv4, demo launcher
# sandbox defaults/override, two sandbox workers, distributed embedding, and
# the connection-agent's LiveJacGrid product flow.
set -euo pipefail

TEST_NAME="e2e_lan_sandbox_embedding"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
COORD_DIR="$REPO_ROOT/platform/coordinator"
APP_DIR="$REPO_ROOT/apps/connection-agent"
JAC="$REPO_ROOT/.venv/bin/jac"
DEMO_LIB="$REPO_ROOT/scripts/demo/lib.sh"
LOGDIR="$HERE/logs"
SECRET="${JACGRID_KEY:-lan-e2e-nondefault-key}"
EXPECTED_EMBEDDING_RUNTIME="${EXPECTED_EMBEDDING_RUNTIME:-connection-embedding:1.0.0}"

# The launcher and this test must use one implementation of the LAN-selection
# contract. Missing this library is an intentional RED until the launcher is
# refactored onto the tested helper.
# shellcheck source=../../scripts/demo/lib.sh
source "$DEMO_LIB"
# shellcheck source=lan_test_lib.sh
source "$HERE/lan_test_lib.sh"

mkdir -p "$LOGDIR"
COORD_LOG="$LOGDIR/${TEST_NAME}_coordinator.log"
APP_LOG="$LOGDIR/${TEST_NAME}_app.log"
WORKER_DEFAULT_LOG="$LOGDIR/${TEST_NAME}_worker_default.log"
WORKER_STUB_LOG="$LOGDIR/${TEST_NAME}_worker_stub.log"
WORKER_A_LOG="$LOGDIR/${TEST_NAME}_worker_a.log"
WORKER_B_LOG="$LOGDIR/${TEST_NAME}_worker_b.log"
for log in "$COORD_LOG" "$APP_LOG" "$WORKER_DEFAULT_LOG" \
    "$WORKER_STUB_LOG" "$WORKER_A_LOG" "$WORKER_B_LOG"; do
    : >"$log"
done

LAN_IP="$(jacgrid_choose_lan_ip)"
if JACGRID_LAN_IP=999.1.2.3 jacgrid_choose_lan_ip >/dev/null 2>&1; then
    fail "malformed JACGRID_LAN_IP override was accepted"
fi
if JACGRID_LAN_IP=203.0.113.42 jacgrid_choose_lan_ip >/dev/null 2>&1; then
    fail "an IPv4 address not assigned to this Mac was accepted"
fi
PORT="${E2E_PORT:-$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')}"
APP_PORT="${E2E_APP_PORT:-$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')}"
BASE="http://$LAN_IP:$PORT"
APP_BASE="http://$LAN_IP:$APP_PORT"

COORD_PID=""
COORD_LISTENER_PID=""
APP_PID=""
APP_LISTENER_PID=""
OWNED_PIDS=()
STATE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/jacgrid-lan-e2e.XXXXXX")"
COORD_DATA="$COORD_DIR/.jac/data"
APP_DATA="$APP_DIR/.jac/data"
COORD_STATE_MODE="untouched"
APP_STATE_MODE="untouched"

fail() {
    echo "FAIL: $*" >&2
    for log in "$COORD_LOG" "$APP_LOG" "$WORKER_DEFAULT_LOG" \
        "$WORKER_STUB_LOG" "$WORKER_A_LOG" "$WORKER_B_LOG"; do
        [ -f "$log" ] || continue
        echo "--- $(basename "$log") tail ---" >&2
        tail -25 "$log" >&2
    done
    exit 1
}

stop_pid() {
    local pid="${1:-}"
    [ -n "$pid" ] || return 0
    # A dead child PID may be recycled before cleanup. Never signal a process
    # that is no longer part of this test's process tree.
    jacgrid_pid_is_descendant "$pid" "$$" || return 0
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        for _ in $(seq 1 20); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi
    wait "$pid" 2>/dev/null || true
}

cleanup() {
    trap - EXIT INT TERM
    local i restore_failed=0
    for ((i=${#OWNED_PIDS[@]} - 1; i >= 0; i--)); do
        stop_pid "${OWNED_PIDS[$i]}"
    done
    OWNED_PIDS=()
    jacgrid_restore_test_state \
        "$COORD_DATA" "$STATE_TMP/coordinator-data" "$COORD_STATE_MODE" \
        || {
            echo "WARNING: coordinator test-state restore failed; backup retained at $STATE_TMP/coordinator-data" >&2
            restore_failed=1
        }
    jacgrid_restore_test_state \
        "$APP_DATA" "$STATE_TMP/app-data" "$APP_STATE_MODE" \
        || {
            echo "WARNING: app test-state restore failed; backup retained at $STATE_TMP/app-data" >&2
            restore_failed=1
        }
    [ "$restore_failed" -ne 0 ] || rm -rf "$STATE_TMP"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for tool in curl jq lsof python3; do
    command -v "$tool" >/dev/null 2>&1 || fail "required tool '$tool' is missing"
done
[ -x "$JAC" ] || fail "Jac binary missing at $JAC"

if lsof "$COORD_DATA/anchor_store.db" >/dev/null 2>&1; then
    fail "coordinator graph is in use; stop that coordinator before this isolated E2E"
fi
if lsof "$APP_DATA/anchor_store.db" >/dev/null 2>&1; then
    fail "connection-agent graph is in use; stop that app before this isolated E2E"
fi
COORD_STATE_MODE="$(jacgrid_backup_test_state \
    "$COORD_DATA" "$STATE_TMP/coordinator-data")" \
    || fail "could not safely back up coordinator graph state"
APP_STATE_MODE="$(jacgrid_backup_test_state \
    "$APP_DATA" "$STATE_TMP/app-data")" \
    || fail "could not safely back up connection-agent graph state"

report_of() {
    jq -ce '(.data.reports // .reports // [])[0] // empty'
}

post_to() {
    local base="$1" walker="$2" body="$3"
    curl --noproxy '*' -sS --connect-timeout 3 --max-time 30 \
        -X POST "$base/walker/$walker" \
        -H 'Content-Type: application/json' \
        -d "$body" | report_of
}

coord_post() {
    local walker="$1" body="$2"
    post_to "$BASE" "$walker" \
        "$(jq -cn --arg secret "$SECRET" --argjson body "$body" '$body + {secret:$secret}')"
}

wait_for_worker_runtime() {
    local worker_name="$1" runtime="$2" found=""
    for _ in $(seq 1 80); do
        found="$(coord_post network_status '{}' 2>/dev/null \
            | jq -r --arg name "$worker_name" \
                '.workers[]? | select(.name == $name) | .capabilities.runtime' \
            | tail -n 1 || true)"
        [ "$found" = "$runtime" ] && return 0
        sleep 0.25
    done
    fail "worker '$worker_name' advertised runtime '$found', expected '$runtime'"
}

echo "== JacGrid LAN + sandbox embedding + LiveJacGrid E2E =="
echo "LAN IP:          $LAN_IP"
echo "coordinator URL: $BASE"
echo "app URL:         $APP_BASE"

echo "[1/9] start a normal jac coordinator and prove non-loopback readiness"
(
    exec env JACGRID_KEY="$SECRET" JACGRID_PORT="$PORT" JACGRID_LAN_IP="$LAN_IP" \
        "$REPO_ROOT/scripts/demo/start_coordinator.sh"
) >"$COORD_LOG" 2>&1 &
COORD_PID=$!
disown "$COORD_PID" 2>/dev/null || true
jacgrid_own_pid "$COORD_PID"
for _ in $(seq 1 160); do
    if ! kill -0 "$COORD_PID" 2>/dev/null; then
        fail "coordinator exited during startup"
    fi
    ready="$(coord_post network_status '{}' 2>/dev/null || true)"
    if [ -n "$ready" ] && printf '%s' "$ready" | jq -e '.server_time' >/dev/null 2>&1; then
        break
    fi
    ready=""
    sleep 0.5
done
[ -n "${ready:-}" ] || fail "coordinator never became ready through $BASE"
COORD_LISTENER_PID="$(lsof -nP -tiTCP:"$PORT" -sTCP:LISTEN | head -n 1)"
[ -n "$COORD_LISTENER_PID" ] || fail "could not resolve coordinator listener PID"
jacgrid_pid_is_descendant "$COORD_LISTENER_PID" "$COORD_PID" \
    || fail "coordinator listener PID $COORD_LISTENER_PID is not owned by launcher $COORD_PID"
jacgrid_own_pid "$COORD_LISTENER_PID"
for _ in $(seq 1 40); do
    grep -Fq "export JACGRID_COORDINATOR=$BASE" "$COORD_LOG" && break
    kill -0 "$COORD_PID" 2>/dev/null || fail "coordinator launcher exited before printing LAN URL"
    sleep 0.25
done
grep -Fq "export JACGRID_COORDINATOR=$BASE" "$COORD_LOG" \
    || fail "coordinator launcher did not print its proven LAN URL"
echo "      ready via $BASE (launcher=$COORD_PID listener=$COORD_LISTENER_PID)"

echo "[2/9] prove demo worker defaults to sandbox and explicit 0 opts out"
(
    exec env -u JACGRID_SANDBOX \
        JACGRID_COORDINATOR="$BASE" JACGRID_KEY="$SECRET" \
        WORKER_JOB_TYPES="__probe__" JACGRID_POLL=0.2 \
        "$REPO_ROOT/scripts/demo/start_worker.sh" --name lan-default-sandbox
) >"$WORKER_DEFAULT_LOG" 2>&1 &
default_pid=$!
disown "$default_pid" 2>/dev/null || true
jacgrid_own_pid "$default_pid"
wait_for_worker_runtime lan-default-sandbox sandbox-harness:v1
stop_pid "$default_pid"
jacgrid_forget_owned_pid "$default_pid"

(
    exec env JACGRID_SANDBOX=0 \
        JACGRID_COORDINATOR="$BASE" JACGRID_KEY="$SECRET" \
        WORKER_JOB_TYPES="__probe__" JACGRID_POLL=0.2 \
        "$REPO_ROOT/scripts/demo/start_worker.sh" --name lan-explicit-stub
) >"$WORKER_STUB_LOG" 2>&1 &
stub_pid=$!
disown "$stub_pid" 2>/dev/null || true
jacgrid_own_pid "$stub_pid"
wait_for_worker_runtime lan-explicit-stub stub-runner:v0
stop_pid "$stub_pid"
jacgrid_forget_owned_pid "$stub_pid"
echo "      default=sandbox-harness:v1; JACGRID_SANDBOX=0=stub-runner:v0"

echo "[3/9] start two sandbox workers against the LAN URL"
for suffix in a b; do
    log_var="$WORKER_A_LOG"
    [ "$suffix" = b ] && log_var="$WORKER_B_LOG"
    (
        exec env JACGRID_SANDBOX=1 JACGRID_SEATBELT=0 \
            JACGRID_COORDINATOR="$BASE" JACGRID_KEY="$SECRET" \
            JACGRID_TASK_DELAY=1 JACGRID_HEARTBEAT=1 JACGRID_POLL=0.2 \
            "$REPO_ROOT/scripts/demo/start_worker.sh" --name "lan-sandbox-$suffix"
    ) >"$log_var" 2>&1 &
    worker_pid=$!
    disown "$worker_pid" 2>/dev/null || true
    jacgrid_own_pid "$worker_pid"
done
wait_for_worker_runtime lan-sandbox-a sandbox-harness:v1
wait_for_worker_runtime lan-sandbox-b sandbox-harness:v1
echo "      both workers registered with sandbox capability"

echo "[4/9] submit a real four-task embedding job"
items="$(jq -cn '[
    {id:"lan-1",text:"distributed systems and graph compute"},
    {id:"lan-2",text:"machine learning infrastructure"},
    {id:"lan-3",text:"product design and developer tools"},
    {id:"lan-4",text:"network orchestration and reliability"}
]')"
job="$(coord_post create_job "$(jq -cn --argjson items "$items" '{
    app_id:"lan-sandbox-e2e",
    job_type:"embedding",
    payload:{model:"all-MiniLM-L6-v2",items:$items},
    partitioning:{strategy:"chunk",chunk_size:1},
    verification:{method:"recompute_sample",sample_rate:1.0},
    budget:{max_total:1.0,price_per_task:0.1,currency:"TESTUSD"}
}')")"
JOB_ID="$(printf '%s' "$job" | jq -r '.job_id // empty')"
[ -n "$JOB_ID" ] || fail "create_job returned no job_id: $job"
echo "      job_id=$JOB_ID"

echo "[5/9] wait for verified and paid completion"
status=""
for _ in $(seq 1 300); do
    status="$(coord_post get_job "$(jq -cn --arg id "$JOB_ID" '{job_id:$id}')")"
    job_status="$(printf '%s' "$status" | jq -r '.status // empty')"
    [ "$job_status" = complete ] && break
    [ "$job_status" = failed ] && fail "embedding job failed: $status"
    sleep 0.5
done
[ "${job_status:-}" = complete ] || fail "embedding job timed out: $status"

result="$(coord_post get_job_result "$(jq -cn --arg id "$JOB_ID" '{job_id:$id}')")"
printf '%s' "$result" | jq -e '
    (.results | length) == 4 and
    ([.results[].embedding | length] | all(. == 384)) and
    .receipt.tasks == 4 and
    .receipt.verified == 4 and
    .receipt.total_paid == 0.4
' >/dev/null || fail "result/receipt assertion failed: $result"

workers="$(printf '%s' "$result" \
    | jq -r '[.receipt.payments[].worker] | unique | sort | join(",")')"
worker_count="$(printf '%s' "$result" \
    | jq '[.receipt.payments[].worker] | unique | length')"
[ "$worker_count" -ge 2 ] || fail "tasks were not distributed: $result"
echo "      distributed across $worker_count workers: $workers"

echo "[6/9] assert the coordinator recorded the allowlisted sandbox runtime"
audit="$(coord_post audit_job "$(jq -cn --arg id "$JOB_ID" '{job_id:$id}')")"
printf '%s' "$audit" | jq -e --arg runtime "$EXPECTED_EMBEDDING_RUNTIME" '
    [.tasks[].attempts[]
      | select(.status == "complete")
      | {
          sandbox_runtime: .sandbox.runtime,
          outcome: .verification.outcome,
          detail: .verification.detail
        }] as $attempts
    | ($attempts | length) == 4
      and ($attempts | all(
        .sandbox_runtime == $runtime
        and .outcome == "passed"
        and .detail.recompute == true
        and .detail.recomputed_compared > 0
        and .detail.original_runtime == $runtime
        and .detail.recompute_runtime == $runtime
      ))
' >/dev/null || fail "audit lacked expected runtime/recompute proof ($EXPECTED_EMBEDDING_RUNTIME): $audit"
echo "      runtime=$EXPECTED_EMBEDDING_RUNTIME with genuine recompute comparisons in coordinator audit"

echo "[7/9] start connection-agent in live mode with the same non-default key"
if lsof -nP -iTCP:"$APP_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    fail "app port $APP_PORT became occupied before connection-agent startup"
fi
(
    cd "$APP_DIR"
    exec env JACGRID_MODE=live JACGRID_COORDINATOR="$BASE" JACGRID_KEY="$SECRET" \
        "$JAC" start main.sv.jac --no_client --port "$APP_PORT"
) >"$APP_LOG" 2>&1 &
APP_PID=$!
disown "$APP_PID" 2>/dev/null || true
jacgrid_own_pid "$APP_PID"
for _ in $(seq 1 120); do
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        fail "connection-agent exited during startup"
    fi
    if curl --noproxy '*' -sS --connect-timeout 2 --max-time 3 \
        "$APP_BASE/healthz" >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done
curl --noproxy '*' -sS --connect-timeout 2 --max-time 3 \
    "$APP_BASE/healthz" >/dev/null || fail "connection-agent not ready through $APP_BASE"
APP_LISTENER_PID="$(lsof -nP -tiTCP:"$APP_PORT" -sTCP:LISTEN | head -n 1)"
[ -n "$APP_LISTENER_PID" ] || fail "could not resolve connection-agent listener PID"
jacgrid_pid_is_descendant "$APP_LISTENER_PID" "$APP_PID" \
    || fail "app listener PID $APP_LISTENER_PID is not owned by app launcher $APP_PID"
jacgrid_own_pid "$APP_LISTENER_PID"

app_call() {
    post_to "$APP_BASE" "$1" "$2"
}

seed="$(app_call seed_profiles '{}')"
printf '%s' "$seed" | jq -e '(.seeded // 0) > 0 or (.already_seeded // 0) > 0' \
    >/dev/null || fail "connection-agent seed failed: $seed"
profile="$(app_call create_profile '{
    "name":"LAN Demo Operator",
    "bio":"Distributed systems engineer building private compute networks.",
    "tags":{"skills":["python","distributed-systems"],"interests":["devtools"],"looking_for":["ml"]}
}')"
PROFILE_ID="$(printf '%s' "$profile" | jq -r '.id // empty')"
[ -n "$PROFILE_ID" ] || fail "connection-agent create_profile failed: $profile"

find="$(app_call find_matches "$(jq -cn --arg id "$PROFILE_ID" '{profile_id:$id}')")"
APP_JOB_ID="$(printf '%s' "$find" | jq -r '.job_id // empty')"
[ -n "$APP_JOB_ID" ] || fail "LiveJacGrid did not create a job with the non-default JACGRID_KEY: $find"
echo "      profile=$PROFILE_ID live_job=$APP_JOB_ID"

echo "[8/9] poll the app flow and fetch paid matches"
app_status=""
for _ in $(seq 1 360); do
    app_status="$(app_call match_status "$(jq -cn --arg id "$PROFILE_ID" '{profile_id:$id}')")"
    state="$(printf '%s' "$app_status" | jq -r '.status // empty')"
    [ "$state" = complete ] && break
    [ "$state" = failed ] && fail "LiveJacGrid job failed: $app_status"
    sleep 0.5
done
[ "${state:-}" = complete ] || fail "LiveJacGrid job timed out: $app_status"
matches="$(app_call get_matches "$(jq -cn --arg id "$PROFILE_ID" '{profile_id:$id,top_n:3}')")"
printf '%s' "$matches" | jq -e '
    (.matches | length) == 3 and
    (.receipt.verified > 0) and
    (.receipt.total_paid > 0)
' >/dev/null || fail "LiveJacGrid matches/receipt failed: $matches"
app_workers="$(printf '%s' "$matches" \
    | jq -r '[.receipt.payments[].worker] | unique | sort | join(",")')"
echo "      LiveJacGrid complete: 3 matches, paid workers=$app_workers"

echo "[9/9] final checks"
echo "PASS: LAN=$LAN_IP coordinator_port=$PORT app_port=$APP_PORT"
echo "PASS: distributed_workers=$workers"
echo "PASS: LiveJacGrid_job=$APP_JOB_ID paid_workers=$app_workers"
