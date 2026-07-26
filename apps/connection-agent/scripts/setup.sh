#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd "${script_dir}/.." && pwd)"
repo_dir="$(cd "${app_dir}/../.." && pwd)"

if ! command -v jac >/dev/null 2>&1; then
  echo "Jac is required. Install a compatible Jac 0.34.x release, then rerun this command." >&2
  exit 1
fi
echo "Using $(jac --version)"
echo "Repository: ${repo_dir}"

if [[ ! -f "${app_dir}/.env" ]]; then
  echo "No apps/connection-agent/.env found. The mock foundation uses safe built-in defaults."
fi

jac check "${app_dir}/src" "${repo_dir}/workloads/connection-embedding/src" --nowarn
echo "Connection Agent foundation is ready."
