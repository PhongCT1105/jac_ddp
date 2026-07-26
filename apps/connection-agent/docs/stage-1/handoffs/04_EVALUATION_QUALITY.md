# Stage 1 handoff: Reproducible demo evaluation

**Execution directive:** Implement this handoff end to end, following the
mandatory workflow linked below.

**Worktree:** `/Users/sebastian/dev/jac_ddp-evaluation-quality`

**Branch:** `agent/evaluation-quality`

**Push destination:** `origin/agent/evaluation-quality`

## Goal

Turn the shared Stage 1 journey into one reproducible, isolated scenario with a
concise result. It should tell orchestration whether the product loop is correct
without building the full evaluation laboratory.

This is one Stage 1 specification using narrow portions of E1, E2, and E4. Do
not implement E1–E7 in sequence.

## Required reading

- [`../../AGENT_WORKFLOW.md`](../../AGENT_WORKFLOW.md)
- [`../../STAGE_1_PRODUCT.md`](../../STAGE_1_PRODUCT.md)
- [`../../specs/INTERNAL_CONTRACT_V1.md`](../../specs/INTERNAL_CONTRACT_V1.md)
- [`../../specs/STAGE_1_OPERATION_CONTRACT.md`](../../specs/STAGE_1_OPERATION_CONTRACT.md)
- [`../../specs/WALKING_SKELETON.md`](../../specs/WALKING_SKELETON.md)
- [`../../objectives/04_EVALUATION_AND_QUALITY.md`](../../objectives/04_EVALUATION_AND_QUALITY.md) as backlog context only

## Writable paths

```text
apps/connection-agent/evals/
apps/connection-agent/tests/evals/
apps/connection-agent/docs/specs/stage-1/evaluation-quality/
```

Everything else is read-only. File integration defects in the handoff report;
do not reproduce or patch product logic inside the evaluator.

## Required deliverable

Create one synthetic, uniquely identified Stage 1 scenario that:

1. Starts and resets an isolated local demo state.
2. Selects Alice and requests a suggestion from the complete fixture pool.
3. Confirms Alice receives Bob and her open remains private.
4. Selects Bob, confirms his card is distinct, and records his independent open.
5. Confirms exactly one canonical match and one thread are created.
6. Sends one Alice message and confirms Bob reads exactly one copy.
7. Confirms Carol cannot read or write the thread or inspect hidden decisions.
8. Repeats idempotent requests and confirms no duplicates.
9. Confirms all embedding chunks are recombined before whole-pool retrieval.
10. Emits a short human-readable pass/fail report without profile text,
    embeddings, hidden decisions, secrets, or stack traces.

The scenario calls the exact
[`STAGE_1_OPERATION_CONTRACT.md`](../../specs/STAGE_1_OPERATION_CONTRACT.md)
surface. It may begin with a thin test double while isolated; orchestration
points it at the integrated Core façade without changing scenario semantics.

## Explicit deferrals

- Layered inspector UI.
- Qualitative LLM judging and broad datasets.
- Supabase/browser/production isolation tests.
- Regression dashboards and cross-version reporting.
- Real identities or production data.

## Required review panel

- Current-Jac testing expert.
- Application-contract and integration-boundary reviewer.
- Test-isolation, privacy, and end-to-end behavior specialist.

Create:

```text
apps/connection-agent/docs/specs/stage-1/evaluation-quality/IMPLEMENTATION_SPEC.md
apps/connection-agent/docs/specs/stage-1/evaluation-quality/HANDOFF_REPORT.md
```

## Acceptance

- One documented command runs the scenario repeatedly without network access or
  credentials and returns nonzero on a broken invariant.
- The reciprocal flow, Carol denial, repeated-action idempotency, and whole-pool
  behavior have deterministic assertions.
- The evaluator imports/calls released product behavior and contains no
  matching, consent, authorization, or message implementation of its own.
- Provide an `evals/check.sh` hook that the root quality gate can call.
- Existing foundation tests and `./apps/connection-agent/scripts/check.sh` pass.

## Completion and handback

Complete both reviews, commit the implementation/spec/report, push with
`git push -u origin HEAD`, and stop. Do not merge to `main`. Return the final SHA,
scenario command, and complete workflow evidence.
