# Stage 1 implementation spec: Core operation surface

**Handoff:** `apps/connection-agent/docs/stage-1/handoffs/00_CORE.md`

**Branch:** `agent/orchestration-core`

**Baseline SHA:** `7f9f0cfa1f6c6ac395637f8126761c8eaac640c8`

**Jac version:** `jac 0.34.6 (Darwin arm64)`

**Jac MCP:** enabled and verified with `codex mcp list` and `jac mcp --inspect`

**Status:** Panel reviewed / Implemented

## Outcome and demo

Deliver one in-process `DemoApp` façade for the frozen Stage 1 operations. It
owns fixture-run state, delegates fixture profiles, embedding compute, retrieval,
assessment, and card generation through injected dependencies, and reuses the
released core lifecycle for private decisions, matching, threads, and messages.

Demo command: `./apps/connection-agent/scripts/run-demo.sh --mock`.

## Existing code to reuse

- `src/contracts/models.jac` released domain objects, extended only with
  additive operation result/dependency shapes as needed.
- `src/adapters/fixtures.jac` immutable synthetic profile source.
- `src/adapters/mock_jacgrid.jac` local invocation of the pinned workload.
- `src/intelligence/retrieval.jac` complete-pool deterministic retrieval.
- `src/intelligence/cards.jac` assessment and viewer-specific card functions.
- `src/core/lifecycle.jac` private-decision, canonical pair, match/thread, and
  message primitives.

## Design and files

- Add `src/core/demo_app.jac` as the sole façade. `DemoApp` owns suggestions,
  lifecycle state, and operation-scoped idempotency state. A fresh instance
  receives immutable fixture profiles plus compute and intelligence boundaries.
- Add `reset_demo()`/`new_demo_app()` construction helpers so reset returns no
  retained mutable state. Fixture identity selection returns only registered
  synthetic actors; it does not grant cross-actor access.
- `get_profile` verifies the actor is selected from this app's profile source
  before returning only that profile. `request_next_suggestion` computes the
  entire profile batch through the injected compute adapter, ranks through the
  injected intelligence boundary, and creates one viewer-owned immutable card.
- The façade scopes idempotency by actor and operation; it verifies full input
  equality before returning a prior suggestion, decision/result, or message.
  Reused keys with changed input fail with the frozen `idempotency_conflict`
  code. Active suggestions prevent a second non-retry request.
- `record_interest` checks ownership and active state, delegates the canonical
  pair/match/thread transition to `InMemoryLifecycle`, and changes the
  suggestion terminal state only after a valid decision. One-sided opens return
  no match and reveal no reverse state.
- Each returned suggestion includes additive `EmbeddingRetrievalEvidence` with
  lifecycle plus submitted, recombined-result, and eligible-candidate counts.
  It proves complete-batch recombination to evaluators without exposing vectors,
  profile text, hidden decisions, provider IDs, or adapter internals.
- `load_thread` maps absent and nonparticipant thread accesses to the same
  `thread_forbidden` failure. `send_message` validates membership before
  invoking the lifecycle primitive so direct-ID guessing remains non-disclosing.
- Add deterministic façade-only integration tests for the complete journey,
  reset, idempotency conflicts/retries, active-suggestion behavior, and Carol's
  read/write denial. The existing walking-skeleton CLI remains outside this
  handoff's writable paths; the integration suite is the façade demo.

The façade is in-process only and does not introduce a second embedding,
retrieval, card, or persistence implementation. Its dependencies are concrete
fixture fakes for Stage 1 and can be replaced by compatible adapters later.

## Internal implementation tasks

1. Add minimum additive contract result/dependency objects.
2. Implement `DemoApp` and the seven frozen operations in Jac.
3. Add deterministic integration coverage and run Jac checks.
4. Resolve panel findings, record implementation review, and hand back evidence.

## Tests and acceptance evidence

| Acceptance | Evidence |
|---|---|
| Profile to private reciprocal match/message journey | Integration test using only façade operations and mock workload |
| Duplicate operations create no records | Repeated suggestion/open/message assertions and lifecycle counts |
| Changed duplicate inputs conflict | Suggestion, interest, and message same-key negative tests |
| One-sided interest remains private | First open returns no match; no reverse decision operation exists |
| Third actor denied | Carol load/send tests assert `thread_forbidden` |
| Reset is isolated and repeatable | Reset/new app test replays fixture flow with empty lifecycle state |
| Foundation and quality gates | `jac fmt`, `jac check`, `jac test`, and `scripts/check.sh` |

