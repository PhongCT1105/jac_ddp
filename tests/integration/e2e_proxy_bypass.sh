#!/usr/bin/env bash
# Focused proof that worker and LiveJacGrid coordinator traffic ignores ambient
# proxy variables. Starts no workloads and performs no expensive embedding.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
COORD_DIR="$REPO_ROOT/platform/coordinator"
APP_DIR="$REPO_ROOT/apps/connection-agent"
JAC="$REPO_ROOT/.venv/bin/jac"
SECRET="proxy-e2e-key"
LOGDIR="$HERE/logs"
mkdir -p "$LOGDIR"
COORD_LOG="$LOGDIR/e2e_proxy_bypass_coordinator.log"
WORKER_LOG="$LOGDIR/e2e_proxy_bypass_worker.log"
: >"$COORD_LOG"
: >"$WORKER_LOG"

# shellcheck source=../../scripts/demo/lib.sh
source "$REPO_ROOT/scripts/demo/lib.sh"
# shellcheck source=lan_test_lib.sh
source "$HERE/lan_test_lib.sh"

LAN_IP="$(jacgrid_choose_lan_ip)"
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')"
BASE="http://$LAN_IP:$PORT"
STATE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/jacgrid-proxy-e2e.XXXXXX")"
COORD_DATA="$COORD_DIR/.jac/data"
COORD_STATE_MODE="untouched"
OWNED_PIDS=()

fail() {
    echo "FAIL: $*" >&2
    tail -25 "$COORD_LOG" >&2 || true
    tail -25 "$WORKER_LOG" >&2 || true
    exit 1
}

stop_pid() {
    local pid="${1:-}"
    [ -n "$pid" ] || return 0
    jacgrid_pid_is_descendant "$pid" "$$" || return 0
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

cleanup() {
    trap - EXIT INT TERM
    local i
    for ((i=${#OWNED_PIDS[@]} - 1; i >= 0; i--)); do
        stop_pid "${OWNED_PIDS[$i]}"
    done
    jacgrid_restore_test_state \
        "$COORD_DATA" "$STATE_TMP/coordinator-data" "$COORD_STATE_MODE" \
        || {
            echo "WARNING: graph restore failed; backup retained at $STATE_TMP" >&2
            return
        }
    rm -rf "$STATE_TMP"
}
trap cleanup EXIT

if lsof "$COORD_DATA/anchor_store.db" >/dev/null 2>&1; then
    fail "coordinator graph is in use; stop that coordinator before this isolated E2E"
fi
COORD_STATE_MODE="$(jacgrid_backup_test_state \
    "$COORD_DATA" "$STATE_TMP/coordinator-data")" \
    || fail "could not safely back up coordinator graph"

(
    exec env JACGRID_KEY="$SECRET" JACGRID_PORT="$PORT" JACGRID_LAN_IP="$LAN_IP" \
        "$REPO_ROOT/scripts/demo/start_coordinator.sh"
) >"$COORD_LOG" 2>&1 &
COORD_PID=$!
disown "$COORD_PID" 2>/dev/null || true
jacgrid_own_pid "$COORD_PID"

auth_body="$(jq -cn --arg secret "$SECRET" '{secret:$secret}')"
for _ in $(seq 1 120); do
    ready="$(curl --noproxy '*' -sS --connect-timeout 1 --max-time 3 \
        -X POST "$BASE/walker/network_status" \
        -H 'Content-Type: application/json' -d "$auth_body" 2>/dev/null \
        | jq -ce '(.data.reports // .reports // [])[0] // empty' \
        2>/dev/null || true)"
    [ -n "$ready" ] && break
    sleep 0.25
done
[ -n "${ready:-}" ] || fail "coordinator not ready through $BASE"
listener="$(lsof -nP -tiTCP:"$PORT" -sTCP:LISTEN | head -n 1)"
[ -n "$listener" ] || fail "coordinator listener missing"
jacgrid_pid_is_descendant "$listener" "$COORD_PID" \
    || fail "coordinator listener is not owned by launcher"
jacgrid_own_pid "$listener"

PROXY_URL="http://127.0.0.1:9"
echo "[1/2] worker registration bypasses bogus ambient proxies"
(
    exec env -u NO_PROXY -u no_proxy \
        HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL" ALL_PROXY="$PROXY_URL" \
        http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$PROXY_URL" \
        JACGRID_COORDINATOR="$BASE" JACGRID_KEY="$SECRET" \
        JACGRID_SANDBOX=0 JACGRID_MAX_LOOPS=1 JACGRID_POLL=0.1 \
        "$REPO_ROOT/scripts/demo/start_worker.sh" --name proxy-bypass-worker
) >"$WORKER_LOG" 2>&1 &
WORKER_PID=$!
disown "$WORKER_PID" 2>/dev/null || true
jacgrid_own_pid "$WORKER_PID"
for _ in $(seq 1 60); do
    kill -0 "$WORKER_PID" 2>/dev/null || break
    sleep 0.25
done
if kill -0 "$WORKER_PID" 2>/dev/null; then
    fail "worker stayed in its retry loop; coordinator traffic leaked into bogus proxy"
fi
wait "$WORKER_PID" || fail "worker proxy probe exited non-zero"
jacgrid_forget_owned_pid "$WORKER_PID"
grep -q 'registered as' "$WORKER_LOG" || fail "worker never registered"

echo "[2/2] LiveJacGrid submit/poll bypass bogus ambient proxies"
app_output="$(
    cd "$APP_DIR"
    env -u NO_PROXY -u no_proxy \
        HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL" ALL_PROXY="$PROXY_URL" \
        http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$PROXY_URL" \
        JACGRID_COORDINATOR="$BASE" JACGRID_KEY="$SECRET" \
        "$JAC" run tests/live_proxy_probe.jac
)" || fail "LiveJacGrid leaked coordinator traffic into bogus proxy"
printf '%s\n' "$app_output" | grep -q 'LIVE_PROXY_BYPASS_OK' \
    || fail "LiveJacGrid proxy probe did not report success"

echo "PASS: worker and LiveJacGrid ignored bogus proxy variables for $BASE"
