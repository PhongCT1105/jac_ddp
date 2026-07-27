# Stage 1 implementation spec: Evaluation and Quality

**Scenario:** `stage1-reciprocal-private-v1`

**Status:** Implemented during Stage 1 consolidation

## Outcome

One deterministic, offline command exercises the released Stage 1 product
façade and reports whether the showable loop is correct:

```bash
./apps/connection-agent/evals/check.sh
```

The evaluator is a client of Core. It does not implement suggestions,
matching, authorization, idempotency, messaging, retrieval, or embedding.

## Released behavior used

The scenario creates isolated `DemoApp` instances and calls only:

- `reset_demo`
- `select_fixture_actor`
- `get_profile`
- `request_next_suggestion`
- `record_interest`
- `load_thread`
- `send_message`

Whole-pool behavior is proven only through the additive, safe
`EmbeddingRetrievalEvidence` returned on the suggestion: lifecycle states,
31 submitted items, 31 recombined results, and 30 eligible candidates. The
evaluator does not inspect chunks, vectors, provider IDs, or adapter state.

## Deterministic invariants

1. A reset instance selects only approved fixture actors/profiles.
2. Alice receives Bob after complete whole-pool recombination.
3. Alice's first open returns no match and remains private.
4. Bob's card is viewer-specific and identical to a clean-control run, proving
   Alice's private decision did not affect its content.
5. Bob's independent open returns one stable canonical match and thread.
6. Retrying Alice's original open after reciprocity still returns no match.
7. Retrying one Alice message returns the same message and Bob reads one copy.
8. Idempotency keys are isolated across actors and operations; changed input
   conflicts safely.
9. Carol and participants probing missing threads receive the same
   `thread_forbidden` result.
10. Reset and parallel app instances cannot observe each other's thread state.

## Safe report

The runner catches every exception without printing its text or traceback. It
emits only whitelisted invariant names, the fixed scenario ID, status, and the
three safe fixture IDs. A hostile-error regression test injects secret-,
profile-, vector-, decision-, provider-, and traceback-shaped text and proves
none appears in rendered output.

## Files

- `evals/stage1_reciprocal_private.jac` — scenario and safe report.
- `tests/evals/stage1_reciprocal_private_tests.jac` — success,
  reproducibility, and redaction tests.
- `evals/check.sh` — Jac format/check/test plus one CLI run.
- `evals/README.md` — operator command and scope.

## Jac-native implementation

The scenario, report, and tests are Jac. The POSIX check script contains only
toolchain orchestration. The module uses `with entry:__main__` so importing it
from tests cannot execute the CLI or exit the test process. Optional Core
response fields are explicitly narrowed before access.

## Review record

The initial review correctly blocked implementation on the earlier Core
baseline: no façade, stale-open privacy leakage, disclosing missing-thread
errors, globally scoped idempotency, and no safe whole-pool evidence. Core's
follow-up resolved all five before Evaluation resumed.

During final review, the Jac and privacy reviewers found a separate
consolidation failure: the accepted JacGrid merge released workload `1.0.0`
while the application adapter still expected `0.1.0`. Orchestration resolved
that in the application-owned adapter/workload boundary rather than inside the
evaluator. After that correction, the current-Jac/testing,
application-contract/boundary, and privacy/isolation reviewers all returned
READY. The validation evidence is recorded in the handoff report.

## Non-goals

No hosted auth/persistence, live JacGrid dependency, production data,
qualitative LLM judging, inspector UI, regression dashboard, or Stage 2/3
behavior is part of this evaluator.