## Risks and explicit non-goals

- The existing lifecycle raises stable-code exceptions; this narrow in-process
  façade preserves that convention while keeping messages safe. A future
  transport maps those errors to response envelopes.
- Fixture-only adapters are intentionally concrete; no production auth,
  persistence, remote transport, profile editing, reconsideration, realtime,
  or coordination flow is added.
- The frozen fixture source currently supplies the required 31 synthetic
  profiles; only eligible/profile-owned records are sent to computation.

## Jac-native implementation evidence

Resources consulted: `jac://guide/pitfalls`, `jac://guide/patterns`,
`jac://guide/jac-core-cheatsheet`, `jac://guide/jac-types`,
`jac://guide/jac-project-kinds`, and `jac://guide/jac-testing`.

Authored non-Jac source exceptions: none.

## Spec review record

| Reviewer role | Reviewer/task | Finding | Severity | Resolution |
|---|---|---|---|---|
| Current-Jac expert | `/root/spec_jac_review` | Façade/result shapes, actor/suggestion validation, injected boundaries, copies, and in-process Jac module design | Blocking | Implemented `DemoApp`, `InterestResult`, `ThreadView`, boundary objects, stored suggestion resolution, and clone helpers. |
| Architecture/boundary reviewer | `/root/spec_arch_review` | Idempotency must be operation/actor scoped; retries preserve original response; unknown/forbidden threads must be indistinguishable | Blocking | Stored façade responses/fingerprints; lifecycle now accepts internal scope; read/write call `safe_thread` before replay. |
| Lifecycle, authorization, idempotency specialist | `/root/spec_arch_review` | Validate requests, bidirectional blocks, active ownership, forged IDs, and non-disclosure | Important | Added validation, bidirectional candidate filtering, state ownership, and deterministic negative tests. |

### Spec review verdict

`/root/spec_jac_review` reviewed the Jac 0.34.6 design using the required MCP
guides and returned **ready**. `/root/spec_arch_review` reviewed the frozen
contracts and current source; its blocking findings above were incorporated
before implementation. The implemented acceptance evidence is sufficient for
the second panel review.

## Implementation review record

| Reviewer role | Reviewer/task | Finding | Severity | Resolution |
|---|---|---|---|---|
| Current-Jac expert | `/root/implementation_jac_review` | Missing required report/review evidence; compute boundary initially exposed the adapter directly | Blocking / Important | Added this evidence and report; `FixtureComputeBoundary.embed` now owns typed invocation. Focused re-review: ready. |
| Architecture/boundary reviewer | `/root/implementation_arch_review` | Missing required report/review evidence | Blocking | Added this report and recorded final checks. Runtime lifecycle/auth/idempotency review was ready. |
| Lifecycle, authorization, idempotency specialist | `/root/implementation_arch_review` | Scoped keys, immutable retry response, canonical match/thread, safe thread access, reset | Important | Confirmed conformant by reviewer and deterministic integration coverage. |
| Current-Jac expert | `/root/evaluation_jac_review` | Evaluation evidence initially exposed a provider job ID | Blocking | Removed the ID; additive evidence is aggregate-only. Focused re-review: ready. |
| Architecture/evaluation reviewer | `/root/evaluation_contract_review` | Verify all evaluation blockers and operation-namespaced idempotency | Important | Added complete-pool evidence and same-literal-key cross-operation regression; reviewer ready. |

### Implementation review verdict

`/root/implementation_arch_review` reviewed the finished behavior and returned
runtime **ready** after successful Jac format/check/test evidence; its only
blocker was the mandatory handoff artifact, resolved here.
`/root/implementation_jac_review` rechecked the behavioral boundary, format,
compiler, diff, and evidence after correction and returned **ready**. Final
gate reruns are recorded in the handoff report.
Evaluation follow-up reviewers `/root/evaluation_jac_review` and
`/root/evaluation_contract_review` both returned **ready** after the aggregate
evidence and operation-namespace regression were finalized.
