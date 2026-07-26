# Stage 1 handoff: Credible matching intelligence

**Execution directive:** Implement this handoff end to end, following the
mandatory workflow linked below.

**Worktree:** `/Users/sebastian/dev/jac_ddp-intelligence-workload`

**Branch:** `agent/intelligence-workload`

**Push destination:** `origin/agent/intelligence-workload`

## Goal

Turn the foundation's deterministic matching components into a credible,
data-driven Stage 1 suggestion pipeline. It must use the complete synthetic
candidate pool, return grounded reciprocal evidence, and create different
immutable cards for each viewer without depending on a live LLM or external
model download.

This is one Stage 1 specification using narrow parts of I1, I4, I6, and I7. Do
not implement I1–I8 in sequence.

## Required reading

- [`../../AGENT_WORKFLOW.md`](../../AGENT_WORKFLOW.md)
- [`../../STAGE_1_PRODUCT.md`](../../STAGE_1_PRODUCT.md)
- [`../../specs/INTERNAL_CONTRACT_V1.md`](../../specs/INTERNAL_CONTRACT_V1.md)
- [`../../specs/STAGE_1_OPERATION_CONTRACT.md`](../../specs/STAGE_1_OPERATION_CONTRACT.md)
- [`../../specs/WALKING_SKELETON.md`](../../specs/WALKING_SKELETON.md)
- [`../../objectives/02_INTELLIGENCE_AND_WORKLOAD.md`](../../objectives/02_INTELLIGENCE_AND_WORKLOAD.md) as backlog context only
- `docs/specs/CONNECTION_AGENT_JACGRID_BOUNDARIES.md`
- `workloads/connection-embedding/README.md`

## Writable paths

```text
apps/connection-agent/src/intelligence/
apps/connection-agent/tests/intelligence/
workloads/connection-embedding/
apps/connection-agent/docs/specs/stage-1/intelligence-workload/
```

Everything else is read-only, including `src/contracts/`, `src/core/`,
`src/adapters/`, `web/`, `evals/`, `platform/`, and `sandbox/`.

## Required deliverable

Implement a deterministic or recorded intelligence pipeline that:

1. Accepts approved synthetic profile revisions and an optional explicit
   current-request snapshot.
2. Uses the existing immutable workload `0.1.0` through the released compute
   result contract; do not silently rewrite that workload version. Add a new
   version only if the reviewed spec proves it is necessary and affordable.
3. Ranks across the complete eligible vector set after compute chunks are
   recombined, with deterministic self/block/ineligible exclusions and tie
   behavior.
4. Produces a canonical reciprocal pair assessment whose evidence is directly
   supported by both synthetic profiles or explicit requests.
5. Produces distinct Alice-viewing-Bob and Bob-viewing-Alice card snapshots with
   mobile-safe headlines/reasons and exact source revision IDs.
6. Produces credible results for more than the single Alice/Bob path so the
   implementation is not a hardcoded pair lookup.
7. Returns stable failures for no candidate, missing projections, and
   unsupported or ungrounded evidence. Compute result shape/completeness remains
   the adapter's responsibility.

Recorded AI output is allowed when schema-valid, versioned, traceable to the
exact fixture revisions, and available offline. Unit tests never call a live
LLM. Prefer a small Jac-native design over introducing a framework.

## Explicit deferrals

- Live `by llm()` profile conversation.
- Production embedding model and model artifact download.
- Supabase pgvector.
- Full Jac graph topology/walker if it does not materially help this slice.
- Open-ended explanations and invited coordination.
- Broad qualitative model evaluation.

## Required review panel

- Current-Jac and Jac AI-pattern expert.
- Application-contract, privacy, and JacGrid-boundary reviewer.
- Retrieval, grounding, and evaluation specialist.

Create:

```text
apps/connection-agent/docs/specs/stage-1/intelligence-workload/IMPLEMENTATION_SPEC.md
apps/connection-agent/docs/specs/stage-1/intelligence-workload/HANDOFF_REPORT.md
```

## Acceptance

- At least 30 eligible fixture profiles participate in whole-pool retrieval
  after workload chunks are combined.
- Alice selects Bob for understandable profile-grounded reasons; reversing the
  direction keeps one pair identity but returns a distinct card.
- At least one contrasting fixture request produces a different plausible
  result or evidence path.
- Self, blocked, ineligible, and missing-vector fixtures cannot leak into a
  suggestion.
- Every card reason is traceable to allowed input text; deliberately unsupported
  evidence fails a grounding check.
- Results are deterministic offline and record source revision/workload
  identity.
- Existing foundation tests and `./apps/connection-agent/scripts/check.sh` pass.

## Completion and handback

Complete both reviews, commit the implementation/spec/report, push with
`git push -u origin HEAD`, and stop. Do not merge to `main`. Return the final SHA
and complete workflow evidence.
