# Objective 02: Intelligence and Workload

> **Stage 2/3 backlog:** For the current showable product, implement only
> [`../stage-1/handoffs/02_INTELLIGENCE_WORKLOAD.md`](../stage-1/handoffs/02_INTELLIGENCE_WORKLOAD.md).
> Do not run I1–I8 as a sequential Stage 1 queue.

**Session:** Implementation agent 2

**Goal:** Implement profile intelligence, the immutable embedding workload, candidate retrieval, reciprocal pair reasoning, viewer-specific cards, explanations, and minimal coordination.

## Writable paths

```text
apps/connection-agent/src/intelligence/
apps/connection-agent/tests/intelligence/
workloads/connection-embedding/
```

## Read-only paths

`src/contracts/`, `src/core/`, `src/adapters/`, `supabase/`, `web/`, `evals/`, `platform/`, and `sandbox/` are read-only. Request contract changes from the orchestration agent.

## Ordered specs

### I1 — Typed intelligence fixtures

Release schema-valid fixtures for profile proposals, embedding projections, retrieval sets, reciprocal assessments, cards, explanations, and coordination suggestions. Record prompt/model/workload versions and source profile revisions.

**Acceptance:** valid fixtures deserialize through released types; malformed or incomplete fixtures fail with stable codes.

### I2 — Conversational profile proposal

Use Jac `by llm()` to transform a user's conversation into concise canonical Markdown while preserving dated context and returning an inspectable proposal before persistence. Tests use recorded/mock responses.

**Acceptance:** a natural fixture turn produces an understandable proposal; unapproved raw transcript is not used for retrieval or assessment.

### I3 — Production embedding workload

Release a new immutable `connection-embedding` version with exact model artifact/revision, dependency lock, preprocessing, normalization, schemas, resources, numeric tolerance, and fixtures. Do not overwrite foundation workload `0.1.0` semantics.

**Acceptance:** local harness, `MockJacGrid`, recorded live response, and sandbox integration return contract-compatible vectors; meaningful profile changes create a projection for the exact revision.

### I4 — Candidate retrieval

Retrieve a bounded neighborhood from the complete eligible embedding set. Exclude self, blocks, system-ineligible actors, and lifecycle-ineligible prior suggestions. Keep natural-language preferences for reciprocal reasoning rather than mislabeling them as database filters.

**Acceptance:** deterministic fixtures prove whole-pool ranking, exclusions, bounded output, stable tie handling, and source revision tracking.

### I5 — Jac candidate topology and walker

Represent only the bounded candidate neighborhood in Jac and traverse it through a walker for reciprocal assessment orchestration. Supabase remains canonical; the Jac graph does not duplicate identity or messages.

**Acceptance:** the walker examines only retrieved candidates and returns typed, traceable evidence.

### I6 — Reciprocal pair assessment

Evaluate both people's approved profiles plus explicit current-request snapshots. Return reciprocal fit, concerns, evidence, uncertainty, and a decision suitable for card generation.

**Acceptance:** reversing actor order preserves canonical pair identity while allowing viewer-specific interpretation; unsupported claims fail grounding checks.

### I7 — Viewer-specific cards and explanations

Generate a distinct immutable card for each viewer and grounded follow-up disclosures tied to the exact profile revisions used.

**Acceptance:** Alice/Bob cards differ appropriately, remain mobile-safe, preserve history, and disclose only relevant allowed profile information.

### I8 — Minimal invited coordination

When explicitly summoned inside a match, return one helpful coordination suggestion without external actions or venue booking.

**Acceptance:** suggestions are invited, grounded, clearly agent-authored, and separate from human messages.

## Required checks

- No live LLM calls in unit tests.
- Workload schemas, deterministic fixtures, parity, malformed output, and tolerance tests.
- Retrieval exclusion and whole-pool tests.
- Grounding and reciprocal assessment evaluations.
- Root application check remains green.

## Done

This objective is complete when an approved profile revision produces a verified projection and the bounded Jac reasoning pipeline returns grounded recipient-specific cards and explanations through released operations.
