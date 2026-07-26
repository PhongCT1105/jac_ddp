# Parallel build plan: AI connection agent

This document divides the hackathon build among several Codex sessions. It defines the order of the work and the contracts that the parts share.

## 1. Build strategy

Connection Agent should be built as one application core with several adapters around it.

```text
First-party web conversation ----+
                                 |
External agent through MCP ------+-- Connection Agent application core -- Supabase
                                 |             |                  |
Evaluation laboratory -----------+             +-- Jac intelligence
                                 |                                |
                                 +-------------------------- JacGrid compute
```

The web experience, public MCP server, and evaluation laboratory must not each implement profile or matching rules. They call the same application operations. This is what allows separate Codex sessions to work against fakes, merge later, and still produce one product.

Development has three stages:

1. **Foundation, sequential:** establish the repository, contracts, boundaries, and a thin walking skeleton.
2. **Parallel workstreams:** data/integrations, intelligence, experience, and evaluation proceed in separate worktrees against the shared contracts.
3. **Continuous integration:** merge small vertical increments throughout the build rather than joining completed subsystems at the end.

The recommended maximum is five concurrent Codex sessions: one integration lead, who also owns core orchestration, and four implementation workstreams. If only four sessions are practical, the integration lead also owns the data/integrations workstream.

## 2. Product cut line

The hackathon build proves one ordinary product loop:

1. A person signs in with a phone number or enters the development lab as a fixture persona.
2. Conversation creates or updates one canonical Markdown profile.
3. The person asks to see someone.
4. Connection Agent retrieves plausible candidates and uses Jac/LLM reasoning to select one.
5. Connection Agent presents one tailored, mobile-safe card inside chat.
6. Each person independently expresses interest or passes.
7. Reciprocal interest creates a private two-person thread.
8. The two people exchange realtime messages.
9. Either person can explicitly summon Connection Agent for one minimal coordination suggestion.

Events are not an application entity, pool, permission, or special workflow. “I am at the Jac hackathon today” is ordinary dated Markdown context. Every signed-in profile is eligible for matching, subject to mutual constraints expressed in profiles or the current conversation.

The public MCP adapter, SMS notifications beyond OTP, automatic venue discovery/booking, and elaborate multi-turn coordination are valuable but may not delay the complete first-party loop. A minimal invited coordination response is part of the demo.

## 3. Boundaries that make parallel development possible

### 3.1 Canonical data

Supabase is canonical for:

- Authenticated user identity.
- Full name and canonical Markdown profile.
- Derived search projection and embeddings.
- Cards shown and interest decisions.
- Matches, threads, and messages.

Jac owns the matching workflow and temporary candidate topology used to reason over a retrieved neighborhood. It does not become a competing source of truth for identity or human messages.

JacGrid is a replaceable distributed-compute dependency, not a source of product truth. The connection-app team owns the immutable embedding workload that JacGrid executes. JacGrid returns verified vectors; Supabase stores the current derived projection, and our Jac logic retrieves and ranks candidates.

### 3.2 Application operations

All clients should depend on the same conceptual operations:

- Get the current person's profile.
- Propose and approve a profile update.
- Show the next suggested person, optionally using the current conversational request.
- Ask a question about the currently suggested person.
- Record open/pass for a suggestion.
- Load a match and its private thread.
- Send and receive a human message.
- Ask Connection Agent for coordination help when invited.

The operation contracts should define typed inputs, typed successful outputs, expected errors, authorization requirements, and idempotency behavior. Transport details such as HTTP, MCP, or an in-process call belong in adapters.

### 3.3 Replaceable adapters

Each external dependency has both a real and fake implementation:

| Boundary | Real implementation | Development implementation |
|---|---|---|
| Identity | Supabase phone OTP session | Fixture actor selected by the evaluation lab |
| Profiles and state | Supabase repositories | In-memory fixture repository |
| Candidate retrieval | Supabase pgvector | Fixture list or deterministic similarity table |
| Embedding compute | JacGrid job client executing our `connection-embedding` workload | Local Contract C harness / `MockJacGrid` invoking the same workload |
| LLM | Configured model through Jac/byLLM | Recorded response or deterministic stub where useful |
| Notifications | SMS provider | Captured notification outbox |
| Realtime messages | Supabase Realtime | In-memory event stream |

Fakes are not alternate product logic. They implement the same interfaces and make independent work possible.

## 4. Repository and worktree layout

Connection Agent now lives inside the shared `jac_ddp` repository. Its implementation is isolated from Phong's `platform/` and Luke/Santhos's `sandbox/` by directory ownership and accepted boundary contracts.

Current repository ownership:

```text
apps/connection-agent/src/contracts/     orchestration-owned internal contract
apps/connection-agent/src/core/          orchestration-owned product lifecycle
apps/connection-agent/src/adapters/      data and service integrations
apps/connection-agent/src/intelligence/  profile, retrieval, matching, and cards
apps/connection-agent/web/               first-party product experience
apps/connection-agent/supabase/          migrations, RLS, and local seed
apps/connection-agent/evals/             scenarios, rubrics, and reports
apps/connection-agent/tests/             owned and cross-objective tests
apps/connection-agent/docs/              product and objective documentation
workloads/connection-embedding/          immutable application-owned workload
```

