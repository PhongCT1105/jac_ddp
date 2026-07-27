#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JAC="$REPO_ROOT/.venv/bin/jac"
PORT="${JACGRID_TEST_PORT:-18110}"
URL="http://127.0.0.1:$PORT"
KEY="jachammer-tools-test-key"
SERVER_LOG="$(mktemp)"
SERVER_PID=""

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f "$SERVER_LOG"
}
trap cleanup EXIT

(
    cd "$REPO_ROOT"
    JACGRID_KEY="$KEY" JACGRID_HOSTED=1 \
        "$JAC" start main.sv.jac --no_client --port "$PORT"
) >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 60); do
    curl --noproxy '*' -fsS "$URL/healthz" >/dev/null 2>&1 && break
    kill -0 "$SERVER_PID" 2>/dev/null || { cat "$SERVER_LOG" >&2; exit 1; }
    sleep 0.5
done
curl --noproxy '*' -fsS "$URL/healthz" >/dev/null

JACGRID_KEY="$KEY" \
    "$REPO_ROOT/scripts/deploy/jachammer/smoke_coordinator.sh" \
    --allow-http "$URL" \
    | grep -F "JacGrid coordinator ready: $URL"

set +e
WRONG_OUTPUT="$(
    JACGRID_KEY=wrong \
        "$REPO_ROOT/scripts/deploy/jachammer/smoke_coordinator.sh" \
        --allow-http "$URL" 2>&1
)"
WRONG_STATUS=$?
set -e
[ "$WRONG_STATUS" -ne 0 ]
printf '%s' "$WRONG_OUTPUT" | grep -Fq "coordinator rejected JACGRID_KEY"

set +e
HTTP_OUTPUT="$(
    JACGRID_KEY="$KEY" \
        "$REPO_ROOT/scripts/deploy/jachammer/smoke_coordinator.sh" \
        "$URL" 2>&1
)"
HTTP_STATUS=$?
set -e
[ "$HTTP_STATUS" -ne 0 ]
printf '%s' "$HTTP_OUTPUT" | grep -Fq "public JacHammer URL must use https://"

"$REPO_ROOT/scripts/deploy/jachammer/connect_worker.sh" --help \
    | grep -Fq "connect_worker.sh"

echo "[jachammer tools test] OK"
