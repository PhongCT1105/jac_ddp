# Launching the Stage 1 Codex sessions

**Status:** Operator instructions

Stage 1 uses five implementation worktrees and keeps the primary `main`
checkout untouched for later consolidation. Each session implements one
launch-ready handoff, performs its own spec and implementation reviews, pushes
its assigned branch, and stops.

## 1. Worktrees, branches, and handoffs

| Session | Open Codex in | Assigned branch | Implement this document |
|---|---|---|---|
| Core | `/Users/sebastian/dev/jac_ddp-orchestration-core` | `agent/orchestration-core` | `/Users/sebastian/dev/jac_ddp-orchestration-core/apps/connection-agent/docs/stage-1/handoffs/00_CORE.md` |
| Data and Integrations | `/Users/sebastian/dev/jac_ddp-data-integrations` | `agent/data-integrations` | `/Users/sebastian/dev/jac_ddp-data-integrations/apps/connection-agent/docs/stage-1/handoffs/01_DATA_INTEGRATIONS.md` |
| Intelligence and Workload | `/Users/sebastian/dev/jac_ddp-intelligence-workload` | `agent/intelligence-workload` | `/Users/sebastian/dev/jac_ddp-intelligence-workload/apps/connection-agent/docs/stage-1/handoffs/02_INTELLIGENCE_WORKLOAD.md` |
| Product Experience | `/Users/sebastian/dev/jac_ddp-product-experience` | `agent/product-experience` | `/Users/sebastian/dev/jac_ddp-product-experience/apps/connection-agent/docs/stage-1/handoffs/03_PRODUCT_EXPERIENCE.md` |
| Evaluation and Quality | `/Users/sebastian/dev/jac_ddp-evaluation-quality` | `agent/evaluation-quality` | `/Users/sebastian/dev/jac_ddp-evaluation-quality/apps/connection-agent/docs/stage-1/handoffs/04_EVALUATION_QUALITY.md` |

The primary checkout `/Users/sebastian/dev/jac_ddp` stays on `main`. Do not open
an implementation session there.

## 2. Create or verify the worktrees

After the launch documents are merged to a clean `main`, run from the primary
checkout:

```bash
./apps/connection-agent/scripts/create-agent-worktrees.sh
```

The script creates missing worktrees and verifies every existing worktree belongs
to this repository, uses its assigned branch, is clean, and can be safely
fast-forwarded to the exact `main` launch baseline. It aborts rather than
overwriting divergent or unfinished work. Do not launch sessions unless all five
paths print `Ready` at the same SHA.

Before opening the implementation sessions, verify the global Jac MCP once:

```bash
codex mcp list
jac mcp --inspect
```

`jac` must appear enabled. Codex clients normally discover MCP servers when a
session starts, so open or restart the five implementation sessions only after
this check.

## 3. Exact prompt for each session

Open Codex in the worktree shown in the table and paste this prompt, replacing
`<ABSOLUTE_HANDOFF_PATH>` with the document from the final column:

```text
Implement the Stage 1 handoff in <ABSOLUTE_HANDOFF_PATH> end to end.

The handoff is authoritative for your goal, writable paths, exact worktree and
branch, review panel, acceptance criteria, checks, commit/push destination, and
stopping point. Follow its required AGENT_WORKFLOW.md completely: draft the one
lane implementation spec, have the spec reviewed by the required panel including
a current-Jac expert using the installed Jac MCP, improve it, implement it in
Jac wherever Jac can reasonably implement it, have the final implementation
reviewed, resolve blocking findings, run all checks, commit and push only your
assigned branch, and return the required handoff evidence. Choose the other
reviewers appropriate to your lane, such as backend/security, AI/evaluation,
UX/accessibility, or testing/privacy experts.

Do not implement the lane's Stage 2/3 backlog, modify another lane, modify
Phong's platform/ or Luke/Santhos's sandbox/, merge to main, or begin unreviewed
code.
```

No additional branch instructions are needed; they are inside each handoff.

## 4. What runs in parallel

All five sessions may start together from the same baseline. They work against
released contracts and fakes rather than editing one another's branches. A
session that discovers a shared contract need records the smallest proposal in
its handoff report; it does not cross the ownership boundary.

Each session produces one coherent Stage 1 deliverable. The older numbered
C/D/I/U/E briefs remain backlog and must not be treated as the current launch
queue.

## 5. When the sessions finish

For each session, collect:

- pushed branch and final SHA;
- implementation spec and review records;
- check/test evidence;
- demo command;
- contract requests and integration notes.

Then return to the orchestration session in `/Users/sebastian/dev/jac_ddp` and
say that the Stage 1 branches are ready for consolidation. Orchestration reviews
and integrates the branches; implementation sessions never merge themselves.