The five active sessions and their exact writable paths are defined in [`docs/objectives/README.md`](objectives/README.md). Worktrees may be created as siblings of the main checkout with names chosen by the operator; names are not part of the architecture.

A branch alone does not isolate simultaneous local sessions because several sessions would still operate on the same checked-out files. Each active Codex session needs its own worktree and branch.

## 5. Foundation sequence — integration lead

Parallel work begins only after Specs F0–F4 are merged. F5 continues alongside the workstreams.

The implemented foundation and its current acceptance evidence are maintained in [`docs/specs/FOUNDATION_AND_PARALLEL_WORK.md`](specs/FOUNDATION_AND_PARALLEL_WORK.md), [`docs/specs/INTERNAL_CONTRACT_V1.md`](specs/INTERNAL_CONTRACT_V1.md), and [`docs/specs/WALKING_SKELETON.md`](specs/WALKING_SKELETON.md).

### F0 — Repository bootstrap

Create the Git repository, ignore generated artifacts and secrets, establish the proposed directory structure, document local prerequisites, and verify the existing Jac installation with one smoke command.

**Exit condition:** a clean baseline commit can be checked out in a new worktree and the documented smoke command succeeds.

### F1 — Domain and operation contracts

Define the shared representation of an authenticated actor, conversation/session event, profile proposal and approval, saved profile revision, embedding-compute request/result, candidate reference, pair assessment, recipient-specific card snapshot, suggestion, interest decision, match, thread, message, trace event, and application error. Define the application operations without binding them to HTTP or MCP. Record the JacGrid job contract and the application workload contract as separate versioned boundaries.

The contract must specify identifiers, revision identifiers, exact suggestion/interest states, error semantics, authorization expectations, retry/idempotency rules, and the mapping from application operations to agent/MCP tools. Only the integration lead changes `apps/connection-agent/src/contracts/` during parallel work, through a small reviewed contract commit that all dependent lanes incorporate before continuing.

**Exit condition:** each workstream can compile or validate fixtures against the same released contract version; unresolved behavior is recorded rather than guessed independently.

### F2 — Fake adapters and fixture people

Create a small in-memory implementation of identity, profiles, embedding compute, candidate retrieval, suggestions, matches, and messages. `MockJacGrid` must invoke the same application-owned workload package locally rather than contain a second embedding algorithm. Seed several contrasting Markdown profiles drawn from the product examples.

**Exit condition:** tests can act as two different fixture users without phone numbers or external services.

### F3 — Walking skeleton

Connect one minimal client or command to the application core. As a fixture user, request a person, receive a hardcoded but contract-valid card, express interest from two fixture users, create a match, and append one message.

**Exit condition:** the complete state transition works through shared operations, even though intelligence, persistence, and presentation are still fake.

### F4 — Parallel-work quality gate

Before branch fan-out, add formatting, contract validation, unit tests, and the minimal end-to-end fixture scenario to one repeatable command. Add migration checks as soon as P1 lands.

**Exit condition:** every new worktree can run the same fast pre-merge check before doing independent work.

### F5 — Integration environment

Provide one documented local configuration that connects the web client, Jac service, local Supabase, evaluation laboratory, and either `MockJacGrid` or a live JacGrid coordinator. Centralize environment-variable names and provide safe example values without secrets.

**Exit condition:** a newly created worktree can reach the integrated local application by following the repository instructions.

## 6. Core orchestration sequence — integration lead

The adapters and AI components do not become a product until a stateful core coordinates them. The integration lead owns this conflict-prone layer so no parallel strand independently invents the suggestion or match lifecycle.

### C1 — First-party conversation storage and profile-proposal lifecycle

Persist first-party conversation/session events so the owning person can return to their Connection Agent conversation and cards remain in history. Route profile-related turns through proposal, inspection, approval/edit, save, and rejection. External hosts retain their own transcript; Connection Agent persists only the profile proposals and product actions they invoke.

First-party raw turns are readable only by the owning person and the server-side agent serving that conversation. In V1 they are retained with the account for conversation continuity. Candidate retrieval, pair assessment, cards, and explanations may use only canonical Markdown revisions plus the explicit current-request snapshot—not unrelated or unapproved transcript history.

A current request passed in conversation is call/session context, not a separate persistent `Intent` entity. The matching call snapshots the request for reproducibility. If it should remain useful beyond that conversation, the agent proposes a dated addition to the canonical Markdown profile.

**Depends on:** F1–F4 and the profile repository interface.

**Exit condition:** one natural-language fixture conversation produces an understandable proposal, approval, and saved profile revision; negative tests prove unrelated raw transcript text is absent from matching inputs.

### C2 — Suggestion lifecycle

