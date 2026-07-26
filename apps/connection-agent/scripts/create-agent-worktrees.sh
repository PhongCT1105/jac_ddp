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
baseline_sha="$(git rev-parse HEAD)"
repo_common_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd)"

sync_worktree() {
  local branch_name="$1"
  local target_dir="$2"
  local actual_branch
  local target_common_dir

  if ! git -C "${target_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not a Git worktree: ${target_dir}" >&2
    exit 1
  fi
  target_common_dir="$(cd "$(git -C "${target_dir}" rev-parse --git-common-dir)" && pwd)"
  if [[ "${target_common_dir}" != "${repo_common_dir}" ]]; then
    echo "Path belongs to a different repository: ${target_dir}" >&2
    exit 1
  fi
  actual_branch="$(git -C "${target_dir}" branch --show-current)"
  if [[ "${actual_branch}" != "${branch_name}" ]]; then
    echo "Expected ${target_dir} on ${branch_name}; found ${actual_branch:-detached HEAD}." >&2
    exit 1
  fi
  if [[ -n "$(git -C "${target_dir}" status --porcelain)" ]]; then
    echo "Worktree is not clean; preserve or finish its work before launch: ${target_dir}" >&2
    exit 1
  fi
  if [[ "$(git -C "${target_dir}" rev-parse HEAD)" != "${baseline_sha}" ]]; then
    if ! git merge-base --is-ancestor "$(git -C "${target_dir}" rev-parse HEAD)" "${baseline_sha}"; then
      echo "${branch_name} contains commits outside the launch baseline; not synchronizing automatically." >&2
      exit 1
    fi
    git -C "${target_dir}" merge --ff-only "${baseline_sha}"
  fi
  if [[ "$(git -C "${target_dir}" rev-parse HEAD)" != "${baseline_sha}" ]]; then
    echo "Failed to synchronize ${target_dir} to ${baseline_sha}." >&2
    exit 1
  fi
  echo "Ready: ${target_dir} (${branch_name} @ ${baseline_sha})"
}

create_worktree() {
  local branch_name="$1"
  local suffix="$2"
  local target_dir="${parent_dir}/${repo_name}-${suffix}"

  if [[ -e "${target_dir}" ]]; then
    sync_worktree "${branch_name}" "${target_dir}"
    return
  fi

  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    git worktree add "${target_dir}" "${branch_name}"
  else
    git worktree add -b "${branch_name}" "${target_dir}" "${baseline_sha}"
  fi
  sync_worktree "${branch_name}" "${target_dir}"
}

create_worktree "agent/data-integrations" "data-integrations"
create_worktree "agent/intelligence-workload" "intelligence-workload"
create_worktree "agent/product-experience" "product-experience"
create_worktree "agent/evaluation-quality" "evaluation-quality"
create_worktree "agent/orchestration-core" "orchestration-core"

echo "Open one Codex session in each agent worktree above."
echo "Keep the primary repository on main, clean, and reserved for consolidation."
echo "All five worktrees are clean and synchronized to launch baseline ${baseline_sha}."
