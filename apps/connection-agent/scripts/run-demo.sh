#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--mock" ]]; then
  echo "Usage: $0 --mock" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd "${script_dir}/.." && pwd)"

cd "${app_dir}"
jac run src/main.jac