Create a canonical unordered pair identity plus persisted, recipient-specific suggestions. Each suggestion contains viewer, subject, pair/opportunity key, source profile revision IDs, current-request snapshot, pair-assessment reference, immutable card snapshot, and state. V1 states are `queued`, `active`, `open`, `passed`, `skipped`, `expired`, and `invalidated`; only one suggestion is active per viewer. Reversing user order resolves to the same pair identity.

When A opens a suggestion for B, the core privately prioritizes a separate, independently assessed and tailored suggestion for B about A. It does not reveal A's decision. If B already has an active suggestion, it is not displaced; the reciprocal opportunity remains queued for B's next appropriate “show me someone” request. A match occurs only if B sees their own card and independently opens it.

“Show me someone else” marks the prior active suggestion `skipped` rather than recording affirmative or negative consent. A `pass` closes the current opportunity and any pending open on that opportunity. `skipped` and `expired` suggestions may be reconsidered only after a new current request or material profile revision; `invalidated` requires reassessment; a block excludes the pair until explicitly removed.

The exact card already shown remains immutable in history. “Tell me more” may select additional relevant information from the person's canonical Markdown, as the product promises, but must record the profile revision used and remain grounded. If a relevant profile revision changes before a decision, the core revalidates or replaces the suggestion rather than treating stale reasoning as current.

**Depends on:** F1–F4; initially uses fixture pair assessments and repositories.

**Exit condition:** retries do not duplicate a suggestion; only one current person is conversationally active; prior cards remain intact; reversed user order shares one pair identity; A opening privately queues B's distinct card without displacing B's active card; and every terminal/reconsideration rule is tested.

### C3 — Atomic interest, match, and thread lifecycle

Keep each interest decision private. An `open` decision creates no user-visible reciprocity until the other person independently opens their linked recipient-specific suggestion. Passing, blocking, withdrawing, expiring, invalidating, or superseding an opportunity follows the C2 policy and cannot silently reuse a previous open. The transition from reciprocal open decisions to one match and one thread is an idempotent server-side transaction owned by Supabase, never two client writes.

**Depends on:** F1–F4; initially runs against the in-memory transaction boundary, then P3.

**Exit condition:** simultaneous opens, repeated requests, reversed user order, and network retries create exactly one match and one thread; A-open/B-pass and A-open/B-never-views create no match and never disclose A's interest.

### C4 — Conversation orchestration and agent capability adapter

Route first-party turns between the C1 profile lifecycle, C2 suggestion lifecycle, C3 decisions, explanation, and coordination. Expose these operations to the first-party Jac agent through the capability/tool mapping already released in F1. The adapter may invoke handlers in-process for speed and reliability, but its tool definitions and behavior are the same contract later exposed through remote MCP. Authentication, Realtime human chat, and browser navigation remain outside this agent tool layer.

**Depends on:** C1–C3 and the relevant implemented handlers.

**Exit condition:** the first-party agent completes the profile-to-suggestion loop exclusively through the released capability contract, and the same contract has transport-level tests ready for P7.

## 7. Workstream A — data, persistence, identity, and transports

### Ownership

This strand owns Supabase migrations and policies, concrete repositories, phone identity, human-message transport, notifications, the JacGrid service client, and the thin MCP adapter. It does not decide how embeddings are calculated, profiles are written, candidates are ranked, or cards are worded.

### Sequential specs

#### P1 — Core persistence schema

Create migrations for first-party agent sessions/events, profile proposals and approvals, versioned profiles, disposable derived profile search data, recipient-specific suggestions/card snapshots and follow-up disclosures, interest decisions, blocks, matches, threads, notification outbox entries, and messages. Add source revision IDs, canonical unordered pair/opportunity IDs, timestamps, state constraints, and uniqueness rules needed for idempotency.

There is no event-membership table, active/inactive profile flag, or private-vs-shareable profile split. All canonical Markdown is readable by the matching service and eligible for relevant selection. V1 deterministic exclusion is limited to authentication/system eligibility and explicit blocks; other natural-language constraints are evaluated reciprocally by the pair-assessment layer.

**Depends on:** F1.

**Exit condition:** migrations apply cleanly to a fresh local Supabase database and repository tests can create the complete fixture state.

#### P2 — Authorization and RLS

Implement an explicit role/action/table access matrix and its RLS policies. A person can manage their own profile and decisions; only matched participants can access a private thread; neither participant can directly read the other's phone number, canonical Markdown, derived search record, raw pair assessment, trace, or pending decision through client APIs. They may read only the recipient-specific cards and follow-up disclosures that the trusted matching service generated for them. Define trusted server-only access for matching and atomic match operations. Cover agent sessions, proposals, profile revisions, suggestions/card snapshots, follow-up disclosures, blocks, decisions, matches, threads, messages, notifications, search projections, assessments, and Realtime subscriptions.

**Depends on:** P1.

