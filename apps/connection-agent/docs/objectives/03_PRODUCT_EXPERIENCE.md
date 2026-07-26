# Objective 03: Product Experience

> **Stage 2/3 backlog:** For the current showable product, implement only
> [`../stage-1/handoffs/03_PRODUCT_EXPERIENCE.md`](../stage-1/handoffs/03_PRODUCT_EXPERIENCE.md).
> Do not run U1–U7 as a sequential Stage 1 queue.

**Session:** Implementation agent 3

**Goal:** Build the responsive Jac first-party experience for profile conversation, suggestions, private consent, matches, and human chat against released operations and fake handlers first.

## Writable paths

```text
apps/connection-agent/web/
apps/connection-agent/tests/experience/
```

## Read-only paths

`src/contracts/`, `src/core/`, `src/adapters/`, `src/intelligence/`, `supabase/`, `evals/`, `workloads/`, `platform/`, and `sandbox/` are read-only. Request new operation behavior from the orchestration agent.

## Ordered specs

### U1 — Mobile conversation shell

Create the minimal responsive Jac web/PWA shell with conversation history, composer, loading, empty, retry, and safe error states. Use fake handlers through the released capability contract.

**Acceptance:** the shell works at phone width and preserves earlier cards/messages in history.

### U2 — Development and production entry

Add a local-only fixture-persona selector and production phone OTP screens behind the identity boundary.

**Acceptance:** the same UI works as a fixture actor locally and authenticated actor in integration; fixture controls are absent from production output.

### U3 — Profile proposal and approval

Render conversational profile capture, Markdown proposal review, edit/approve/reject actions, revision identity, and embedding readiness.

**Acceptance:** a fixture person completes proposal through approved revision using only released operations.

### U4 — Suggested-person card

Render one viewer-specific card inside conversation with open, pass, someone-else, and tell-me-more actions. Preserve the immutable shown card.

**Acceptance:** retries do not duplicate actions, loading does not reveal hidden decisions, and previous cards remain readable.

### U5 — Mutual match transition

Show no reciprocity after one open. On a true match, transition both participants to the single private thread without exposing action timing.

**Acceptance:** open/pass and never-viewed scenarios reveal nothing; reciprocal opens converge on one thread.

### U6 — Direct human chat

Implement ordered message history, realtime append, reconnect, send retry, and clear distinction between human messages and invited agent suggestions.

**Acceptance:** two sessions exchange one copy of each message after reconnect; unauthorized states render safely.

### U7 — Return states and polish

Add authenticated deep links, recoverable provider failures, offline/reconnect handling, accessible focus/labels, and hackathon-ready responsive polish.

**Acceptance:** the full demo can recover from refresh and temporary compute delay without losing canonical product state.

## Required checks

- Component and operation-adapter tests using fakes.
- Phone-width and desktop responsive checks.
- Accessibility checks for keyboard, focus, labels, and contrast.
- Production bundle check excluding fixture controls and secrets.
- Root application check remains green.

## Done

This objective is complete when two fixture people can complete the approved-profile-to-private-chat loop through the first-party UI, and the same client is ready for real adapters without product-rule changes.
