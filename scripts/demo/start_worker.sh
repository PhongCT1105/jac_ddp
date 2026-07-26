#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: start_worker.sh [--coordinator URL] [--name NAME] [URL] [NAME]

The coordinator URL is required, either as an argument or in
JACGRID_COORDINATOR. The worker name defaults to WORKER_NAME, then hostname.

Optional environment:
  JACGRID_KEY          Shared secret (default: jacgrid-dev-key)
  WORKER_JOB_TYPES     Comma-separated job types (worker default applies)
  JACGRID_SANDBOX      1 uses the allowlisted sandbox (demo default); set 0
                       explicitly to use the unisolated local stub runner
  JACGRID_SEATBELT     1 adds macOS network/write Seatbelt restrictions to
                       sandbox subprocesses (default: 0)
  JACGRID_TASK_DELAY   Simulated seconds per task (passed through unchanged)
EOF
}

COORDINATOR="${JACGRID_COORDINATOR:-}"
WORKER="${WORKER_NAME:-}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --coordinator)
            [ "$#" -ge 2 ] || { echo "ERROR: --coordinator requires a URL." >&2; exit 2; }
            COORDINATOR="$2"
            shift 2
            ;;
        --name)
            [ "$#" -ge 2 ] || { echo "ERROR: --name requires a value." >&2; exit 2; }
            WORKER="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            if [ -z "$COORDINATOR" ]; then
                COORDINATOR="$1"
            elif [ -z "$WORKER" ]; then
                WORKER="$1"
            else
                echo "ERROR: too many positional arguments." >&2
                usage >&2
                exit 2
            fi
            shift
            ;;
    esac
done

if [ -z "$COORDINATOR" ]; then
    echo "ERROR: coordinator URL is required." >&2
    echo "Set JACGRID_COORDINATOR to the export printed by Mac 1, or pass --coordinator URL." >&2
    exit 2
fi
case "$COORDINATOR" in
    http://*|https://*) ;;
    *)
        echo "ERROR: coordinator URL must start with http:// or https:// (got '$COORDINATOR')." >&2
        exit 2
        ;;
esac
COORDINATOR="${COORDINATOR%/}"

if [ -z "$WORKER" ]; then
    WORKER="$(hostname -s 2>/dev/null || hostname)"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKER_DIR="$REPO_ROOT/platform/worker"
VENV_ACTIVATE="$REPO_ROOT/.venv/bin/activate"
SECRET="${JACGRID_KEY:-jacgrid-dev-key}"
SANDBOX="${JACGRID_SANDBOX:-1}"
SEATBELT="${JACGRID_SEATBELT:-0}"

case "$SANDBOX" in
    0|1) ;;
    *)
        echo "ERROR: JACGRID_SANDBOX must be 0 or 1 (got '$SANDBOX')." >&2
        exit 2
        ;;
esac
case "$SEATBELT" in
    0|1) ;;
    *)
        echo "ERROR: JACGRID_SEATBELT must be 0 or 1 (got '$SEATBELT')." >&2
        exit 2
        ;;
esac

for tool in curl jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool '$tool' was not found." >&2
        exit 1
    fi
done
if [ ! -f "$VENV_ACTIVATE" ]; then
    echo "ERROR: repo virtualenv not found at $VENV_ACTIVATE" >&2
    exit 1
fi
if [ ! -f "$WORKER_DIR/jac.toml" ]; then
    echo "ERROR: worker config not found at $WORKER_DIR/jac.toml" >&2
    exit 1
fi

AUTH_BODY="$(jq -cn --arg secret "$SECRET" '{secret:$secret}')"
RAW_RESPONSE=""
if ! RAW_RESPONSE="$(curl --noproxy '*' -sS --connect-timeout 5 --max-time 15 \
    -X POST "$COORDINATOR/walker/network_status" \
    -H 'Content-Type: application/json' \
    -d "$AUTH_BODY")"; then
    echo "ERROR: cannot reach JacGrid coordinator at $COORDINATOR." >&2
    echo "Likely causes: wrong IP/port, macOS firewall, or the Macs are not on the same Wi-Fi." >&2
    exit 1
fi

PAYLOAD="$(printf '%s' "$RAW_RESPONSE" \
    | jq -ce '(.data.reports // .reports // [])[0] // empty' 2>/dev/null || true)"
if [ -z "$PAYLOAD" ]; then
    echo "ERROR: $COORDINATOR responded, but not with a JacGrid network_status payload." >&2
    echo "Check that the URL points to the coordinator port, not another local service." >&2
    exit 1
fi
if [ "$(printf '%s' "$PAYLOAD" | jq -r '.error // empty')" = "unauthorized" ]; then
    echo "ERROR: coordinator rejected JACGRID_KEY; all Macs must use the same shared secret." >&2
    exit 1
fi
if ! printf '%s' "$PAYLOAD" | jq -e '.server_time and (.error == null)' >/dev/null 2>&1; then
    echo "ERROR: coordinator readiness check failed: $PAYLOAD" >&2
    echo "Check the IP, firewall, shared key, and whether both Macs are on the same Wi-Fi." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$VENV_ACTIVATE"
if ! command -v jac >/dev/null 2>&1; then
    echo "ERROR: 'jac' is unavailable after activating $VENV_ACTIVATE" >&2
    exit 1
fi

export JACGRID_COORDINATOR="$COORDINATOR"
export JACGRID_KEY="$SECRET"
export WORKER_NAME="$WORKER"
export JACGRID_SANDBOX="$SANDBOX"
export JACGRID_SEATBELT="$SEATBELT"

echo "Coordinator reachable: $COORDINATOR"
echo "Starting worker '$WORKER' (job types: ${WORKER_JOB_TYPES:-noop,embedding})..."
if [ "$SANDBOX" = 1 ]; then
    echo "Execution: allowlisted sandbox (JACGRID_SANDBOX=1, JACGRID_SEATBELT=$SEATBELT)"
else
    echo "Execution: UNISOLATED local stub (explicit JACGRID_SANDBOX=0)"
fi
if [ -n "${JACGRID_TASK_DELAY:-}" ]; then
    echo "Demo task delay: ${JACGRID_TASK_DELAY}s"
fi

cd "$WORKER_DIR"
exec jac run main.jac