**Exit condition:** positive and negative tests cover every table/role, direct-ID guessing, unauthorized Realtime subscriptions, cross-user writes, raw-profile reads, hidden one-sided decisions, and third-party thread access.

#### P3 — Repository adapters

Implement the shared core repository interfaces against Supabase. Preserve the same behavior as the in-memory fakes. Make reciprocal-interest detection plus match/thread creation one atomic, idempotent server transaction.

**Depends on:** P1–P2 and F2.

**Exit condition:** the walking skeleton passes with Supabase adapters substituted for in-memory state, including simultaneous and retried open decisions producing exactly one match and one thread.

#### P3J — JacGrid compute adapter

Implement the released embedding-compute interface with `MockJacGrid` and `LiveJacGrid` adapters. Submission is server-side, authenticated, idempotent, and versioned. Polling, timeouts, retryable errors, result-invariant validation, job/result hashes, and compute receipts remain isolated inside this adapter. The browser never receives the JacGrid service credential or submits jobs directly.

The mock invokes the exact application-owned workload locally and emits realistic task-progress states. The live adapter uses the shared `docs/architecture.md` contracts and `docs/workload-ownership-decision.md` without knowing about workers or sandboxes.

**Depends on:** F1–F2. It may be built and tested against a mock coordinator while Phong implements the live platform.

**Exit condition:** identical fixture input produces contract-equivalent vectors through the local workload harness, `MockJacGrid`, and a recorded live-response fixture; duplicate submission creates one logical paid job; malformed or partial results are rejected before persistence.

#### P4 — Phone OTP and application actor

Implement first-party phone sign-in and translate a valid Supabase session into the transport-independent authenticated actor used by the core.

**Depends on:** P2–P3.

**Exit condition:** a real test phone flow reaches the same profile as subsequent sessions; core logic contains no phone-provider assumptions.

#### P5 — Realtime private chat

Implement persistent messages, realtime delivery, reconnection, and thread authorization. Keep human messages separate from agent utterances and coordination suggestions.

**Depends on:** P2–P3. It can use a seeded match before real matching exists.

**Exit condition:** two authenticated test sessions exchange messages and a third session cannot observe them.

#### P6 — Match and message notifications (post-demo extension)

Use the notification outbox created in P1 and add a delivery adapter. Begin with match notification and a deep link to the authenticated web thread; keep OTP delivery separate. A captured outbox and synthetic deep link are sufficient for the demo-ready milestone, so live delivery does not block the core loop.

**Depends on:** P4–P5.

**Exit condition:** production can send a configured notification while local/evaluation runs capture it without sending SMS.

#### P7 — Remote product MCP transport and authorization (post-demo extension)

Expose the C4 capability mapping as a product-specific remote MCP server. Keep product logic in the core and map remote authorization to the same product account identity. The data/integrations strand owns redirect URI registration, issuer/audience validation, scoped token validation, and separate development/test/production endpoints and credentials. Start with profile operations and showing/responding to a suggestion; direct human chat remains canonical in the web application.

**Depends on:** released F1 contracts, C4 transport tests, P3–P4, and the integrated intelligence operations.

**Exit condition:** an MCP test client completes the configured authorization flow, invalid issuer/audience/scope tokens fail, environment endpoints cannot be mixed, and the client can read/update the same profile used by the web app, request a suggestion, and receive a deep link for an accepted match.

## 8. Workstream B — Jac intelligence and matching

### Ownership

This strand owns conversational profile proposals, the application-supplied embedding workload, derived retrieval data, candidate construction and ranking, mutual-constraint evaluation, Jac traversal, pair reasoning, card content, explanation, and the minimal invited coordination suggestion. It does not own distributed scheduling, sandboxing, authentication, persistent human chat, or the web interface.

### Sequential specs

#### I1 — Intelligence fixtures and typed boundaries

Represent the agreed profile proposal, pair assessment, card content, and coordination suggestion as typed AI outputs. Establish deterministic recorded responses for non-LLM tests.

**Depends on:** F1–F2.

**Exit condition:** valid fixture outputs deserialize successfully and malformed or incomplete outputs fail clearly.

#### I2 — Conversational profile proposal

Given existing Markdown and a user utterance, propose a faithful Markdown update and at most the next useful clarification. The model must not silently save, invent facts, or turn the interaction into a questionnaire.

**Depends on:** I1.

**Exit condition:** profile-conversation scenarios produce inspectable proposals that preserve stable and dated information in the same document.

#### I3 — Derived search projection

Build and version the application-owned `connection-embedding` workload, including its Jac entrypoint, immutable manifest, exact model artifact/revision, dependency lock, input/output schemas, normalization, resource declaration, numeric tolerance, and deterministic fixtures. The workload contains no Supabase, scheduling, worker, payment, matching, or UI logic.

Generate an embedding and optional free-form facets from an identified canonical Markdown revision through the embedding-compute interface. Keep projections disposable and record the profile revision, workload ID/version, model artifact hash, index version, JacGrid job/result hash when applicable, and generation time that produced them.

