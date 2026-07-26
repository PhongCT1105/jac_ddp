#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/../../.." && pwd)"
parent_dir="${1:-$(dirname "${repo_dir}")}"
repo_name="$(basename "${repo_dir}")"

cd "${repo_dir}"

if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "Run this command from the merged main branch." >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "The main worktree must be clean before creating agent worktrees." >&2
  exit 1
fi

git fetch --prune origin
git pull --ff-only origin main

create_worktree() {
  local branch_name="$1"
  local suffix="$2"
  local target_dir="${parent_dir}/${repo_name}-${suffix}"

  if [[ -e "${target_dir}" ]]; then
    echo "Already exists: ${target_dir}"
    return
  fi

  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    git worktree add "${target_dir}" "${branch_name}"
  else
    git worktree add -b "${branch_name}" "${target_dir}" main
  fi
  echo "Created ${target_dir} on ${branch_name}"
}

create_worktree "agent/data-integrations" "data-integrations"
create_worktree "agent/intelligence-workload" "intelligence-workload"
create_worktree "agent/product-experience" "product-experience"
create_worktree "agent/evaluation-quality" "evaluation-quality"

echo "Open one Codex session in each path above. Keep the primary repository on main for orchestration."
