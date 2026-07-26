#!/usr/bin/env bash
# Shared helpers for the JacGrid cross-component integration tests.
#
# Sourced by tests/integration/*.sh. Provides: repo/project paths, the `post`
# JSON-RPC-ish helper over POST /walker/<name>, coordinator start + readiness
# wait, worker launch, and process cleanup.
#
# Contract note (jaclang 0.16.7 / jac-scale): endpoint errors are IN-BAND —
# a bad secret returns HTTP 200 with an `unauthorized` report. Always inspect
# the report, never the HTTP status.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COORD_DIR="$REPO_ROOT/platform/coordinator"
WORKER_DIR="$REPO_ROOT/platform/worker"
LOGDIR="$REPO_ROOT/tests/integration/logs"
SECRET="${JACGRID_KEY:-jacgrid-dev-key}"
JAC="${JAC:-$REPO_ROOT/.venv/bin/jac}"

COORD_PID=""
WORKER_PIDS=()

require_tools() {
    command -v jq >/dev/null || { echo "FAIL: jq not found (brew install jq)" >&2; exit 1; }
    [ -x "$JAC" ] || { echo "FAIL: jac not found at $JAC (expected the repo .venv)" >&2; exit 1; }
    [ -f "$COORD_DIR/jac.toml" ] || { echo "FAIL: $COORD_DIR/jac.toml missing" >&2; exit 1; }
    [ -f "$WORKER_DIR/jac.toml" ] || { echo "FAIL: $WORKER_DIR/jac.toml missing" >&2; exit 1; }
    mkdir -p "$LOGDIR"
}

cleanup() {
    trap - EXIT INT TERM
    for p in "${WORKER_PIDS[@]:-}" "$COORD_PID"; do
        [ -n "${p:-}" ] && kill "$p" 2>/dev/null
    done
    sleep 1
    for p in "${WORKER_PIDS[@]:-}" "$COORD_PID"; do
        [ -n "${p:-}" ] && kill -9 "$p" 2>/dev/null
    done
    # Belt and braces: jac start forks children that outlive the parent pid.
    [ -n "${PORT:-}" ] && pkill -f "main.sv.jac --no_client --port ${PORT}" 2>/dev/null
    wait 2>/dev/null
    return 0
}

fail() {
    echo "FAIL: $*" >&2
    echo "--- coordinator log tail ---" >&2
    tail -25 "$COORD_LOG" 2>/dev/null >&2
    for wl in "$LOGDIR"/${TEST_NAME:-x}_worker*.log; do
        [ -f "$wl" ] || continue
        echo "--- $(basename "$wl") tail ---" >&2
        tail -15 "$wl" >&2
    done
    exit 1
}

# post <walker> <json-body-without-secret>
# Unwraps the 0.16 response envelope: reports live at .data.reports.
post() {
    local walker="$1" body="$2"
    curl -s -m 20 -X POST "$BASE/walker/$walker" \
        -H 'Content-Type: application/json' \
        -d "$(jq -cn --arg s "$SECRET" --argjson b "$body" '$b + {secret:$s}')" \
    | jq -c '(.data.reports // .reports // [])[0] // empty'
}

# start_coordinator — fresh graph, jac start from the coordinator project dir.
start_coordinator() {
    if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
        echo "FAIL: port $PORT already in use (jac start would silently pick another)" >&2
        exit 1
    fi
    rm -rf "$COORD_DIR/.jac/data"
    ( cd "$COORD_DIR" && exec "$JAC" start main.sv.jac --no_client --port "$PORT" ) \
        >"$COORD_LOG" 2>&1 &
    COORD_PID=$!
    disown %% 2>/dev/null   # keep the shell from printing "Terminated" at cleanup

    local ready=""
    for _ in $(seq 1 120); do
        kill -0 "$COORD_PID" 2>/dev/null || fail "coordinator died during startup"
        r=$(post network_status '{}' 2>/dev/null)
        if [ -n "$r" ] && echo "$r" | jq -e '.server_time' >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 1
    done
    [ -n "$ready" ] || fail "coordinator did not become ready on $BASE within 120s"
}

# start_sweeper <logfile> [extra env assignments...]
# The out-of-process failure detector (spec §2.4). The coordinator cannot run
# this internally — see the note in platform/coordinator/main.sv.jac.
start_sweeper() {
    local logfile="$1"; shift
    ( cd "$WORKER_DIR" && \
      env JACGRID_COORDINATOR="$BASE" \
          JACGRID_KEY="$SECRET" \
          JACGRID_MODE=sweeper \
          WORKER_NAME="sweeper" \
          "$@" \
          "$JAC" run main.jac ) >"$logfile" 2>&1 &
    WORKER_PIDS+=("$!")
    echo "$!"
}

# start_worker <name> <hostname> <logfile> [extra env assignments...]
start_worker() {
    local name="$1" host="$2" logfile="$3"; shift 3
    ( cd "$WORKER_DIR" && \
      exec env JACGRID_COORDINATOR="$BASE" \
          JACGRID_KEY="$SECRET" \
          WORKER_NAME="$name" \
          WORKER_HOSTNAME="$host" \
          JACGRID_HEARTBEAT=2 \
          JACGRID_POLL=0.5 \
          JACGRID_EXIT_WHEN_IDLE=1 \
          JACGRID_IDLE_LIMIT=10 \
          JACGRID_MAX_LOOPS=400 \
          "$@" \
          "$JAC" run main.jac ) >"$logfile" 2>&1 &
    WORKER_PIDS+=("$!")
    echo "$!"
}
