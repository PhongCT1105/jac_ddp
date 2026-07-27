# Stage 1 handoff report: Evaluation and Quality

**Status:** Implemented and integrated

## Delivered

The reproducible `stage1-reciprocal-private-v1` scenario now validates the
complete frozen operation surface through Core's released `DemoApp` façade.
It covers reciprocal matching, one-sided privacy, original-result replay,
message idempotency, safe thread authorization, complete-pool recombination,
and reset/parallel-run isolation.

Run it with:

```bash
./apps/connection-agent/evals/check.sh
```

The successful report contains ten `PASS` lines and one safe summary. A failed
invariant returns nonzero without exposing exception bodies or private data.

## Changed paths

- `apps/connection-agent/evals/`
- `apps/connection-agent/tests/evals/`
- `apps/connection-agent/docs/specs/stage-1/evaluation-quality/`

Consolidation also updated the application-owned compute adapter/workload
boundary and Product Experience smoke expectations. Those decisions are
documented in `../INTEGRATION_REPORT.md`; no platform or sandbox source changed.

## Validation

| Command | Result |
|---|---|
| `jac fmt evals tests/evals --check` | passed |
| `jac check evals tests/evals --nowarn` | passed |
| `jac test -d tests/evals` | passed: 3 tests |
| `jac run evals/stage1_reciprocal_private.jac` | passed: 10 invariants |
| `./apps/connection-agent/web/check.sh` | passed: build and complete browser flow |
| workload tests | passed: 19 tests |
| application tests | passed: 31 tests |

## Review evidence

- Current-Jac/testing review identified the reserved `report` keyword,
  unguarded module entry, and optional-type narrowing requirements. All were
  corrected.
- Contract-boundary review returned READY after confirming the scenario uses
  only released operations and safe aggregate embedding evidence.
- Privacy/isolation review confirmed Core's prior blockers were fixed and
  required clean-control card comparison, stale Alice replay, missing-thread
  equivalence, and reset isolation. Those assertions are present.

All three final follow-up reviews returned READY. The contract reviewer also
reran the evaluator command independently; the Jac reviewer confirmed the
complete root gate, and the privacy reviewer verified every required
black-box privacy and isolation assertion. No reviewer edited implementation
files.

## Boundary confirmation

Evaluation imports no platform, worker, sandbox, provider client, lifecycle
storage, or raw compute implementation. It neither reads hidden decisions nor
counts internal chunks. All application behavior remains owned by its released
lane; Evaluation supplies assertions and reporting only.
