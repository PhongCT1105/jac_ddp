#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: submit_demo_job.sh [--coordinator URL] [URL]

Submits the M2 twelve-task noop job. The coordinator URL is required, either
as an argument or in JACGRID_COORDINATOR.
EOF
}

COORDINATOR="${JACGRID_COORDINATOR:-}"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --coordinator)
            [ "$#" -ge 2 ] || { echo "ERROR: --coordinator requires a URL." >&2; exit 2; }
            COORDINATOR="$2"
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
            if [ -n "$COORDINATOR" ]; then
                echo "ERROR: coordinator URL was supplied more than once." >&2
                usage >&2
                exit 2
            fi
            COORDINATOR="$1"
            shift
            ;;
    esac
done

if [ -z "$COORDINATOR" ]; then
    echo "ERROR: coordinator URL is required." >&2
    echo "Use the JACGRID_COORDINATOR export printed by Mac 1." >&2
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

for tool in curl jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool '$tool' was not found." >&2
        exit 1
    fi
done

SECRET="${JACGRID_KEY:-jacgrid-dev-key}"
REQUEST_BODY="$(jq -cn --arg secret "$SECRET" '{
    secret: $secret,
    app_id: "m2-three-mac-demo",
    job_type: "noop",
    payload: {
        items: [
            {id: "m2-1", text: "alpha"},
            {id: "m2-2", text: "bravo"},
            {id: "m2-3", text: "charlie"},
            {id: "m2-4", text: "delta"},
            {id: "m2-5", text: "echo"},
            {id: "m2-6", text: "foxtrot"},
            {id: "m2-7", text: "golf"},
            {id: "m2-8", text: "hotel"},
            {id: "m2-9", text: "india"},
            {id: "m2-10", text: "juliet"},
            {id: "m2-11", text: "kilo"},
            {id: "m2-12", text: "lima"}
        ]
    },
    partitioning: {strategy: "chunk", chunk_size: 1},
    verification: {method: "recompute_sample", sample_rate: 1.0},
    budget: {max_total: 2.0, price_per_task: 0.1, currency: "TESTUSD"}
}')"

RAW_RESPONSE=""
if ! RAW_RESPONSE="$(curl --noproxy '*' -sS --connect-timeout 5 --max-time 30 \
    -X POST "$COORDINATOR/walker/create_job" \
    -H 'Content-Type: application/json' \
    -d "$REQUEST_BODY")"; then
    echo "ERROR: could not submit the demo job to $COORDINATOR." >&2
    echo "Check the coordinator IP/port, macOS firewall, and Wi-Fi connectivity." >&2
    exit 1
fi

PAYLOAD="$(printf '%s' "$RAW_RESPONSE" \
    | jq -ce '(.data.reports // .reports // [])[0] // empty' 2>/dev/null || true)"
if [ -z "$PAYLOAD" ]; then
    echo "ERROR: coordinator returned an unexpected response: $RAW_RESPONSE" >&2
    exit 1
fi
ERROR_KIND="$(printf '%s' "$PAYLOAD" | jq -r '.error // empty')"
if [ -n "$ERROR_KIND" ]; then
    echo "ERROR: coordinator rejected the job ($ERROR_KIND): $PAYLOAD" >&2
    exit 1
fi

JOB_ID="$(printf '%s' "$PAYLOAD" | jq -r '.job_id // empty')"
if [ -z "$JOB_ID" ]; then
    echo "ERROR: create_job returned no job_id: $PAYLOAD" >&2
    exit 1
fi

TASK_COUNT="$(printf '%s' "$PAYLOAD" | jq -r '.task_count // 0')"
echo "Submitted 12 noop items in chunks of 1: $TASK_COUNT tasks at 0.1 TESTUSD each (budget 2.0)."
printf 'job_id=%s\n' "$JOB_ID"
