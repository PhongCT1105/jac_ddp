# Stage 1 implementation spec: Intelligence and Workload

**Handoff:** `docs/stage-1/handoffs/02_INTELLIGENCE_WORKLOAD.md`

**Branch:** `agent/intelligence-workload`

**Baseline SHA:** `7f9f0cfa1f6c6ac395637f8126761c8eaac640c8`

**Jac version:** `jac 0.34.6 (Darwin arm64)`

**Jac MCP:** enabled and verified with `codex mcp list` and `jac mcp --inspect`

**Status:** Implemented

## Outcome and demo

The intelligence lane will consume the unchanged `connection-embedding` 0.1.0
result, rank the complete recombined eligible profile pool deterministically,
create a canonical grounded reciprocal assessment, and return a separate
immutable card for either viewer. The implementation remains offline and uses
only approved synthetic Markdown plus an optional explicit request snapshot.

Demo: `./apps/connection-agent/scripts/run-demo.sh --mock`

## Existing code to reuse

- Released V1 Jac objects in `src/contracts/models.jac`; no contract edits.
- Immutable synthetic `ProfileRevision` fixtures and local `MockJacGrid`.
- The exact workload package at `workloads/connection-embedding/`, version
  `0.1.0`, invoked through its existing compute result contract.
- Foundation `rank_candidates`, `fixture_assessment`, and
  `fixture_suggestion`, extended in place rather than shadowed.

## Design and files

`src/intelligence/retrieval.jac` will add a compatible result-aware entrypoint
that consumes a completed `EmbeddingBatchResult` and requires the pinned
`0.1.0` workload/artifact identity. The adapter remains responsible for result
shape, chunk recombination, normalization, and completeness. Retrieval first
builds its visible eligible set (not self, eligible, no block in either
direction), then requires projections only for the viewer and that set. A
missing required projection raises exactly `embedding_not_ready`; an empty set
raises `no_eligible_candidate`. A missing projection for an already excluded
profile is ignored and never leaks state.

An explicit request is viewer-private. A non-empty request is passed unchanged
as one additional deterministic request item through the unchanged local
workload, which alone performs token normalization; its returned vector is
passed into the result-aware retrieval entrypoint. The request item ID is
opaque and distinct from revision IDs. Candidate score is `cosine(profile, candidate) +
0.20 * max(0, cosine(request, candidate))` when a non-empty request is
present; otherwise it is cosine alone. Ordering is total:
`(-score, actor_id, profile_revision_id)`. The complete eligible profile pool
is always ranked; the request is never a candidate or a profile projection.

`src/intelligence/cards.jac` will derive a profile-only canonical assessment
from a fixed, bounded theme catalog. Every canonical evidence item has a
private `EvidenceProvenance` record proving that its exact normalized theme
appears in both approved profiles. A viewer card derives fresh reason strings
and a fresh list from that assessment. The viewer's own request may add one
directional reason only when its theme appears in the subject's profile; the
raw request and any other actor's request never appear in assessment or card
text. Headlines are at most 88 characters, cards contain at most two reasons,
and each reason is at most 120 characters.

`GroundedAssessment` and `CardProvenance` are lane-private Jac objects: they
hold both exact revision IDs, request-item identity (when any), workload
version/artifact/result hash, and evidence support. They wrap rather than
alter released contract objects. Their deterministic opaque card IDs include
viewer/subject revisions and workload/result identity while canonical `pair_id`
remains actor-only. This proves transient intelligence provenance now, but the
frozen Core `Suggestion` cannot persist the full envelope; an additive Core
contract request is recorded for consolidation. Grounding validator outcomes
are private test failures (`ungrounded_evidence` / `no_grounded_evidence`),
not client-visible Stage 1 errors or contract changes.

`tests/intelligence/` will execute the real local workload through
`MockJacGrid` before retrieval. Tests prove the 31 result keys returned after
four chunks are consumed by whole-pool retrieval, strict ties independent of
input order, both block directions, exclusion-before-vector-check behavior,
missing required vectors, no candidates, reciprocal identity,
request-sensitive contrast, provenance, separate card/reason instances, and
grounding rejection (unsupported, one-sided, wrong revision, and
viewer-only-request claims). No test makes a network or LLM call.

The workload package is inspected and exercised unchanged: no `0.1.0` model,
schema, package, or artifact identity is rewritten.

