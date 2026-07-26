#!/usr/bin/env bash
# Exercise the worker's two execution paths without a coordinator. The enabled
# path reaches sandbox_run_bridge(), so this catches both the opt-in flag and
# the repo-root import used by the nested worker project.
set -euo pipefail

WORKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$WORKER_DIR/../.." && pwd)"
JAC_BIN="$REPO_ROOT/.venv/bin/jac"

if [ ! -x "$JAC_BIN" ]; then
  echo "error: Jac executable not found at $JAC_BIN" >&2
  exit 1
fi

run_selftest() {
  local label="$1"
  local expected_result_runtime="$2"
  local expected_capability_runtime="$3"
  shift 3
  local output

  output="$(cd "$WORKER_DIR" && env "$@" "$JAC_BIN" run main.jac 2>&1)"
  printf '%s\n' "$output"

  if ! grep -Fq "[worker selftest] OK dim=384 runtime=$expected_result_runtime capability_runtime=$expected_capability_runtime" <<<"$output"; then
    echo "error: $label self-test did not report result runtime $expected_result_runtime and capability runtime $expected_capability_runtime" >&2
    exit 1
  fi
}

run_selftest "stub" "stub-runner:v0" "stub-runner:v0" JACGRID_WORKER_SELFTEST=1
run_selftest "sandbox" "connection-embedding:1.0.0" "sandbox-harness:v1" JACGRID_SANDBOX=1 JACGRID_WORKER_SELFTEST=1

echo "[worker selftest modes] OK"
