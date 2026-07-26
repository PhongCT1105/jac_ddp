# Stage 1 implementation spec: data integrations

**Handoff:** `apps/connection-agent/docs/stage-1/handoffs/01_DATA_INTEGRATIONS.md`

**Branch:** `agent/data-integrations`

**Baseline SHA:** `7f9f0cfa1f6c6ac395637f8126761c8eaac640c8`

**Jac version:** `jac 0.34.6 (Darwin arm64)`

**Jac MCP:** verified (`codex mcp list`; `jac mcp --inspect`)

**Status:** Implemented

## Outcome and demo

The local fixture boundary explicitly selects only approved synthetic actors and
returns fresh defensive values for each Core-owned demo instance and lookup.
The released `obj` records are mutable, so the Stage 1 guarantee is
copy-on-read mutation isolation rather than externally immutable objects.
Actor-scoped lookup returns only the selected actor's approved revision.
`MockJacGrid` remains the default local compute adapter, invokes the
pinned `workloads/connection-embedding` harness for every chunk, validates and
combines every result before returning one complete batch.

Demo and quality gate: `./apps/connection-agent/scripts/run-demo.sh --mock` and
`./apps/connection-agent/scripts/check.sh`.

## Existing code to reuse

- Released V1 records in `src/contracts/models.jac` (read-only).
- Existing synthetic fixtures and `MockJacGrid` in `src/adapters/`.
- The immutable `workloads/connection-embedding` package and its `0.1.0`
  contract.
- Core's `InMemoryLifecycle`, which remains the sole owner of mutable demo
  lifecycle/reset state.

## Design and files

- Extend `src/adapters/fixtures.jac` with an explicit `FixtureSource` local
  identity/profile boundary. Its private blueprint is never returned directly:
  `select_fixture_actor(actor_id) -> Actor` and
  `get_selected_profile(actor: Actor) -> ProfileRevision` construct fresh
  records, including fresh nested blocked-ID lists, for every call. The profile
  lookup requires `actor.fixture is True` and a known fixture identity;
  unknown or non-fixture actor failures are
  `ValueError("fixture_actor_not_found")`. There is no client-facing
  arbitrary-actor profile lookup.
- Keep `fixture_profiles` and `find_profile` as compatibility helpers for the
  released walking skeleton. They return no shared mutable fixture collection.
- Tighten `src/adapters/mock_jacgrid.jac` at the provider boundary. A trusted
  `workload.json` descriptor supplies workload id/version and pinned model
  id/revision/artifact hash; the existing workload does not publish a separate
  package-release hash, so the released result field retains the manifest's
  model artifact hash and this limitation is recorded. A pure
  `validate_workload_result` seam validates each chunk's exact ordered IDs,
  model identity, dimensions, non-boolean finite components, and L2
  normalization against manifest tolerance. It rejects invalid chunk size and
  malformed/duplicate/extra/cross-chunk result IDs. Aggregate hashing uses
  canonical submitted-ID order and vectors, independent of chunking/output
  formatting. The subprocess boundary translates failures to a safe stable
  `embedding_failed` code without echoing stderr, text, vectors, or stacks.
  It invokes the exact local harness once per chunk.
- Add Jac-only tests under `tests/data_integrations/` for identity selection,
  actor-scoped positive/negative lookup, same-source and cross-source mutation
  isolation (including nested lists), chunked complete real-workload execution,
  safe process-error translation, and pure malformed-output rejection. Every
  test creates fresh source/mock state and unique keys for xdist isolation. No
  contract or Core files change.

No additive contract is required: `Actor`, `ProfileRevision`, `EmbeddingItem`,
and `EmbeddingBatchResult` already express this adapter surface.

## Internal implementation tasks

1. Add the fixture source and safe scoped-lookup errors while preserving
   released helper behavior.
2. Harden MockJacGrid boundary validation and deterministic aggregation.
3. Add deterministic adapter tests and run formatter/checker/tests.
4. Run the required implementation review, document findings, commit, push,
   then write and commit the handoff report.

