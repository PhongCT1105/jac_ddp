# Objective 04: Evaluation and Quality

> **Stage 2/3 backlog:** For the current showable product, implement only
> [`../stage-1/handoffs/04_EVALUATION_QUALITY.md`](../stage-1/handoffs/04_EVALUATION_QUALITY.md).
> Do not run E1–E7 as a sequential Stage 1 queue.

**Session:** Implementation agent 4

**Goal:** Build a reproducible evaluation laboratory that exercises the real application core, identifies failures by layer, and proves fixture tooling cannot affect production.

## Writable paths

```text
apps/connection-agent/evals/
apps/connection-agent/tests/evals/
```

## Read-only paths

All implementation folders outside the two paths above are read-only. File defects against the owning objective; do not reproduce or patch its product logic inside the evaluation harness.

## Ordered specs

### E1 — Scenario and persona format

Define synthetic fixture people, canonical Markdown, dated context, starting state, conversation turns, expected invariants, optional qualitative criteria, and a unique `test_run_id`.

**Acceptance:** foundation fixtures migrate without using real identities or production data.

### E2 — Local laboratory shell

Run selected scenarios through released operations with fixture identity, fake repositories, `MockJacGrid`, recorded LLM responses, and captured notifications.

**Acceptance:** a scenario can be run, inspected, and reset independently without external services.

### E3 — Layered inspector

Expose approved profile revisions, compute lifecycle, retrieved candidates, assessment evidence, card snapshots, state transitions, and errors while respecting the selected fixture actor's authorization.

**Acceptance:** a failure can be assigned to profile, compute, retrieval, reasoning, rendering, or state without reading unrelated private data.

### E4 — Deterministic invariants

Automate self/block/ineligible exclusion, complete-pool retrieval, private one-sided interest, one match/thread, message idempotency, revision traceability, and unauthorized access checks.

**Acceptance:** deliberately breaking each invariant makes the suite fail for the expected stable code.

### E5 — Layered AI evaluation

Add versioned datasets and rubrics for profile faithfulness, reciprocal fit, grounding, card usefulness, and coordination quality. Keep deterministic product correctness separate from model judgment.

**Acceptance:** results record prompt/model/workload versions and support human review rather than treating one model score as truth.

### E6 — Integrated isolation tests

Run selected scenarios against an isolated local/test Jac backend and the real web client. Require both a test-environment sentinel and unique `test_run_id`; scope reset strictly to that run; capture notifications.

**Acceptance:** production URLs/markers fail closed, run A cannot reset run B, non-fixture local data survives, and production bundles expose no fixture impersonation or reset controls.

### E7 — Regression reporting

Produce concise versioned reports comparing scenario outcomes and qualitative results across application, prompt, model, and workload revisions.

**Acceptance:** regressions link to the failing layer and reproducible scenario without containing secrets or real private profile text.

## Required checks

- Deterministic invariant suite.
- Fixture ownership/reset isolation suite.
- Production artifact negative checks.
- Recorded AI evaluation suite plus human-review output.
- Root application check remains green.

## Done

This objective is complete when the full two-person journey is reproducible through fakes and local integration, failures are inspectable by layer, and automated guards prove evaluation tooling cannot target production.
