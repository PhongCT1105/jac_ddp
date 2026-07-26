# Stage 1 handoff report: Intelligence and Workload

**Branch:** `agent/intelligence-workload`

**Baseline SHA:** `7f9f0cfa1f6c6ac395637f8126761c8eaac640c8`

**Implementation commit before this report:** `6eab484e0664dab2f9c33b135ffc7b7aa3a18fbb`

## Delivered

The Jac-native intelligence pipeline now consumes completed, pinned
`connection-embedding` 0.1.0 results, ranks the complete eligible fixture pool
with stable ties and bilateral exclusions, and supports a separately verified
viewer-private request embedding. It builds canonical profile-grounded pair
assessments plus isolated viewer-specific cards with bounded mobile copy and
private provenance for exact revisions, workload/result identities, and any
request result.

Demo: `./apps/connection-agent/scripts/run-demo.sh --mock`

## Changed paths

- `apps/connection-agent/src/intelligence/cards.jac`
- `apps/connection-agent/src/intelligence/retrieval.jac`
- `apps/connection-agent/tests/intelligence/intelligence_tests.jac`
- `apps/connection-agent/docs/specs/stage-1/intelligence-workload/`

All changed paths are handoff-owned. No contracts, core, adapters, workload,
web, evals, platform, or sandbox files were modified.

## Validation

| Command | Result |
|---|---|
| `jac fmt src tests --check` | passed |
| `jac check src tests --nowarn` | passed (10 checked files) |
| `jac test -d tests` | passed (17 application tests) |
| `./apps/connection-agent/scripts/check.sh` | passed (7 workload + 17 application tests and Jac-native policy) |
| `./apps/connection-agent/scripts/run-demo.sh --mock` | passed: 31 profiles, 30 candidates, Bob selected, private open/match/thread/message flow |
| `git diff --check` | passed before handoff |

## Review evidence

The implementation spec is [IMPLEMENTATION_SPEC.md](IMPLEMENTATION_SPEC.md).
The mandatory spec and implementation panels used:

- Current-Jac: `/root/jac_spec_review` — ready after Jac MCP review and final
  compiler/test verification.
- Application-contract/privacy/JacGrid boundary:
  `/root/boundary_spec_review` — ready after request-result provenance was
  bound to a completed pinned result.
- Retrieval/grounding/evaluation: `/root/retrieval_spec_review` — ready after
  canonical reversal, request/no-request contrast, and one-sided evidence
  coverage were added.

All material review findings and resolutions are recorded in the implementation
spec.

## Jac-native evidence

Jac version: `jac 0.34.6 (Darwin arm64)`. The Jac MCP was enabled and used;
the session consulted the knowledge map plus `pitfalls`, `patterns`,
`jac-core-cheatsheet`, `jac-types`, `jac-project-kinds`, `jac-testing`, and
`jac-native`. Application logic and tests are authored in Jac. Approved
non-Jac runtime exceptions: none.

## Integration notes

No frozen contract changes are included. Consolidation should add a Core-owned
provenance envelope to persist both viewer/subject revision IDs and workload,
profile-result, and request-result identities alongside immutable suggestions
and cards. The currently read-only foundation demo continues to invoke the
legacy vector-map wrapper; consolidation should wire its released operation to
`rank_candidates_from_result` and pass the verified request result/item and
private card provenance.

## Deferred and known limitations

Live LLMs, production embedding artifacts/vector indexes, persistent graph
provenance, and open-ended explanations remain Stage 2/3 work. The fixture
model uses a bounded grounded-theme catalog; it makes no production semantic
model claim.

## Git confirmation

This branch will be pushed with `git push -u origin HEAD` without force. No
merge to `main` is performed by this session. The final branch SHA is reported
after this report is committed and pushed.