## Tests and acceptance evidence

| Acceptance criterion | Evidence |
|---|---|
| Unknown/non-fixture actor fails safely | fixture identity negative tests |
| Actor-scoped lookup positive and negative | scoped profile tests |
| Fresh starting data without leakage | same- and cross-source mutation-isolation test |
| Exact workload chunks and complete result | MockJacGrid integration test asserts chunk count, states, vectors, manifest identity, and canonical aggregate |
| Provider result safety | pure validation tests cover ordered IDs, partial/extra/duplicate/cross-chunk IDs, model mismatch, dimensions, finite numeric values, normalization, and safe process failure |
| Foundation and full check remain green | `jac test` plus `scripts/check.sh` |

## Risks and explicit non-goals

Mutable nested Jac/Python objects can leak if returned directly; every source
read defensively builds a new record and list. Workload subprocess output is
untyped at the adapter boundary, so a pure validator checks it before it enters
a typed result. There is no package-release hash in the immutable workload
manifest, so a separate package artifact assertion is deferred to its future
contract release; current validation uses its pinned manifest/model identity.
Durable graphs, real identity, live JacGrid networking, retries, credentials,
suggestions, decisions, matches, threads, messages, and reset ownership are
explicitly deferred.

## Jac-native implementation evidence

Consulted Jac MCP resources: `jac-core-cheatsheet`, `jac-types`,
`jac-project-kinds`, `jac-testing`, `pitfalls`, `patterns`, and the Jac &
Jaseci knowledge map. Authored non-Jac runtime source: none.

## Spec review record

| Reviewer role | Reviewer/task | Finding | Severity | Resolution |
|---|---|---|---|---|
| Current-Jac interoperability | `/root/jac_spec_review` | Mutable records require copy-on-read; validate manifest/model identity rather than an unavailable package hash; add a pure validator seam | Blocking | Added fresh-return semantics, manifest descriptor validation, canonical hashing, and pure validator tests |
| Application-contract/provider boundary | `/root/boundary_spec_review` | Require ordered per-chunk IDs and safe subprocess error translation | Blocking | Added exact ordered-ID checks and `embedding_failed` translation with no stderr/text exposure |
| Repository authorization/test isolation | `/root/isolation_spec_review` | Same-source nested mutation and malformed-output tests were not explicit | Blocking | Added defensive-copy and xdist-isolated pure-validator tests |

### Spec review verdict

All three reviewers are ready after the documented corrections. Jac reviewer
`/root/jac_spec_review` used Jac 0.34.6 MCP resources: knowledge map,
`pitfalls`, `patterns`, `jac-types`, `jac-testing`, and
`jac-python-interop`; its initial blocking verdict is resolved by this revised
design.

## Implementation review record

| Reviewer role | Reviewer/task | Finding | Severity | Resolution |
|---|---|---|---|---|
| Current-Jac interoperability | `/root/jac_spec_review` | Initial implementation review noted test-evidence gaps and descriptor pinning opportunities | Important | Added partial/extra/nonfinite coverage and strict manifest contract/version/entrypoint/normalization checks |
| Application-contract/provider boundary | `/root/boundary_spec_review` | Required exact `connection-embedding@0.1.0` and non-empty idempotency key | Blocking | Enforced pinned manifest id/version/entrypoint/model constraints, finite bounded tolerance, and `invalid_request` for blank keys |
| Repository authorization/test isolation | `/root/isolation_spec_review` | Required final workflow artifacts; noted Actor identity is ID-based rather than provenance-secure | Important | This spec/report complete the artifacts; wording now states the actual selected-ID boundary guarantee |

### Implementation review verdict

`/root/jac_spec_review`: ready after final diff review; Jac 0.34.6 compiler,
lane tests, and full quality gate passed. `/root/boundary_spec_review`: initial
blocking final finding was resolved by strict v0.1.0 manifest pinning and the
empty-key guard. `/root/isolation_spec_review`: ready once this required report
is created; it found no code/test-isolation blocker. Affected Jac checks were
rerun after corrections.
