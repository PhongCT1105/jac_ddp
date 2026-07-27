#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}/.."
# Prefer the pinned MiniLM runtime for the showable local journey. The workload
# reports and visibly labels its deterministic fallback if the model is absent.
export JACGRID_USE_ST="${JACGRID_USE_ST:-1}"
exec jac start
