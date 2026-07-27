#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JAC="$REPO_ROOT/.venv/bin/jac"
TEST_KEY="jachammer-root-test-key"

fail() {
    echo "[jachammer root test] FAIL: $*" >&2
    exit 1
}

[ -x "$JAC" ] || fail "missing Jac executable at $JAC"
[ -f "$REPO_ROOT/jac.toml" ] || fail "missing root jac.toml"
[ -f "$REPO_ROOT/main.sv.jac" ] || fail "missing root main.sv.jac"
[ -L "$REPO_ROOT/main.sv.jac" ] || fail "root main.sv.jac must be a symlink"
[ -L "$REPO_ROOT/src" ] || fail "root src must be a symlink"
[ "$(readlink "$REPO_ROOT/main.sv.jac")" = "platform/coordinator/main.sv.jac" ] \
    || fail "root main.sv.jac points to an unexpected target"
[ "$(readlink "$REPO_ROOT/src")" = "platform/coordinator/src" ] \
    || fail "root src points to an unexpected target"

(
    cd "$REPO_ROOT"
    "$JAC" check main.sv.jac
    JACGRID_KEY="$TEST_KEY" JACGRID_HOSTED=1 JACGRID_SELFTEST=1 \
        "$JAC" run main.sv.jac
)

(
    cd "$REPO_ROOT/platform/coordinator"
    "$JAC" check main.sv.jac
    JACGRID_KEY="$TEST_KEY" JACGRID_HOSTED=1 JACGRID_SELFTEST=1 \
        "$JAC" run main.sv.jac
)

set +e
HOSTED_OUTPUT="$(
    cd "$REPO_ROOT"
    JACGRID_HOSTED=1 JACGRID_KEY= "$JAC" run main.sv.jac 2>&1
)"
HOSTED_STATUS=$?
set -e
[ "$HOSTED_STATUS" -ne 0 ] || fail "hosted mode accepted an empty key"
printf '%s' "$HOSTED_OUTPUT" | grep -Fq \
    "JACGRID_HOSTED=1 requires a non-development JACGRID_KEY" \
    || fail "hosted failure did not explain the key requirement"

set +e
DEFAULT_OUTPUT="$(
    cd "$REPO_ROOT"
    JACGRID_HOSTED=1 JACGRID_KEY=jacgrid-dev-key \
        "$JAC" run main.sv.jac 2>&1
)"
DEFAULT_STATUS=$?
set -e
[ "$DEFAULT_STATUS" -ne 0 ] || fail "hosted mode accepted jacgrid-dev-key"
printf '%s' "$DEFAULT_OUTPUT" | grep -Fq \
    "JACGRID_HOSTED=1 requires a non-development JACGRID_KEY" \
    || fail "default-key failure did not explain the requirement"

echo "[jachammer root test] OK"
