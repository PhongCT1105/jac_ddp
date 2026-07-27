#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: smoke_coordinator.sh [--allow-http] URL

Checks that a JacHammer coordinator is reachable and accepts JACGRID_KEY.
Public JacHammer URLs must use HTTPS. --allow-http is for local testing only.
EOF
}

ALLOW_HTTP=0
URL=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --allow-http)
            ALLOW_HTTP=1
            shift
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
            if [ -n "$URL" ]; then
                echo "ERROR: URL was supplied more than once." >&2
                usage >&2
                exit 2
            fi
            URL="$1"
            shift
            ;;
    esac
done

if [ -z "$URL" ]; then
    echo "ERROR: coordinator URL is required." >&2
    usage >&2
    exit 2
fi
URL="${URL%/}"

case "$URL" in
    https://*) ;;
    http://*)
        if [ "$ALLOW_HTTP" -ne 1 ]; then
            echo "ERROR: public JacHammer URL must use https:// (pass --allow-http only for local testing)." >&2
            exit 2
        fi
        ;;
    *)
        echo "ERROR: coordinator URL must start with https://." >&2
        exit 2
        ;;
esac

SECRET="${JACGRID_KEY:-}"
if [ -z "$SECRET" ] || [ "$SECRET" = "jacgrid-dev-key" ]; then
    echo "ERROR: JACGRID_KEY must be set to a non-development shared key." >&2
    exit 2
fi

for tool in curl jq; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool '$tool' was not found." >&2
        exit 1
    }
done

REQUEST_BODY="$(jq -cn --arg secret "$SECRET" '{secret: $secret}')"
RAW_RESPONSE=""
if ! RAW_RESPONSE="$(curl --noproxy '*' -sS --connect-timeout 5 --max-time 20 \
    -X POST "$URL/walker/network_status" \
    -H 'Content-Type: application/json' \
    -d "$REQUEST_BODY")"; then
    echo "ERROR: cannot reach JacGrid coordinator at $URL." >&2
    exit 1
fi

PAYLOAD="$(printf '%s' "$RAW_RESPONSE" \
    | jq -ce '(.data.reports // .reports // [])[0] // empty' 2>/dev/null || true)"
if [ -z "$PAYLOAD" ]; then
    echo "ERROR: coordinator returned an unexpected network_status response." >&2
    exit 1
fi
if [ "$(printf '%s' "$PAYLOAD" | jq -r '.error // empty')" = "unauthorized" ]; then
    echo "ERROR: coordinator rejected JACGRID_KEY." >&2
    exit 1
fi
if ! printf '%s' "$PAYLOAD" | jq -e '
    .server_time != null and (.workers | type == "array") and (.jobs | type == "array")
' >/dev/null 2>&1; then
    echo "ERROR: coordinator readiness check failed." >&2
    exit 1
fi

WORKER_COUNT="$(printf '%s' "$PAYLOAD" | jq -r '.workers | length')"
JOB_COUNT="$(printf '%s' "$PAYLOAD" | jq -r '.jobs | length')"
printf 'JacGrid coordinator ready: %s\nworkers=%s jobs=%s\n' "$URL" "$WORKER_COUNT" "$JOB_COUNT"