## Internal implementation tasks

1. Add deterministic retrieval validation, bilateral exclusions, request-aware
   scoring, and total ordering.
2. Replace pair-specific card fixtures with grounded deterministic reciprocal
   assessment and viewer-card construction while preserving released shapes.
3. Add Jac intelligence tests running the existing local workload adapter.
4. Run Jac format/check/test and the repository quality gate; record reviews.

## Tests and acceptance evidence

| Acceptance | Evidence |
|---|---|
| 30+ eligible profiles after chunk recombination | real `MockJacGrid` chunk test asserts four invocations, all 31 profile vectors, and 30 Alice candidates |
| Alice/Bob grounded, reciprocal, distinct | assessment/card test checks one pair ID, exact revision/workload provenance, different isolated cards, and supported reasons |
| contrasting request changes result/evidence | request item is run through 0.1.0 and changes Alice's deterministic top result or directional evidence |
| exclusions do not leak | self, each bilateral-block direction, ineligible, excluded-missing, and required-missing projection tests |
| unsupported evidence fails | private validator tests for unsupported, one-sided, stale revision, and viewer-only request claims |
| stable offline output/identity | repeat, reversed-input tie, source/workload/result identity assertions |
| foundation and root checks | `jac test` lane tests and `scripts/check.sh` |

## Risks and explicit non-goals

The fixture embedding is intentionally small and lexical, so Stage 1 uses a
bounded grounded-theme catalog instead of claiming semantic model reasoning.
Live LLMs, production embedding artifacts/indexes, graph topology, and
open-ended explanations remain deferred. Core must later add provenance fields
to persist full card provenance; this branch does not alter its frozen types or
operations.

## Jac-native implementation evidence

Jac MCP resources to consult: `jac-core-cheatsheet`, `jac-types`,
`jac-project-kinds`, `jac-testing`, and `jac-native`. Authored runtime and
tests are Jac. Authored non-Jac source exceptions: none; Markdown documents
are native-format artifacts.

## Spec review record

| Reviewer role | Reviewer/task | Finding | Severity | Resolution |
|---|---|---|---|---|
| Current-Jac expert | `/root/jac_spec_review` | Released error mismatch; profile/request provenance and privacy unspecified; bilateral block absent | Blocking | Exact released error, private provenance envelope, profile-only canonical evidence, and bilateral tests added above |
| Application-contract/privacy/JacGrid boundary | `/root/boundary_spec_review` | Frozen errors/provenance conflict; request visibility and result identity incomplete | Blocking | Private validator/envelope, explicit Core request, viewer-private request scope, result-aware entrypoint added above |
| Retrieval, grounding, and evaluation | `/root/retrieval_spec_review` | Full-pool proof, total ties, complete exclusions, fresh card lists, and grounding negatives incomplete | Blocking | Exact score/order, comprehensive test matrix, fresh snapshots and provenance added above |

### Spec review verdict

All blocking findings were resolved. `/root/jac_spec_review`,
`/root/boundary_spec_review`, and `/root/retrieval_spec_review` each returned
`ready` on the revised design.

## Implementation review record

| Reviewer role | Reviewer/task | Finding | Severity | Resolution |
|---|---|---|---|---|
| Current-Jac expert | `/root/jac_spec_review` | Required report, actor identity, mobile limits, grounding and result-negative coverage | Blocking then resolved | Added report deliverable, actor validation, capped copy, and deterministic negative tests; final verdict ready |
| Application-contract/privacy/JacGrid boundary | `/root/boundary_spec_review` | Request vector provenance was not tied to a verified result | Blocking then resolved | Result-aware retrieval now validates completed pinned request result/item; private provenance records request result hash |
| Retrieval, grounding, and evaluation | `/root/retrieval_spec_review` | Reverse assessment canonicality and request contrast were incomplete | Blocking then resolved | Canonical assessment ordering and reverse test added; same-pair request/no-request evidence test added |

### Implementation review verdict

Final implementation review: all three mandatory roles returned `ready` after
the corrections. Jac reviewer reran `jac fmt src tests --check`,
`jac check src tests --nowarn`, and `jac test -d tests` (17 tests passed).
The full root quality gate also passed (7 workload tests and 17 application
tests). Current-Jac reviewer used Jac 0.34.6 and the required MCP guides.
