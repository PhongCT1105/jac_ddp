#!/usr/bin/env bash
# Convenience driver for the sandbox test suite.
#
# `jac test <file>` treats the target file as a standalone entry module and
# does NOT add the repo root to sys.path the way `jac run` does, so the
# suite's no-dot absolute import (`import from sandbox.runner.harness { ... }`)
# needs the repo root on PYTHONPATH explicitly. This script is the
# documented way to run the suite; see sandbox/README.md "Running the
# tests" for the plain `jac test` command this wraps.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
JAC_BIN="$REPO_ROOT/.venv/bin/jac"

if [ ! -x "$JAC_BIN" ]; then
  echo "error: $JAC_BIN not found — is the venv set up? (see jac-baseline.md)" >&2
  exit 1
fi

cd "$REPO_ROOT"
PYTHONPATH="$REPO_ROOT:${PYTHONPATH:-}" "$JAC_BIN" test sandbox/tests/run_tests.jac -v
