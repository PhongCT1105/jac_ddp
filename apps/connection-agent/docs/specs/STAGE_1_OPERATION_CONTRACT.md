# Stage 1 operation contract

**Status:** Frozen launch contract

**Owner:** Orchestration and Core

## 1. Purpose

This document freezes the operation surface used independently by the Core,
Data, Intelligence, Product Experience, and Evaluation Stage 1 branches. It
narrows the broader conceptual V1 contract to the showable local journey so the
Web fixture client and Evaluation runner can integrate with Core without
inventing different operations.

Stage 1 is in-process and fixture-only. Transport routes are not part of this
contract. Exact Jac request/response objects may be additive implementations of
these shapes, but operation names, meanings, privacy, and errors cannot change
on an implementation branch.

## 2. State ownership

One `DemoApp` instance owns one isolated in-memory demo run. Core exclusively
owns suggestion state, private decisions, matches, threads, messages,
idempotency, authorization decisions, and reset behavior.

Data supplies only synthetic fixture actors/profiles and the `MockJacGrid`
compute adapter. Intelligence supplies retrieval, pair assessment, and card
generation. Web and Evaluation are clients. None of those lanes persists or
reimplements Core lifecycle state in Stage 1.

## 3. Released Stage 1 operations

### `reset_demo()`

Local/test-only operation. Replaces the current `DemoApp` instance with a clean
state seeded from the same immutable synthetic profiles. It returns no private
prior state.

### `select_fixture_actor(actor_id)`

Returns the released `Actor`. The actor ID must exist in the synthetic fixture
source and have `fixture = true`. An unknown/non-fixture ID returns
`fixture_actor_not_found`. Selection is client context and does not grant access
to another actor's resources.

### `get_profile(actor)`

Returns that actor's existing, preapproved immutable `ProfileRevision`. Stage 1
shows the Markdown and asks the person to confirm “Use this demo profile,” but
does not edit or persist a proposal. An actor cannot retrieve another actor's
canonical profile through this client operation.

### `request_next_suggestion(actor, current_request, idempotency_key)`

Inputs:

```text
actor: Actor
current_request: string | null
idempotency_key: non-empty string
```

Returns one released `Suggestion` containing an immutable viewer-specific
`CardSnapshot`. It uses the actor's preapproved profile plus only the explicit
current request; processes or reuses embeddings for the complete eligible
fixture set; excludes self, blocks, and system-ineligible actors; and delegates
retrieval, assessment, and card content to Intelligence.

An identical retry returns the same suggestion. Reusing the key with different
input returns `idempotency_conflict`. Stage 1 supports one active suggestion per
viewer. No result exposes another actor's decision.

### `record_interest(actor, suggestion_id, kind, idempotency_key)`

Inputs:

```text
actor: Actor
suggestion_id: string owned by actor
kind: "open" | "pass"
idempotency_key: non-empty string
```

Returns:

```text
decision: InterestDecision
match: MatchRecord | null
```

The decision is private. The first open returns `match = null` and reveals
nothing about the other actor. Reciprocal independent opens for the same
canonical pair return exactly one `MatchRecord` and one associated
`ThreadRecord`. Pass never creates a match. Identical retries return the prior
result; changed input with the same key returns `idempotency_conflict`.

### `load_thread(actor, thread_id)`

Returns:

```text
thread: ThreadRecord
messages: ordered list[MessageRecord]
```

Only a thread participant may call it. Missing and forbidden resources use a
safe, non-disclosing `thread_forbidden` response consistent with
`INTERNAL_CONTRACT_V1.md`.

### `send_message(actor, thread_id, body, idempotency_key)`

Returns one released `MessageRecord`. Only a participant may send a non-empty
human message. Identical retries return the same message; changed input with the
same key returns `idempotency_conflict`.

## 4. Client-visible error codes

Stage 1 uses released errors where defined plus `fixture_actor_not_found` for
the local-only selector:

```text
fixture_actor_not_found
profile_not_found
idempotency_conflict
no_eligible_candidate
embedding_not_ready
embedding_failed
suggestion_not_active
interest_already_recorded
thread_forbidden
invalid_request
internal_error
```

Errors never contain raw profile text, vectors, hidden decisions, secrets, or
provider stack traces.

## 5. Integration fixtures

- `alice_builder` and `bob_researcher` form the positive reciprocal path.
- Alice receives a card about Bob; Bob receives a distinct card about Alice.
- `carol_designer` is the unauthorized third actor for thread tests.
- At least 30 eligible synthetic profiles participate in whole-pool retrieval.
- The exact immutable `connection-embedding` workload `1.0.0` runs through
  `MockJacGrid` by default. It produces 384-dimensional vectors through the
  pinned MiniLM runtime or its separately tagged deterministic fallback.

### Integration amendment

The Stage 1 branches originally targeted the dependency-free
`connection-embedding` `0.1.0` foundation fixture. The accepted JacGrid
integration introduced the application-owned `1.0.0` file-I/O package used by
the live sandbox. Consolidation upgraded `MockJacGrid` to invoke and validate
that same package instead of restoring or duplicating the old algorithm. This
changes workload identity and vector dimensions only; the frozen application
operations, privacy rules, idempotency, and ownership boundaries are unchanged.

Web may build a scripted, contract-valid fixture client that returns these exact
shapes while branches are isolated. That fixture proves rendering and
interaction only; it makes no product-correctness claim. Evaluation may
initially use the foundation composition. During consolidation both are wired
to `DemoApp` without changing their product behavior.

## 6. Change control

Only the Core branch may propose additive Jac types needed to implement this
frozen surface. It may not change operation semantics. Other branches record a
contract request in their handoff report and continue against this document.

Editable profile proposals, full revision lifecycle, production identity,
Durable Jac persistence, live JacGrid, WebSocket delivery, and remote transports are
Stage 2/3 work and cannot be added during Stage 1.
