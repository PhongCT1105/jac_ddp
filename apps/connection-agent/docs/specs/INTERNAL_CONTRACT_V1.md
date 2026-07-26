# Connection Agent Internal Contract V1

**Status:** Released foundation contract

**Owner:** Orchestration and Core

**Implementation:** `apps/connection-agent/src/contracts/models.jac`

## 1. Purpose

All application clients, core services, intelligence functions, repositories, compute providers, and evaluation tools use the same transport-independent operations and domain meanings. HTTP, MCP, Jac agent calls, Supabase, and in-memory fakes are adapters around this contract rather than separate product implementations.

## 2. Common rules

- IDs are opaque strings and are never parsed to grant authorization.
- Every operation receives an authenticated actor or an explicitly local fixture actor.
- Profile-derived records carry the exact immutable profile revision ID used to create them.
- Mutating operations require an idempotency key scoped to actor and operation.
- Reusing a key with identical input returns the original result.
- Reusing a key with different input returns `idempotency_conflict`.
- Errors use stable codes, safe messages, and an explicit retryable flag.
- Raw conversation history is not a matching input. Only approved canonical Markdown plus an explicit current-request snapshot may cross into matching.
- One-sided interest is private. It is never exposed through another actor's operations or errors.

## 3. Released domain objects

The Jac objects in `models.jac` are the compile-time source for the foundation. Their meanings are:

| Object | Required identity and invariants |
|---|---|
| `Actor` | Authenticated or local-fixture caller; `actor_id` is authoritative |
| `ProfileRevision` | Immutable `revision_id`, owning actor, display name, canonical Markdown, eligibility and blocks |
| `EmbeddingItem` | Correlation ID plus approved/synthetic text sent to a compute adapter |
| `EmbeddingBatchResult` | One complete vector per item, workload version/hash, lifecycle, result hash |
| `CandidateReference` | Candidate actor, source revision, deterministic retrieval score |
| `PairAssessment` | Canonical unordered pair, reciprocal score, grounded evidence |
| `CardSnapshot` | Immutable, viewer-specific rendering tied to subject revision and pair |
| `Suggestion` | Viewer/subject opportunity and exact card snapshot with lifecycle state |
| `InterestDecision` | Private viewer decision with idempotency key |
| `MatchRecord` | Exactly one record per reciprocally open canonical pair |
| `ThreadRecord` | Exactly one private thread per match and exactly two participants in V1 |
| `MessageRecord` | Ordered participant-authored message with idempotency key |
| `AppError` | Stable code, safe message, retryability |

As production fields are added, the orchestration agent updates the contract before dependent implementation. Adapters may maintain private provider metadata that never leaks into core operations.

## 4. Exact lifecycle values

Embedding job states:

```text
queued → running → verifying → complete
                           ↘ failed
```

Suggestion states:

```text
queued → active → open
                → passed
                → skipped
                → expired
                → invalidated
```

Rules:

- Only one suggestion is active for one viewer.
- `open` and `passed` are explicit private decisions.
- `skipped` means “show me someone else,” not rejection.
- An immutable card remains in history after its suggestion changes state.
- A material profile revision invalidates a stale suggestion before a decision is accepted.
- A canonical unordered pair identity is the same when actor order is reversed.
- A match and thread appear only after both viewers independently open their own recipient-specific suggestions.

## 5. Application operations

These are conceptual typed operations. Concrete Jac signatures may group values into request/response objects as the implementation grows, but their behavior cannot change silently.

### `get_profile(actor)`

Returns the actor's current approved profile revision or `profile_not_found`. It never returns another actor's canonical Markdown through a client operation.

### `propose_profile_update(actor, conversation_input, idempotency_key)`

Returns a reviewable Markdown proposal without making it canonical. The proposal records its source conversation/session and expected prior revision.

### `approve_profile_update(actor, proposal_id, edited_markdown, idempotency_key)`

Creates one immutable canonical revision owned by the actor and queues its derived embedding projection. Concurrent approval against a stale prior revision returns `profile_revision_conflict`.

### `get_embedding_state(actor, profile_revision_id)`

Returns `queued`, `running`, `verifying`, `complete`, or `failed` for the actor's revision. Provider IDs and credentials remain inside the adapter.

### `request_next_suggestion(actor, current_request, idempotency_key)`

Uses only the actor's approved revision and explicit current request. It excludes self, blocks, ineligible actors, and lifecycle-ineligible opportunities; retrieves a bounded neighborhood from the complete available embedding set; performs reciprocal assessment; and returns one active viewer-specific card.

