#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JAC="$REPO_ROOT/.venv/bin/jac"
PYTHON="$REPO_ROOT/.venv/bin/python"
TEST_KEY="jachammer-root-test-key"

fail() {
    echo "[jachammer root test] FAIL: $*" >&2
    exit 1
}

[ -x "$JAC" ] || fail "missing Jac executable at $JAC"
[ -x "$PYTHON" ] || fail "missing Python executable at $PYTHON"
[ -f "$REPO_ROOT/jac.toml" ] || fail "missing root jac.toml"
[ -f "$REPO_ROOT/platform/__init__.py" ] \
    || fail "missing platform stdlib compatibility initializer"
[ -f "$REPO_ROOT/main.jac" ] || fail "missing root main.jac"
[ -L "$REPO_ROOT/main.jac" ] || fail "root main.jac must be a symlink"
[ -f "$REPO_ROOT/main.sv.jac" ] || fail "missing root main.sv.jac"
[ -L "$REPO_ROOT/main.sv.jac" ] || fail "root main.sv.jac must be a symlink"
[ -d "$REPO_ROOT/src" ] || fail "missing root src directory"
[ ! -L "$REPO_ROOT/src" ] || fail "root src must be a real directory"
[ -L "$REPO_ROOT/src/model.jac" ] \
    || fail "root src/model.jac must be a symlink"
[ "$(readlink "$REPO_ROOT/main.jac")" = "platform/coordinator/main.sv.jac" ] \
    || fail "root main.jac points to an unexpected target"
[ "$(readlink "$REPO_ROOT/main.sv.jac")" = "platform/coordinator/main.sv.jac" ] \
    || fail "root main.sv.jac points to an unexpected target"
[ "$(readlink "$REPO_ROOT/src/model.jac")" = "../platform/coordinator/src/model.jac" ] \
    || fail "root src/model.jac points to an unexpected target"

PYTHONPATH="$REPO_ROOT" "$PYTHON" -c \
    'import platform; assert callable(platform.system); assert platform.system()'

(
    cd "$REPO_ROOT"
    "$JAC" check main.jac
    JACGRID_KEY="$TEST_KEY" JACGRID_HOSTED=1 JACGRID_SELFTEST=1 \
        "$JAC" run main.jac
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
    JACGRID_HOSTED=1 JACGRID_KEY= "$JAC" run main.jac 2>&1
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
        "$JAC" run main.jac 2>&1
)"
DEFAULT_STATUS=$?
set -e
[ "$DEFAULT_STATUS" -ne 0 ] || fail "hosted mode accepted jacgrid-dev-key"
printf '%s' "$DEFAULT_OUTPUT" | grep -Fq \
    "JACGRID_HOSTED=1 requires a non-development JACGRID_KEY" \
    || fail "default-key failure did not explain the requirement"

echo "[jachammer root test] OK"
