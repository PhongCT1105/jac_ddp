#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd "${script_dir}/.." && pwd)"
repo_dir="$(cd "${app_dir}/../.." && pwd)"
workload_dir="${repo_dir}/workloads/connection-embedding"

command -v jac >/dev/null 2>&1 || {
  echo "Jac is required to run Connection Agent checks." >&2
  exit 1
}
command -v rg >/dev/null 2>&1 || {
  echo "ripgrep (rg) is required for boundary checks." >&2
  exit 1
}

echo "Checking workload"
(
  cd "${workload_dir}"
  jac fmt src tests --check
  jac check src tests --nowarn
  jac test -d tests
)

echo "Checking application"
(
  cd "${app_dir}"
  jac fmt src tests --check
  jac check src tests --nowarn
  jac test -d tests
)

if rg -n '(^|[[:space:]])(from|import)[[:space:]].*(platform|sandbox)' "${app_dir}/src" "${workload_dir}/src"; then
  echo "Application or workload source imports platform/sandbox implementation code." >&2
  exit 1
fi

echo "Connection Agent foundation checks passed."
