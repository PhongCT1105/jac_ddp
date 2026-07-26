# Objective 00: Orchestration and Core

> **Stage 2/3 backlog:** For the current showable product, implement only
> [`../stage-1/handoffs/00_CORE.md`](../stage-1/handoffs/00_CORE.md). Do not run
> C1–C4 as a sequential Stage 1 queue.

**Session:** Primary orchestration agent

**Goal:** Keep the shared application contract stable, implement the conflict-prone product lifecycle once, coordinate integration order, and merge green vertical increments from the four implementation objectives.

## Writable paths

```text
apps/connection-agent/src/contracts/
apps/connection-agent/src/core/
apps/connection-agent/docs/
apps/connection-agent/tests/integration/
```

The orchestration agent may make small reviewed changes to shared root documentation, CI, or scripts. It does not implement work inside another objective merely to bypass a handoff.

## Read-only boundaries

```text
platform/
sandbox/
docs/phong-distributed/
docs/luke-sandbox/
```

## Ordered specs

### C1 — Profile proposal lifecycle

Persist first-party session events and route profile turns through proposal, inspection, edit/approval, immutable revision creation, rejection, and derived-projection state. Only approved Markdown and explicit current-request snapshots may enter matching.

**Acceptance:** repeated approval is idempotent; stale approval conflicts; unrelated raw transcript text is absent from embedding and matching fixtures.

### C2 — Suggestion lifecycle

Own canonical unordered pair identity, recipient-specific immutable cards, one active suggestion per viewer, reciprocal private queuing, skip/pass/expire/invalidate behavior, and stale-revision revalidation.

**Acceptance:** reversed actor order shares one pair; Alice opening queues but does not reveal a separate Bob suggestion; prior cards remain immutable; terminal/reconsideration rules have tests.

### C3 — Atomic interest, match, and thread

Coordinate the server-side transaction boundary implemented by Data and Integrations. Two independent opens create exactly one match/thread; a pass, block, stale suggestion, retry, or concurrent request cannot create a false or duplicate match.

**Acceptance:** simultaneous/repeated opens and reversed order produce one match/thread; one-sided interest remains hidden.

### C4 — Agent capability orchestration

Route first-party turns through the released operations. The in-process Jac agent and future MCP transport share capability definitions and handlers.

**Acceptance:** the profile-to-suggestion loop uses only released capabilities; transport tests prove identical input/output and authorization semantics.

## Orchestration duties

- Review proposed contract changes before implementation.
- Assign coordinated Supabase migration timestamps.
- Merge contracts/migrations before dependent adapters.
- Run `./apps/connection-agent/scripts/check.sh` before and after every integration.
- Reject changes outside an objective's writable paths unless an explicit handoff exists.
- Keep an integration ledger of merged revisions, migrations, and workload versions.
- Resolve shared failures in core/integration paths, not inside Phong's or Luke/Santhos's code.

## Done

Core is complete when all four objective suites pass against one contract release, the complete first-party loop passes with fakes and real adapters, and no product lifecycle has competing implementations.
