# Stage 1 handoff report: Core operation surface

**Branch:** `agent/orchestration-core`

**Baseline SHA:** `7f9f0cfa1f6c6ac395637f8126761c8eaac640c8`

**Implementation commit before this report:** `ef47d3bb832e0435977dec2cdf1db9b497d2dc33`

## Delivered

`DemoApp` is a stateful in-process façade for all frozen Stage 1 operations:
fixture selection/profile reads, injected profile/compute/intelligence
boundaries, viewer-private suggestions, idempotent open/pass, canonical
reciprocal match/thread creation, authorized thread loading, and idempotent
participant messages. The deterministic façade demo is:

```bash
cd apps/connection-agent && jac test -d tests -t "frozen facade operations complete the private fixture journey"
```

## Changed paths

- `apps/connection-agent/src/contracts/models.jac`
- `apps/connection-agent/src/core/lifecycle.jac`
- `apps/connection-agent/src/core/demo_app.jac`
- `apps/connection-agent/tests/integration/core_operations_tests.jac`
- `apps/connection-agent/docs/specs/stage-1/core/IMPLEMENTATION_SPEC.md`
- `apps/connection-agent/docs/specs/stage-1/core/HANDOFF_REPORT.md`

All changed paths are within the handoff's writable paths. No forbidden source,
adapter, intelligence, web, eval, workload, platform, or sandbox path changed.

## Validation

| Command | Result |
|---|---|
| `jac fmt --check src tests` | Passed |
| `jac check src tests --nowarn` | Passed |
| `jac test -d tests` | Passed: 10 tests |
| `./apps/connection-agent/scripts/check.sh` | Passed after final lint/check rerun; workload native-lowering notices are non-fatal pre-existing fallback notices |
| `./apps/connection-agent/scripts/run-demo.sh --mock` | Passed: existing foundation demo remains green |
| `git diff --check` | Passed |

## Review evidence

The implementation spec records both mandatory panels. `/root/spec_jac_review`
gave a Jac 0.34.6 **ready** design verdict after MCP guidance review.
`/root/spec_arch_review` identified scoped idempotency, immutable retry results,
safe thread non-disclosure, and lifecycle validation requirements; all were
implemented before code review. `/root/implementation_arch_review` found the
runtime implementation ready and required this report/evidence. 
`/root/implementation_jac_review` verified Jac-native source and requested a
behavioral compute boundary; Core now calls `FixtureComputeBoundary.embed`.
Evaluation follow-up review by `/root/evaluation_contract_review` was ready;
`/root/evaluation_jac_review` required removal of a provider job ID from the
new evidence and then returned ready after the aggregate-only correction.

## Jac-native evidence

Jac `0.34.6` and the enabled Jac MCP were verified. Used resources include
`jac-core-cheatsheet`, `jac-types`, `jac-project-kinds`, `jac-testing`,
`pitfalls`, `patterns`, and `jac-has-fields`. All authored runtime and test
logic is Jac. Approved non-Jac exceptions: none.

## Integration notes

The façade takes dependencies through `DemoApp(dependencies=...)`; the default
factory wires the released fixture profile source, `MockJacGrid`, and fixture
intelligence boundary. The compute dependency exposes `embed(items, key)`, so
future compatible fakes/adapters replace the boundary without moving lifecycle
rules out of Core. The contract additions are additive `InterestResult`,
`ThreadView`, and `EmbeddingRetrievalEvidence` response objects.

### Evaluation regression follow-up

Evaluation review findings were incorporated as Core regression input. The
façade retains actor/operation-scoped idempotency and stores the original
interest response, so Alice's retry after Bob opens still returns `match =
null`. Thread reads and writes call the shared safe authorization gate before
replay and use only `thread_forbidden` for absent or unauthorized threads.

`Suggestion.embedding_evidence` is an additive, safe contract observation for
the evaluator: lifecycle plus submitted-item, recombined-result, and
eligible-candidate counts. It demonstrates full-batch recombination before
whole-pool retrieval without returning profile Markdown, vectors, hidden
decisions, provider IDs, provider internals, or lifecycle implementation state.

## Deferred and known limitations

Only fixture identity and in-memory state are implemented. Profile editing,
production auth/persistence, remote/MCP transports, live compute, realtime,
and reconsideration remain explicitly deferred.

## Git confirmation

The assigned branch will be pushed without force. `main` is not changed or
merged by this session. Final commit SHA is reported to the operator after this
report is committed and pushed.
