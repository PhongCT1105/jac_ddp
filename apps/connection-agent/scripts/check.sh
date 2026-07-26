#!/usr/bin/env bash
set -euo pipefail

require_stage_1_hooks=false
if [[ "${1:-}" == "--stage-1-integrated" ]]; then
  require_stage_1_hooks=true
  shift
fi
if [[ "$#" -ne 0 ]]; then
  echo "Usage: $0 [--stage-1-integrated]" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd "${script_dir}/.." && pwd)"
repo_dir="$(cd "${app_dir}/../.." && pwd)"
workload_dir="${repo_dir}/workloads/connection-embedding"
exception_file="${script_dir}/jac-native-exceptions.txt"

command -v jac >/dev/null 2>&1 || {
  echo "Jac is required to run Connection Agent checks." >&2
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

run_lane_check() {
  local lane_name="$1"
  local check_path="$2"
  if [[ -f "${check_path}" ]]; then
    echo "Checking ${lane_name}"
    bash "${check_path}"
  elif [[ "${require_stage_1_hooks}" == true ]]; then
    echo "Missing required Stage 1 check hook: ${check_path}" >&2
    exit 1
  fi
}

run_lane_check "web experience" "${app_dir}/web/check.sh"
run_lane_check "evaluation scenarios" "${app_dir}/evals/check.sh"

echo "Checking Jac-native source policy"
foreign_source_hits=""
while IFS= read -r source_path; do
  relative_path="${source_path#"${repo_dir}/"}"
  if [[ ! -f "${exception_file}" ]] || ! grep -Fqx "${relative_path}" "${exception_file}"; then
    foreign_source_hits+="${relative_path}"$'\n'
  fi
done < <(
  find \
    "${app_dir}/src" \
    "${app_dir}/tests" \
    "${app_dir}/web" \
    "${app_dir}/evals" \
    "${workload_dir}/src" \
    "${workload_dir}/tests" \
    -type f \
    \( -name '*.py' -o -name '*.pyi' -o -name '*.js' -o -name '*.jsx' \
       -o -name '*.mjs' -o -name '*.cjs' -o -name '*.ts' -o -name '*.tsx' \
       -o -name '*.mts' -o -name '*.cts' \) \
    ! -path '*/.jac/*' \
    ! -path '*/node_modules/*' \
    ! -path '*/dist/*' \
    ! -path '*/build/*' \
    -print
)

if [[ -n "${foreign_source_hits}" ]]; then
  printf '%s' "${foreign_source_hits}"
  echo "Authored non-Jac source requires the documented exception review and an exact-path allowlist entry." >&2
  exit 1
fi

boundary_pattern='(^|[[:space:]])(from|import)[[:space:]].*(platform|sandbox)'
if command -v rg >/dev/null 2>&1; then
  boundary_hits="$(rg -n "${boundary_pattern}" "${app_dir}/src" "${app_dir}/web" "${app_dir}/evals" "${workload_dir}/src" || true)"
else
  boundary_hits="$(grep -R -n -E "${boundary_pattern}" "${app_dir}/src" "${app_dir}/web" "${app_dir}/evals" "${workload_dir}/src" || true)"
fi

if [[ -n "${boundary_hits}" ]]; then
  echo "${boundary_hits}"
  echo "Application or workload source imports platform/sandbox implementation code." >&2
  exit 1
fi

echo "Connection Agent checks passed."
