# Objective 01: Jac Backend and Integrations

> **Stage 2/3 backlog:** For the current showable product, implement only
> [`../stage-1/handoffs/01_DATA_INTEGRATIONS.md`](../stage-1/handoffs/01_DATA_INTEGRATIONS.md).
> Do not run D1–D6 as a sequential Stage 1 queue.

**Session:** Implementation agent 1

**Goal:** Implement secure durable product state, identity, realtime behavior,
and replaceable external-service adapters using Jac's native backend. Do not
decide matching intelligence or product presentation.

**Architecture:**
[`JAC_BACKEND_AND_JACHAMMER.md`](../JAC_BACKEND_AND_JACHAMMER.md)

## Writable paths

```text
apps/connection-agent/src/backend/
apps/connection-agent/src/adapters/
apps/connection-agent/tests/data_integrations/
apps/connection-agent/docs/specs/stage-1/data-integrations/
```

## Read-only paths

`src/contracts/`, `src/core/`, `src/intelligence/`, `web/`, `evals/`,
`workloads/`, `platform/`, and `sandbox/` are read-only. Request contract
changes from orchestration. `supabase/` is inactive and must not receive new
implementation.

## Ordered Stage 2/3 specs

### D1 — Persistent Jac product graph

Model sessions/events, immutable profile revisions, derived projections,
assessments, recipient-specific cards/suggestions, private decisions, blocks,
matches, threads, messages, and notifications as Jac nodes and typed edges.
Attach durable entities to the correct root and return typed view objects rather
than raw nodes.

**Acceptance:** the graph survives restart on the configured backend, schema
changes use Jac alias/upgrade/quarantine mechanisms, and the complete fixture
state can be created without SQL or authored Python/TypeScript.

### D2 — Authentication, isolation, and grants

Use Jac authentication and per-user roots. Define the operation/permission
matrix; use explicit per-root grants for cards and matched threads; keep raw
profiles, vectors, assessments, traces, and one-sided decisions server-private.
Remember that `jobj()` resolves but does not authorize.

**Acceptance:** positive and negative tests cover two authenticated users,
direct-ID guessing, cross-user writes, hidden one-sided decisions, and a third
user attempting to access the thread.

### D3 — Jac-native operation persistence

Implement the released repository behavior through the Jac persistent graph
while preserving fake behavior. Reciprocal-interest detection and creation of
one match/thread must remain atomic and idempotent under Core's lifecycle rules.

**Acceptance:** the foundation lifecycle suite passes with persistent Jac state,
including simultaneous/retried opens producing exactly one match/thread.

### D4 — JacGrid compute adapters

Maintain `MockJacGrid` and implement `LiveJacGrid` behind `EmbeddingCompute` in
Jac. Handle authenticated submission, polling, timeout, bounded retry, error
translation, idempotency, workload identity, completeness, hashes, and receipts.
The browser never receives the provider credential.

**Acceptance:** identical fixture input produces contract-compatible results
locally and through recorded/live JacGrid responses; malformed/partial results
are rejected before projection persistence; no platform or sandbox source is
imported.

### D5 — Jac authentication and application actor

Translate a valid Jac user session into the transport-independent `Actor`.
Fixture identity is unavailable in the production profile. Use built-in
username/email auth or configured SSO for the hackathon; phone OTP remains a
later thin Jac integration if still required.

**Acceptance:** repeat sessions resolve the same actor/profile; forged fixture
identity fails outside local/test mode; two users have isolated roots.

### D6 — Private realtime messages

Implement persistent ordered messages and authorized live delivery through Jac
WebSocket/function endpoints, with safe refresh fallback. Keep human messages
distinct from agent utterances and coordination suggestions.

**Acceptance:** two participants exchange messages and reconnect without
duplicates; a third user cannot subscribe, read, or write.

### D7 — JacHammer deployment verification

Deploy the consolidated full-stack Jac app through the free JacHammer sandbox
and execute the verification list in
[`JAC_BACKEND_AND_JACHAMMER.md`](../JAC_BACKEND_AND_JACHAMMER.md).

**Acceptance:** judges can open a stable URL; auth/isolation, required
persistence, messaging behavior, outbound JacGrid access, and server-only
secrets are demonstrated with evidence. A local Jac run remains the fallback.

## Required checks

- Jac MCP/compiler-backed review using current server, persistence, auth,
  multi-user, testing, and deploy guides.
- Fresh persistent-graph and schema-evolution tests.
- Authentication/grant positive and negative tests.
- Fake/persistent behavior parity tests.
- Recorded/live JacGrid adapter contract tests.
- Hosted isolation, secret-exposure, and cold-start checks.
- Root application check remains green.

## Done

This objective is complete when the walking skeleton runs against Jac's native
backend and live-compatible compute adapters, then the full-stack Jac product is
verified on JacHammer without Supabase or authored non-Jac product logic.
