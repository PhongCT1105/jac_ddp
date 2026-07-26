# Objective 01: Data and Integrations

> **Stage 2/3 backlog:** For the current showable product, implement only
> [`../stage-1/handoffs/01_DATA_INTEGRATIONS.md`](../stage-1/handoffs/01_DATA_INTEGRATIONS.md).
> Do not run D1–D6 as a sequential Stage 1 queue.

**Session:** Implementation agent 1

**Goal:** Implement secure durable storage, identity, realtime human messaging, and replaceable external-service adapters without deciding matching intelligence or product presentation.

## Writable paths

```text
apps/connection-agent/src/adapters/
apps/connection-agent/supabase/
apps/connection-agent/tests/data_integrations/
```

## Read-only paths

`src/contracts/`, `src/core/`, `src/intelligence/`, `web/`, `evals/`, `workloads/`, `platform/`, and `sandbox/` are read-only. Request contract changes from the orchestration agent.

## Ordered specs

### D1 — Core persistence schema

Add append-only migrations for sessions/events, profile proposals and immutable revisions, derived search projections, assessments, recipient-specific suggestion/card snapshots, decisions, blocks, matches, threads, messages, and notification outbox records. Include source revision IDs, canonical pair IDs, lifecycle constraints, timestamps, and uniqueness rules.

**Acceptance:** migrations apply from an empty local database and can create the complete fixture state.

### D2 — Authorization and RLS

Implement and document a role/action/table matrix. A person manages their own profile/decisions; only matched participants access a thread; clients cannot read another person's phone number, canonical Markdown, vector, raw assessment, trace, or pending decision.

**Acceptance:** positive and negative tests cover every table, direct-ID guessing, cross-user writes, unauthorized realtime subscriptions, hidden one-sided decisions, and third-party thread access.

### D3 — Repository adapters

Implement the released repository operations against Supabase while preserving fake behavior. Reciprocal-interest detection plus match/thread creation is one atomic idempotent server transaction.

**Acceptance:** the foundation lifecycle suite passes against Supabase, including simultaneous/retried opens creating one match/thread.

### D4 — JacGrid compute adapters

Maintain `MockJacGrid` and implement `LiveJacGrid` behind the internal `EmbeddingCompute` boundary. Handle authenticated submission, polling, timeout, bounded retry, error translation, idempotency, workload identity, result completeness, hashes, and receipts. Never send service credentials to the browser.

**Acceptance:** identical fixture inputs produce contract-compatible results locally and from recorded/live JacGrid responses; malformed/partial results are rejected before persistence; no platform or sandbox implementation is imported.

### D5 — Phone identity and application actor

Implement phone OTP and translate a valid session into the transport-independent `Actor`. Fixture identity is compiled/configured out of production behavior.

**Acceptance:** repeat sessions resolve the same actor/profile; forged fixture headers fail in production mode.

### D6 — Realtime private messages

Implement persistent ordered messages, authorized realtime delivery, and reconnection. Keep human messages distinct from agent utterances and coordination suggestions.

**Acceptance:** two participants exchange messages and reconnect without duplicates; a third session cannot subscribe or read.

## Required checks

- Fresh migration and RLS suites.
- Fake/real repository parity tests.
- Recorded/live JacGrid adapter contract tests.
- Production-isolation and secret-exposure checks.
- Root application check remains green.

## Done

This objective is complete when the walking skeleton passes with Supabase and live-compatible compute adapters substituted for fakes, with authorization and idempotency proven under retries and concurrency.
