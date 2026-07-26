# Stage 1 handoff: Local data and integration adapters

**Execution directive:** Implement this handoff end to end, following the
mandatory workflow linked below.

**Worktree:** `/Users/sebastian/dev/jac_ddp-data-integrations`

**Branch:** `agent/data-integrations`

**Push destination:** `origin/agent/data-integrations`

## Goal

Provide the small deterministic local boundaries needed by the showable
product: fixture identity, immutable fixture-profile access, and the existing
`MockJacGrid` compute adapter. Core retains all demo lifecycle state and reset
behavior.

This is one Stage 1 specification, not D1–D6. Durable Jac backend and live
service integration are deferred until the local product is green.

## Required reading

- [`../../AGENT_WORKFLOW.md`](../../AGENT_WORKFLOW.md)
- [`../../JAC_NATIVE_ENGINEERING.md`](../../JAC_NATIVE_ENGINEERING.md)
- [`../../JAC_BACKEND_AND_JACHAMMER.md`](../../JAC_BACKEND_AND_JACHAMMER.md)
- [`../../STAGE_1_PRODUCT.md`](../../STAGE_1_PRODUCT.md)
- [`../../specs/INTERNAL_CONTRACT_V1.md`](../../specs/INTERNAL_CONTRACT_V1.md)
- [`../../specs/STAGE_1_OPERATION_CONTRACT.md`](../../specs/STAGE_1_OPERATION_CONTRACT.md)
- [`../../specs/WALKING_SKELETON.md`](../../specs/WALKING_SKELETON.md)
- [`../../objectives/01_DATA_AND_INTEGRATIONS.md`](../../objectives/01_DATA_AND_INTEGRATIONS.md) as backlog context only
- `docs/specs/CONNECTION_AGENT_JACGRID_BOUNDARIES.md`

## Writable paths

```text
apps/connection-agent/src/adapters/
apps/connection-agent/tests/data_integrations/
apps/connection-agent/docs/specs/stage-1/data-integrations/
```

Everything else is read-only, including `src/contracts/`, `src/core/`,
`src/backend/`, `src/intelligence/`, `web/`, `evals/`, `workloads/`, `platform/`,
and `sandbox/`.

## Required deliverable

Build or consolidate fixture-only adapters that:

1. Select Alice, Bob, Carol, and the existing synthetic people through an
   explicit local fixture identity boundary.
2. Return the existing immutable, preapproved synthetic Markdown profile
   revision for the selected actor without exposing other profiles through the
   client-facing lookup.
3. Return deterministic fixture data for every new Core-owned demo instance;
   it does not own reset or mutable product state.
4. Expose the existing `MockJacGrid` as the default embedding-compute adapter,
   invoking the exact local `connection-embedding` package and combining every
   task result before returning.
5. Use interfaces compatible with the released contract. If the façade needs
   an additive interface not yet released, record the smallest contract request
   for orchestration rather than editing `src/contracts/`.

Do not store suggestions, decisions, matches, threads, or messages in this
Stage 1 lane. Do not create another consent/match algorithm or embedding algorithm.
Do not log profile text, vectors, hidden decisions, or secrets by default.

## Explicit deferrals

- Durable Jac graph persistence, production accounts, grants, and WebSockets.
- Phone OTP and production identity.
- Live JacGrid networking, polling, retries, and credentials.
- Notifications and multi-process persistence.

These remain D1–D6 backlog items. Stage 1 must run without a network or secret.

## Required review panel

- Current-Jac interoperability expert.
- Application-contract and provider-boundary reviewer.
- Repository authorization and test-isolation specialist.

Create:

```text
apps/connection-agent/docs/specs/stage-1/data-integrations/IMPLEMENTATION_SPEC.md
apps/connection-agent/docs/specs/stage-1/data-integrations/HANDOFF_REPORT.md
```

## Acceptance

- Selecting an unknown or non-fixture actor fails safely.
- Actor-scoped profile lookup has positive and negative tests.
- Repeated fixture-source construction returns the same immutable starting data
  without mutable state leaking between callers.
- `MockJacGrid` still invokes the exact workload in chunks and returns one
  complete, validated result for all profiles.
- Existing foundation tests and `./apps/connection-agent/scripts/check.sh` pass.
- All authored runtime code is Jac; any exception satisfies and records the
  `JAC_NATIVE_ENGINEERING.md` process.

## Completion and handback

Complete both reviews, commit the implementation/spec/report, push with
`git push -u origin HEAD`, and stop. Do not merge to `main`. Return the final SHA
and complete workflow evidence.
