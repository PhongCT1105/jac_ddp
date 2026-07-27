#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd "${script_dir}/.." && pwd)"

cd "${app_dir}"

jac fmt evals tests/evals --check
jac check evals tests/evals --nowarn
jac test -d tests/evals
jac run evals/stage1_reciprocal_private.jac