If an active suggestion already exists, an identical retry returns it. A new “someone else” action must first transition the active suggestion through the explicit skip operation.

### `explain_suggestion(actor, suggestion_id, question, idempotency_key)`

Returns a grounded explanation based only on the exact subject profile revision and pair assessment behind the card. It records the source revision and never exposes raw assessment data or unrelated private profile content.

### `record_interest(actor, suggestion_id, kind, idempotency_key)`

`kind` is exactly `open` or `pass`. The actor must own the suggestion and it must still be decision-eligible. The operation records one private decision. Reciprocal independent opens atomically return one match and one thread; all other outcomes reveal nothing about the other actor's decision.

### `load_thread(actor, thread_id)`

Returns a private thread and ordered messages only when the actor is a participant. Direct-ID guessing and third-party realtime subscriptions must fail with the same authorization semantics.

### `send_message(actor, thread_id, body, idempotency_key)`

Appends one non-empty human message when the actor participates in the thread. Retrying with the same key creates no duplicate. Agent coordination responses use a distinct message/event kind when introduced.

### `request_coordination_help(actor, thread_id, request, idempotency_key)`

Returns one invited, minimal coordination suggestion grounded in the matched participants' allowed context. It cannot autonomously disclose profiles, contact venues, or take an external action in V1.

## 6. Adapter contracts

Each external boundary has a production and development adapter implementing the same application operation:

| Boundary | Development adapter | Production/integration adapter |
|---|---|---|
| Identity | Explicit fixture actor | Supabase phone-authenticated actor |
| Product storage | In-memory repositories | Supabase repositories with RLS |
| Embedding compute | `MockJacGrid` invoking exact local workload | `LiveJacGrid`, later another compatible provider |
| Candidate retrieval | Complete fixture vector set | Supabase pgvector bounded retrieval |
| LLM | Recorded/deterministic response | Configured Jac `by llm()` model |
| Notifications | Captured outbox | Configured delivery adapter |
| Realtime | In-memory ordered messages | Supabase Realtime |

Fakes reproduce boundary behavior, not alternative product rules.

## 7. Stable error codes

| Code | Meaning | Retryable by default |
|---|---|---|
| `unauthenticated` | No valid application actor | No |
| `forbidden` | Actor cannot access the resource/action | No |
| `not_found` | Resource is not visible to the actor | No |
| `invalid_request` | Required input or state is invalid | No |
| `idempotency_conflict` | Key was reused with different input | No |
| `profile_revision_conflict` | Operation targeted a stale revision | No |
| `embedding_not_ready` | Required projection is still processing | Yes |
| `embedding_failed` | Compute reached a terminal failure | Depends on cause |
| `no_eligible_candidate` | Retrieval found no eligible opportunity | Yes after state changes |
| `suggestion_not_active` | Suggestion cannot accept this action | No |
| `interest_already_recorded` | A different terminal decision already exists | No |
| `thread_forbidden` | Actor is not a thread participant | No |
| `provider_unavailable` | Replaceable external provider is temporarily unavailable | Yes |
| `internal_error` | Unexpected trusted-server error | Yes |

Authorization errors do not disclose whether a hidden resource or one-sided decision exists.

## 8. Agent/tool mapping

The first-party Jac agent and future public MCP adapter expose the same operations through different transports:

| Agent capability | Application operation |
|---|---|
| Read my profile | `get_profile` |
| Propose/save profile | `propose_profile_update`, `approve_profile_update` |
| Show me someone | `request_next_suggestion` |
| Tell me more | `explain_suggestion` |
| Open/pass | `record_interest` |
| Load/send private chat | `load_thread`, `send_message` |
| Help us coordinate | `request_coordination_help` |

Phone authentication, browser navigation, and realtime delivery are not agent tools.

## 9. Foundation conformance

The current walking skeleton implements the minimum released subset: fixture identity/profile reads, embedding computation, complete-pool candidate ranking, deterministic pair/card fixtures, two private decisions, atomic match/thread creation, authorized message listing, and idempotent message creation.

Each objective expands this same surface. An objective is complete only when its fake and real adapters pass the same behavioral tests.

## 10. Change control

- Only the orchestration agent edits `src/contracts/` during parallel work.
- A workstream proposes the smallest needed change with affected operations, compatibility impact, fixture changes, and migration requirement.
- Contract changes merge before implementations that emit or require them.
- Removing a field/state or changing meaning creates V2. Additive optional data can remain V1 after all consumers tolerate it.
