# Stage 1 handoff: Core operation surface

**Execution directive:** Implement this handoff end to end, following the
mandatory workflow linked below.

**Worktree:** `/Users/sebastian/dev/jac_ddp-orchestration-core`

**Branch:** `agent/orchestration-core`

**Push destination:** `origin/agent/orchestration-core`

## Goal

Expose the existing walking-skeleton behavior through one stateful,
transport-independent application façade that the Jac web client and evaluation
scenario can call. Preserve all private-interest, authorization, idempotency,
and canonical-pair rules.

This is one Stage 1 specification. It is a deliberately narrow cut through C2
and C3, with only the minimum profile behavior needed by the demo. Do not
implement all C1–C4.

## Required reading

- [`../../AGENT_WORKFLOW.md`](../../AGENT_WORKFLOW.md)
- [`../../JAC_NATIVE_ENGINEERING.md`](../../JAC_NATIVE_ENGINEERING.md)
- [`../../JAC_BACKEND_AND_JACHAMMER.md`](../../JAC_BACKEND_AND_JACHAMMER.md)
- [`../../STAGE_1_PRODUCT.md`](../../STAGE_1_PRODUCT.md)
- [`../../specs/INTERNAL_CONTRACT_V1.md`](../../specs/INTERNAL_CONTRACT_V1.md)
- [`../../specs/STAGE_1_OPERATION_CONTRACT.md`](../../specs/STAGE_1_OPERATION_CONTRACT.md)
- [`../../specs/WALKING_SKELETON.md`](../../specs/WALKING_SKELETON.md)
- [`../../objectives/00_ORCHESTRATION_AND_CORE.md`](../../objectives/00_ORCHESTRATION_AND_CORE.md) as backlog context only
- `docs/specs/CONNECTION_AGENT_JACGRID_BOUNDARIES.md`

## Writable paths

```text
apps/connection-agent/src/contracts/
apps/connection-agent/src/core/
apps/connection-agent/tests/integration/
apps/connection-agent/docs/specs/stage-1/core/
```

Everything else is read-only. In particular, do not edit `src/adapters/`,
`src/intelligence/`, `web/`, `evals/`, `workloads/`, `platform/`, or `sandbox/`.

## Required deliverable

Create one in-process application façade, with additive typed request/response
objects where necessary, that supports this fixture-only journey:

1. Start or reset an isolated `DemoApp` state owned exclusively by Core.
2. Select a synthetic fixture actor without pretending this is production auth.
3. Read that actor's preapproved immutable synthetic profile.
4. Request the next suggestion through an injected profile/compute/intelligence
   boundary rather than hardcoding a person in core.
5. Read the immutable viewer-specific card.
6. Record `open` or `pass` idempotently without exposing the other actor's
   decision.
7. Switch fixture actors and repeat independently.
8. Create exactly one canonical match and thread after reciprocal opens.
9. Load authorized messages and send one idempotent human message.
10. Reject Carol or any nonparticipant reading or writing the thread.

The façade implements exactly
[`STAGE_1_OPERATION_CONTRACT.md`](../../specs/STAGE_1_OPERATION_CONTRACT.md),
owns all Stage 1 lifecycle state and reset behavior, and accepts injected fakes so it
can be tested before the Data and Intelligence branches are integrated. It must
not contain a second embedding, retrieval, card-generation, or persistence
implementation.

## Explicit deferrals

- Profile proposals, editing/approval, revision concurrency, and stale-approval behavior.
- All suggestion states and reconsideration policies beyond the demonstrated
  `open` and `pass` path.
- MCP or remote transport.
- Production authentication, persistence, notifications, and realtime delivery.
- Coordination help and open-ended explanation.

## Required review panel

- Current-Jac expert.
- Application-contract and architecture reviewer.
- Lifecycle, authorization, and idempotency specialist.

Follow the spec-review and implementation-review process in
[`AGENT_WORKFLOW.md`](../../AGENT_WORKFLOW.md). Create:

```text
apps/connection-agent/docs/specs/stage-1/core/IMPLEMENTATION_SPEC.md
apps/connection-agent/docs/specs/stage-1/core/HANDOFF_REPORT.md
```

## Acceptance

- A deterministic integration test calls only the frozen Stage 1 operations and
  completes profile read → suggestion → first private open → reciprocal open → one
  match/thread → one message journey.
- Repeated operations with the same keys do not duplicate decisions, matches,
  threads, or messages.
- Reusing a key with different input fails safely.
- No operation exposes whether the other actor has opened before a match.
- A third actor cannot inspect or mutate the thread.
- Reset produces a clean, repeatable demo state.
- Existing foundation tests and `./apps/connection-agent/scripts/check.sh` pass.
- All authored runtime code is Jac; any exception satisfies and records the
  `JAC_NATIVE_ENGINEERING.md` process.

## Completion and handback

Complete both reviews, commit the implementation/spec/report, and run:

```bash
git push -u origin HEAD
```

Do not merge to `main`. Return the final SHA and the complete evidence required
by `AGENT_WORKFLOW.md`.