An approved profile write creates a new canonical revision and marks its search projection pending. The refresh operation submits only approved or synthetic matching text and writes a ready projection for that exact revision after a complete, verified result passes application-side invariant validation. “Show me someone” may use only a ready projection matching the current profile revision; in the hackathon implementation it may synchronously refresh a missing/pending projection rather than introducing another background-job system. Candidate results are revision-checked before assessment so a stale index hit is refreshed or skipped.

**Depends on:** I1, P3J, and the finalized profile-revision/search-write contract from F1/P1. Workload implementation begins against the local Contract C harness and `MockJacGrid`; the live coordinator is not required.

**Exit condition:** the same fixtures produce contract-compatible vectors locally and through the compute abstraction; updating meaningful Markdown produces a ready projection for the same revision before matching proceeds; stale, partial, malformed, and failed compute states have explicit tests and user-safe retry behavior.

#### I4 — Candidate retrieval

Retrieve a bounded candidate list from embeddings or, for tiny datasets, a compatible fixture implementation. Exclude the current user, explicit blocks, system-ineligible users, and prior terminal/skipped suggestions according to the C2 lifecycle. Natural-language compatibility constraints remain input to reciprocal pair assessment rather than being mislabeled as deterministic database rules.

**Depends on:** I3 and the shared candidate contract.

**Exit condition:** retrieval scenarios consistently include expected plausible candidates and exclude deterministic ineligible ones.

#### I5 — Jac candidate topology and walker

Materialize the retrieved neighborhood as person nodes and candidate edges carrying retrieval evidence and source profile/search revision IDs. Carry the viewer's current request snapshot with the walker rather than persisting a separate intent object.

**Depends on:** I4.

**Exit condition:** the walker examines only the bounded candidate neighborhood and returns contract-valid evidence for considered candidates.

#### I6 — Reciprocal pair assessment

Use identified Markdown revisions from both people, the viewer's current-request snapshot, any dated context already in either profile, and explicit blocks/system rules to assess whether there is a believable reciprocal reason to meet. The other person need not have a separate active-intent record: their profile may express broad openness, while any request they later make is evaluated for their independently tailored card. Return evidence, uncertainty, and a neutral match hypothesis without claiming mutual interest.

**Depends on:** I5.

**Exit condition:** pair scenarios distinguish underlying social compatibility from superficial word overlap and return an honest no-suggestion result when necessary.

#### I7 — Viewer-specific card content and ASCII rendering

Select relevant facts for the viewer, generate neutral card content tied to both source profile revisions, and then render it separately as short mobile-safe ASCII. Do not dump the candidate's entire Markdown or invent unsupported claims. The core persists the rendered content as an immutable recipient-specific snapshot.

**Depends on:** I6.

**Exit condition:** the same candidate can receive different truthful emphasis for different viewers, and narrow-screen snapshot tests pass.

#### I8 — Follow-up explanation

Answer “tell me more” and “why this person?” using the current suggestion, identified profile revisions, and prior assessment. Continue as ordinary chat without regenerating or replacing the previous card. Persist the exact rendered follow-up as a recipient-specific disclosure with suggestion/pair ID and source profile revision IDs; later profile edits never rewrite what the viewer already saw.

**Depends on:** I6–I7.

**Exit condition:** explanations remain grounded, relevant, non-persuasive, and scoped to the person currently being discussed; only the intended recipient can read the immutable record; evaluation can trace every claim to the recorded source revision.

#### I9 — Coordination suggestion

After a mutual match and only when invited, suggest the smallest next logistical question or reflect already supplied availability. Do not impersonate a participant or commit either person without confirmation. V1 needs only one useful assisted turn; calendars, automatic booking, and prolonged mediation are outside the demo cut line.

**Depends on:** the integrated match/thread contract and I1.

**Exit condition:** scripted coordination scenarios reach an agreed suggestion without sending unauthorized human messages.

## 9. Workstream C — first-party conversational experience

### Ownership

This strand owns the mobile web/PWA presentation, first-party conversational shell, card display, profile review, interest actions, match transition, and direct human thread. It initially consumes fake operations and later switches to the real core.

### Sequential specs

#### U1 — Mobile conversation shell

Create the minimal responsive Jac client/PWA conversation view, message composer, loading/error states, and conversation history using the F1-released capability contract with fake handlers. C4 later supplies the real orchestration behind that unchanged contract.

**Depends on:** F1–F2.

**Exit condition:** the shell works on a narrow mobile viewport and clearly distinguishes user, Connection Agent, card, and system messages.

#### U2 — Development actor and production phone entry

Add a local-only fixture-persona selector and the production phone OTP screens behind the identity boundary. The fixture selector must be absent from production builds.

**Depends on:** the F2 fixture actor; production activation depends on P4.

**Exit condition:** the same UI can run as a fixture person locally and as a phone-authenticated actor in an integrated environment.

#### U3 — Profile conversation and approval

