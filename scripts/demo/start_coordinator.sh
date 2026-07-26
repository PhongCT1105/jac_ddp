#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: start_coordinator.sh [--fresh]

Starts the JacGrid coordinator on JACGRID_PORT (default: 8000).
  --fresh   Delete platform/coordinator/.jac/data before starting.

Optional environment:
  JACGRID_LAN_IP    Valid local non-loopback IPv4 override. By default the
                    active physical/default-route interface is selected.
  JACGRID_PORT      Listener port (default: 8000)
  JACGRID_KEY       Shared secret (default: jacgrid-dev-key)
EOF
}

FRESH=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --fresh)
            FRESH=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
COORD_DIR="$REPO_ROOT/platform/coordinator"
VENV_ACTIVATE="$REPO_ROOT/.venv/bin/activate"
PORT="${JACGRID_PORT:-8000}"
SECRET="${JACGRID_KEY:-jacgrid-dev-key}"
COORD_PID=""
LISTENER_PID=""

case "$PORT" in
    ""|*[!0-9]*)
        echo "ERROR: JACGRID_PORT must be an integer between 1 and 65535 (got '$PORT')." >&2
        exit 2
        ;;
esac
if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "ERROR: JACGRID_PORT must be between 1 and 65535 (got '$PORT')." >&2
    exit 2
fi

for tool in curl jq lsof; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool '$tool' was not found." >&2
        exit 1
    fi
done
if [ ! -f "$VENV_ACTIVATE" ]; then
    echo "ERROR: repo virtualenv not found at $VENV_ACTIVATE" >&2
    exit 1
fi
if [ ! -f "$COORD_DIR/jac.toml" ]; then
    echo "ERROR: coordinator config not found at $COORD_DIR/jac.toml" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$VENV_ACTIVATE"
if ! command -v jac >/dev/null 2>&1; then
    echo "ERROR: 'jac' is unavailable after activating $VENV_ACTIVATE" >&2
    exit 1
fi

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "ERROR: port $PORT is already in use." >&2
    echo "jac start silently selects another port in this situation, so refusing to start." >&2
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2 || true
    exit 1
fi

LAN_IP="$(jacgrid_choose_lan_ip)" || exit $?

AUTH_BODY="$(jq -cn --arg secret "$SECRET" '{secret:$secret}')"

network_status_payload() {
    local base_url="$1"
    curl --noproxy '*' -sS --connect-timeout 2 --max-time 5 \
        -X POST "$base_url/walker/network_status" \
        -H 'Content-Type: application/json' \
        -d "$AUTH_BODY" \
        | jq -ce '(.data.reports // .reports // [])[0] // empty'
}

cleanup() {
    local pid
    trap - EXIT INT TERM
    for pid in "$LISTENER_PID" "$COORD_PID"; do
        [ -n "$pid" ] || continue
        kill "$pid" 2>/dev/null || true
    done
    for pid in "$LISTENER_PID" "$COORD_PID"; do
        [ -n "$pid" ] || continue
        wait "$pid" 2>/dev/null || true
    done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$FRESH" -eq 1 ]; then
    DATA_DIR="$COORD_DIR/.jac/data"
    echo "Fresh start: removing $DATA_DIR"
    rm -rf "$DATA_DIR"
fi

echo "Starting JacGrid coordinator on port $PORT..."
(cd "$COORD_DIR" && exec jac start main.sv.jac --no_client --port "$PORT") &
COORD_PID=$!

READY_PAYLOAD=""
for _ in $(seq 1 120); do
    if ! kill -0 "$COORD_PID" 2>/dev/null; then
        echo "ERROR: coordinator process exited before becoming ready." >&2
        exit 1
    fi
    READY_PAYLOAD="$(network_status_payload "http://127.0.0.1:$PORT" 2>/dev/null || true)"
    if [ -n "$READY_PAYLOAD" ] \
        && printf '%s' "$READY_PAYLOAD" | jq -e '.server_time and (.error == null)' >/dev/null 2>&1; then
        break
    fi
    READY_PAYLOAD=""
    sleep 1
done
if [ -z "$READY_PAYLOAD" ]; then
    echo "ERROR: coordinator did not become ready on port $PORT within 120 seconds." >&2
    exit 1
fi

# Record the listener only after proving it belongs to the jac launcher. If a
# foreign process wins a bind race, leave LISTENER_PID empty so cleanup never
# signals it; cleanup still stops our own COORD_PID.
if ! LISTENER_PID="$(jacgrid_listener_pid_for_owner "$PORT" "$COORD_PID")"; then
    echo "ERROR: refusing to manage the unowned listener on port $PORT." >&2
    LISTENER_PID=""
    exit 1
fi

LAN_URL="http://$LAN_IP:$PORT"
LAN_PAYLOAD="$(network_status_payload "$LAN_URL" 2>/dev/null || true)"
if [ -z "$LAN_PAYLOAD" ] \
    || ! printf '%s' "$LAN_PAYLOAD" | jq -e '.server_time and (.error == null)' >/dev/null 2>&1; then
    echo "ERROR: coordinator is ready on localhost but not reachable through $LAN_URL." >&2
    echo "The service may not be listening on all interfaces, or macOS firewall may be blocking it." >&2
    exit 1
fi

printf '\n'
printf '%s\n' '================================================================================'
printf '  export JACGRID_COORDINATOR=%s\n' "$LAN_URL"
printf '%s\n' '================================================================================'
printf 'Coordinator ready (launcher pid %s). Press Ctrl-C to stop it.\n\n' "$$"

set +e
wait "$COORD_PID"
STATUS=$?
set -e
exit "$STATUS"
