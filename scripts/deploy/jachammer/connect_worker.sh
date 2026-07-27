#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: connect_worker.sh [--allow-http] --url URL --name NAME

Verifies a JacHammer coordinator and starts a local worker connected to it.
Public JacHammer URLs must use HTTPS. --allow-http is for local testing only.
EOF
}

ALLOW_HTTP=0
URL=""
WORKER_NAME=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --allow-http)
            ALLOW_HTTP=1
            shift
            ;;
        --url)
            [ "$#" -ge 2 ] || { echo "ERROR: --url requires a URL." >&2; exit 2; }
            URL="$2"
            shift 2
            ;;
        --name)
            [ "$#" -ge 2 ] || { echo "ERROR: --name requires a worker name." >&2; exit 2; }
            WORKER_NAME="$2"
            shift 2
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
done

if [ -z "$URL" ] || [ -z "$WORKER_NAME" ]; then
    echo "ERROR: both --url and --name are required." >&2
    usage >&2
    exit 2
fi

SECRET="${JACGRID_KEY:-}"
if [ -z "$SECRET" ] || [ "$SECRET" = "jacgrid-dev-key" ]; then
    echo "ERROR: JACGRID_KEY must be set to a non-development shared key." >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SMOKE_ARGS=()
if [ "$ALLOW_HTTP" -eq 1 ]; then
    SMOKE_ARGS+=(--allow-http)
fi
"$SCRIPT_DIR/smoke_coordinator.sh" "${SMOKE_ARGS[@]}" "$URL"

URL="${URL%/}"
export JACGRID_COORDINATOR="$URL"
export JACGRID_KEY="$SECRET"
exec "$REPO_ROOT/scripts/demo/start_worker.sh" --coordinator "$URL" --name "$WORKER_NAME"