Connect conversation to profile proposals. Let the person inspect the complete Markdown, approve a proposed addition, edit it, and ask to see it later.

**Depends on:** U1 and the F1 profile operations; real intelligence depends on I2.

**Exit condition:** no new personal meaning is saved before an understandable approval action.

#### U4 — Suggested-person card in chat

Render one dynamic ASCII card as a chat message. Support asking for more, passing, expressing openness, and requesting another person without introducing a swipe screen.

**Depends on:** U1 and the suggestion contracts; real content depends on I7–I8.

**Exit condition:** the full interaction works with fixture cards and preserves the prior card in conversation history.

#### U5 — Mutual match transition

Show pending interest without implying reciprocity. When a mutual match exists, present a clear transition and deep link into the private thread.

**Depends on:** U4, C2–C3, and the atomic interest/match operation from P3 or its exact in-memory equivalent.

**Exit condition:** one-sided interest never appears as a match; reciprocal interest opens exactly one thread.

#### U6 — Direct human chat

Build the two-person thread, message history, realtime updates, reconnect behavior, and a visible distinction between the people and any summoned Connection Agent coordination assistance.

**Depends on:** U5; real transport depends on P5.

**Exit condition:** two users exchange messages on mobile, the introductory context remains accessible, Connection Agent does not speak as either person, and an explicit “help us coordinate” action can invoke the minimal I9 behavior.

#### U7 — Deep links, return states, and optional notifications

Handle authenticated direct match/thread links, returning users, expired sessions, and safe navigation to an authorized thread. Exercise these with synthetic notification links first; live match/message notification delivery is optional polish.

**Depends on:** P4–P5 and U6. Live-notification behavior additionally depends on P6.

**Exit condition:** a notification recipient reaches the intended thread after authentication without private content leaking into the URL or unauthenticated screen.

#### U8 — Hackathon polish and recovery states

Polish narrow-screen ASCII, loading time, retry states, no-credible-suggestion behavior, offline/reconnect messaging, and demo reset instructions.

**Depends on:** the integrated vertical loop.

**Exit condition:** the documented Hackathon Demo can be completed on two ordinary phones without developer intervention.

## 10. Workstream D — evaluation laboratory and quality

### Ownership

This strand owns fixture identities, personas, scenario definitions, the local test UI, deterministic invariants, qualitative rubrics, batch execution, trace inspection, and regression reports. It uses the real application core rather than recreating profile or matching behavior.

### Sequential specs

#### E1 — Scenario and persona format

Define a scenario format containing fixture people, canonical Markdown, dated context, starting state, conversation turns, expected invariants, and optional qualitative criteria. Every execution receives a unique `test_run_id` that tags all seeded database rows, traces, and notification-outbox entries.

**Depends on:** F1–F2.

**Exit condition:** one scenario can be run deterministically against the in-memory core and reset completely.

#### E2 — Local evaluation laboratory shell

Build a local-only interface that selects a scenario and actor, sends conversation turns, switches between people, resets state, and displays the user-facing experience. It connects only to a separate local/test Supabase environment or in-memory core, never to production data.

**Depends on:** E1 and the shared core operations.

**Exit condition:** a tester can simulate both sides of a match without a phone number or a second browser.

#### E3 — State and reasoning inspector

Display canonical Markdown, derived facets, retrieved candidates, constraint results, pair assessment, model/tool traces, shown cards, interest state, match state, notifications, and messages. Clearly label data that users would not see in production.

**Depends on:** E2 and initial intelligence trace contracts.

**Exit condition:** a failed suggestion can be localized to profile construction, retrieval, reasoning, rendering, or state transition.

#### E4 — Deterministic product invariants

Automate hard assertions: no self-suggestion, mutual constraints, no match before two positive decisions, idempotent match creation, authorized threads only, no phone disclosure, one next card at a time, and test-only routes absent from production.

**Depends on:** E1; expand continuously as data/integration operations land.

**Exit condition:** these invariants run without an LLM and block regressions.

#### E5 — Layered AI evaluation runner

Evaluate profile proposals, retrieval, pair assessment, card faithfulness, explanation quality, and conversational behavior separately. Record prompts, model identifiers, parameters, outputs, latency, token usage, and code/index versions.

**Depends on:** I1 and E1–E3.

**Exit condition:** a batch report identifies which layer changed rather than returning one opaque overall score.

#### E6 — Foundational scenario suite

Encode the product examples: science/education, watercolor/knitting with a social motive, dogs/biology, incompatible hard constraints, romance without appearance-first presentation, in-person versus online requirements, an expiring bike request, shared conference context, and an honest no-match case.

**Depends on:** E5 and the relevant intelligence layer.

**Exit condition:** each scenario has deterministic invariants, expected candidate behavior, and a small human-readable rubric.

#### E7 — Qualitative judging and human review

Add model-based judging only for subjective criteria such as faithfulness, invasiveness, neutrality, and strength of explanation. Keep source facts visible and allow a human to accept, reject, or annotate judgments.

