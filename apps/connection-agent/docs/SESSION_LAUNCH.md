# Launching the parallel Codex sessions

## Team size

Run five concurrent sessions:

1. Primary repository: orchestration and core.
2. Data and Integrations worktree.
3. Intelligence and Workload worktree.
4. Product Experience worktree.
5. Evaluation and Quality worktree.

## Create the worktrees

After the foundation commit is merged to `main`, run from the repository root:

```bash
./apps/connection-agent/scripts/create-agent-worktrees.sh
```

By default this creates four sibling worktrees next to `jac_ddp`. Pass a different parent directory as the first argument if desired.

## Initial prompt for each implementation session

Use the corresponding objective packet and replace `<OBJECTIVE_FILE>`:

```text
You are one implementation session for Connection Agent in the shared jac_ddp repository.

Read completely:
- apps/connection-agent/docs/specs/INTERNAL_CONTRACT_V1.md
- docs/specs/CONNECTION_AGENT_JACGRID_BOUNDARIES.md
- apps/connection-agent/docs/objectives/<OBJECTIVE_FILE>
- the product documents linked by that objective

Implement the objective's numbered specs in order. Work only in its declared writable paths. Treat platform/, sandbox/, src/contracts/, and all other objective paths as read-only unless the orchestration agent gives an explicit handoff.

Before every handoff run ./apps/connection-agent/scripts/check.sh. Commit one tested numbered spec at a time. If a released contract must change, stop at the boundary and propose the smallest change to the orchestration agent; do not edit the contract yourself.
```

Objective files:

```text
01_DATA_AND_INTEGRATIONS.md
02_INTELLIGENCE_AND_WORKLOAD.md
03_PRODUCT_EXPERIENCE.md
04_EVALUATION_AND_QUALITY.md
```

## Orchestration rhythm

The primary session remains on `main`, follows `00_ORCHESTRATION_AND_CORE.md`, reviews each small objective commit, merges contracts and migrations before dependents, runs the integrated quality gate, and tells active sessions when to incorporate the new integration head.

Do not wait for an objective to finish entirely before integration. Merge a green numbered spec at a time so the product remains runnable.