**Depends on:** E5–E6.

**Exit condition:** qualitative judgments are reproducible enough to compare prompt/model changes and never override hard invariant failures.

#### E8 — Integrated and production-isolation tests

Run selected scenarios through local Supabase and the real web client. Seed clearly namespaced test identities for RLS testing without sending SMS, route all notifications to a captured sink, and require both a dedicated test-environment sentinel/attestation and a unique `test_run_id` before seeding or reset. Fail closed before mutation if either is missing or if the target is a production project URL or production-marked database. Reset may delete only rows carrying that run ID. Verify that fixture impersonation, inspectors, service credentials, test configuration, and reset controls are absent from production browser bundles and deployed routes, and that server APIs reject hand-crafted fixture actor headers/tokens.

**Depends on:** P2–P5, U2–U6, and E4.

**Exit condition:** the complete two-person flow passes through real persistence and realtime transport; production-isolation checks are automatic; run A cannot reset run B; non-fixture local data survives cleanup; and reset cannot connect to or target production.

## 11. Dependency and integration order

The runtime journey is sequential, but development uses fakes to remove unnecessary waiting:

```text
F0 -> F1 -> F2 -> F3 -> F4
       |                 |
       |                 +-- Core C1 -> C2 -> C3 -> C4
       +-------------------- Platform P1 -> P2 -> P3 -> P4/P5
       |                                  +-> P3J       +-> P6/P7 later
       +-------------------- Intelligence I1 -> I2
                                 P1 + P3J + I1 -> I3 -> I4 -> I5 -> I6 -> I7/I8 -> I9
       +-------------------- Experience U1 -> U2/U3/U4 -> U5 -> U6 -> U7 -> U8
       +-------------------- Evaluation E1 -> E2/E4 -> E3/E5 -> E6/E7 -> E8
```

The slash notation identifies specs that may overlap inside a workstream after their common prerequisite is stable. A single Codex session should still finish and commit coherent specs one at a time rather than editing several speculative implementations together.

Recommended integration milestones:

### M1 — Contract-valid fake loop

Fixture profiles, hardcoded suggestion, two interest decisions, one match, and one message through the application core.

### M2 — Real profile loop

In one continuous chat history, a natural user message receives one useful response, produces an understandable Markdown proposal, accepts an approval/edit action, saves the identified profile revision through the real repository, and obtains a ready derived search projection for that same revision through the compute abstraction. The evaluation lab can inspect and reset it. `MockJacGrid` is sufficient for this milestone.

### M3 — Real intelligence loop

From that same conversation, C4 routes “show me someone,” C2 snapshots the explicit current request, embeddings retrieve a bounded set, and I5 carries the snapshot through the Jac walker. The conversation displays a grounded card. “Tell me more,” pass/open, and “show me someone else” operate on the correct suggestion lifecycle, while evaluation traces explain the result.

### M3J — Live distributed-workload integration

Publish the immutable application-owned embedding workload, install it unchanged through the Luke/Santhos sandbox setup, and submit a real job through Phong's coordinator. Local harness, sandboxed fixture, and distributed execution produce contract-compatible vectors. Killing one worker triggers reassignment without duplicate items or payment, and the connection app validates and persists the complete verified result.

### M4 — Real two-sided suggestion, mutual match, and chat

A receives a tailored card for B and opens. Without learning A's decision, B later receives a separately assessed and tailored card for A. Each asks at least one grounded follow-up. The recorded cards and disclosures use the correct profile revisions and reveal neither unrelated transcript content nor the other person's pending decision. Independent opens create one persistent match, after which the two actors exchange realtime messages under RLS.

### M5 — Phone-authenticated hackathon loop

Two phone-authenticated people complete M2–M4 on ordinary phones, invoke one minimal coordination suggestion, and can return through an authenticated direct link. Live non-OTP SMS delivery is not required.

### M6 — Optional external-agent loop

An MCP client accesses the same account and application operations, while accepted human chat remains in the Connection Agent web thread.

## 12. How each Codex session should consume specs

Each numbered item above should become a focused implementation spec before coding. A spec should contain:

1. Outcome and user-visible behavior.
2. In-scope and explicitly out-of-scope work.
3. Contracts consumed and changed.
4. Files or directory ownership.
5. Persistence and authorization implications.
6. Deterministic acceptance tests.
7. Relevant evaluation scenarios.
8. Safe rollout or integration instructions.
9. Exit condition and evidence to report.

Within a worktree, Codex completes the strand's specs in order. It may begin the next spec after the prior spec is tested and committed. Avoid one enormous instruction such as “build the backend”; the numbered specs are designed to produce small reviewable commits and early integration evidence.

No implementation session should silently change a shared contract. It should stop at the boundary, propose the minimal contract change to the integration lead, and continue against the agreed revision. This avoids four locally reasonable but incompatible APIs.

## 13. Merge and synchronization rhythm

1. The integration lead publishes the tested F0–F4 foundation head.
2. Each workstream creates its worktree and branch from that commit.
3. A strand implements, tests, and commits one numbered spec.
4. The integration lead reviews the contract surface and merges the small increment.
5. The integrated fast checks and applicable scenarios run.
6. Every active worktree incorporates the new integration head before beginning work that depends on it.
7. The next spec begins.

Do not wait until each subsystem is “finished.” The product should remain vertically runnable at every milestone, with fakes replaced by real adapters incrementally.

Recommended directory ownership reduces conflict, but integration tests and shared contracts will still require coordination. The integration lead owns those conflict-prone surfaces. A workstream does not edit another lane's owned paths without an explicit handoff.

Shared contracts and schema migrations merge before the adapters that consume them. Supabase migrations are append-only after merge, use coordinated names/timestamps, and must apply successfully from an empty database as well as the current integration state. A workstream never rewrites another merged migration to resolve a local conflict.

Every Jac assessment, candidate edge, card, and explanation carries the profile/search revision IDs it used. Supabase remains the durable transaction boundary; Jac topology is disposable. The integration layer rejects or revalidates stale AI output rather than committing it against newer profile state.

## 14. Evaluation principles

Use deterministic assertions before model judgment. A model must not decide whether authorization, reciprocity, idempotency, or supported facts are correct when code can prove them.

Measure AI behavior by layer:

- **Profile construction:** faithfulness, no invented facts, useful brevity, no disguised questionnaire.
- **Retrieval:** expected candidates present, ineligible candidates absent, bounded candidate count.
- **Pair assessment:** underlying social purpose understood, mutual fit considered, weak evidence acknowledged.
- **Card:** grounded claims, viewer relevance, neutrality, mobile-safe rendering.
- **Explanation:** grounded expansion without persuasion or disclosure unrelated to the question.
- **Coordination:** asks the smallest useful question and never commits a person without confirmation.

Record enough context to reproduce a result: scenario version, canonical profiles, current date, prompt version, model configuration, retrieval/index version, code commit, structured outputs, latency, and token usage.

## 15. Critical safeguards

- Fixture actors and impersonation controls exist only in local/test builds.
- Evaluation uses a separately configured local/test Supabase project or database, clearly namespaced fixture identities, and a notification sink; it never receives production credentials or data.
- Startup and CI guards require a test-environment sentinel plus per-run ownership and refuse fixture/reset tools when the target is marked as or resolves to production.
- End-to-end RLS tests use isolated seeded identities and never require real SMS delivery.
- Service-role credentials never enter the browser.
- JacGrid service credentials never enter the browser; only the server-side adapter submits compute jobs.
- Distributed jobs contain only synthetic or explicitly approved matching text and opaque profile-revision IDs. Phone numbers, private messages, unapproved drafts, and unrelated Supabase data never enter worker payloads.
- The Luke/Santhos sandbox protects worker machines from workloads; it does not by itself make plaintext job inputs private from worker owners. Real private-profile distribution requires a later privacy design.
- One immutable application-owned embedding implementation is used by local, mock, worker, and verification paths; Phong and Luke/Santhos do not maintain competing algorithms.
- The matching AI may read everything in canonical Markdown but presents only a relevant subset.
- Full names appear on cards; phone numbers never do.
- One person's interest is not disclosed as a mutual match.
- A private thread exists only for the two matched users.
- MCP, web, and evaluation clients cannot bypass core authorization rules.
- Events remain dated profile context rather than a hidden membership system.

## 16. Readiness definitions

### Demo-ready

The hackathon product is demo-ready when:

- A new participant can authenticate and create understandable Markdown through conversation.
- The participant can inspect and approve what is saved.
- Retrieval and Jac reasoning produce a credible, grounded suggestion from real profiles.
- The application-owned embedding workload runs through the live JacGrid path, survives one worker failure, and returns a complete result that passes application-side invariant validation.
- Cards are readable on a phone and remain in conversation history.
- Both sides independently receive truthful explanations and can opt in or pass.
- Reciprocal interest creates exactly one authorized private thread.
- Realtime human messaging works on two phones.
- Either participant can explicitly request one grounded, non-committing coordination suggestion.
- The no-credible-suggestion path is honest.
- The evaluation lab can reproduce and reset the core two-person journey with fixture users.
- Deterministic authorization, reciprocity, idempotency, and production-isolation tests pass.
- Production builds contain no fixture impersonation or evaluation backdoors.

Live non-OTP notifications, the public MCP path, broad batch judging, and a polished reasoning inspector are not demo blockers.

### Evaluation-complete

The quality workstream is complete when the lab can inspect each profile/retrieval/reasoning/rendering/state layer, run the foundational scenario suite in batch, compare versioned results, support human review of qualitative judgments, and exercise the integrated local Supabase/web path without access to production.

### Extension-ready

The external-agent extension is ready when the remote MCP transport authenticates the same phone-owned account, exercises the same C4 capability contract as the first-party agent, and returns accepted matches to the canonical Connection Agent web thread.
