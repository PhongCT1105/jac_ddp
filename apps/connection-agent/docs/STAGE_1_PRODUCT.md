# Stage 1 product: showable local Connection Agent

**Status:** Ready for parallel implementation

## 1. Outcome

Stage 1 turns the implemented terminal walking skeleton into a coherent,
showable Jac product. It deliberately proves one complete user journey before
production services and hardening are allowed to become blockers.

A presenter can demonstrate:

1. Open the Jac web application at phone width.
2. Select Alice, Bob, or another synthetic demo persona.
3. Review and explicitly use a readable, preapproved synthetic Markdown profile.
4. Ask Connection Agent to show someone.
5. Receive one credible, viewer-specific suggested-person card.
6. Open or pass privately, then switch to the other persona.
7. Independently open from both sides and create exactly one match and thread.
8. Exchange at least one human message in that private thread.
9. Reset and repeat the demo without an external service or secret.

The complete journey must be reachable through released application operations,
not by writing state directly from the interface.

All branches implement the frozen
[`Stage 1 operation contract`](specs/STAGE_1_OPERATION_CONTRACT.md).
All implementation follows the mandatory
[`Jac-native engineering policy`](JAC_NATIVE_ENGINEERING.md).

## 2. What is real in Stage 1

- All authored application runtime logic is Jac unless the mandatory Jac
  reviewer approves a documented exception.
- The first-party interface is implemented with the current Jac client stack.
- The application-owned `connection-embedding` workload runs locally through
  `MockJacGrid` and processes the complete synthetic candidate pool.
- Candidate retrieval, private independent decisions, match/thread creation,
  authorization, message idempotency, and viewer-specific card identity are
  real product behavior.
- Profiles, cards, and people shown in the demo are synthetic and traceable to
  immutable fixture revisions.
- The same provider-neutral compute contract remains usable by local and live
  JacGrid adapters while Jac's own backend owns product state.

## 3. Deliberately constrained

Stage 1 uses fixture identity, in-memory state, deterministic or recorded AI
outputs, and local compute by default. It does not require:

- phone OTP or production accounts;
- durable Jac graph persistence, hosted authentication, or WebSockets;
- a live JacGrid coordinator or worker;
- a production embedding model or live LLM call;
- persistence after the demo process is reset;
- multiple browsers or devices;
- public MCP hosting, notifications, venue actions, or invited coordination;
- production deployment, offline recovery, or complete accessibility polish;
- the complete C1–C4, D1–D6, I1–I8, U1–U7, or E1–E7 backlog.

After Stage 1 is green, an optional live JacGrid adapter may be demonstrated
when Phong's endpoint is available. It is not an implementation-session
requirement and its absence cannot prevent the local Stage 1 demo.

## 4. Architecture cut

```text
Jac web demo
    -> released application operations
    -> in-memory fixture state and real core lifecycle
    -> Jac intelligence and recipient-specific cards
    -> EmbeddingCompute boundary
         -> MockJacGrid -> exact local connection-embedding workload (required)
         -> LiveJacGrid -> accepted JacGrid API (optional post-Stage-1 enhancement)
```

The interface may use a contract-shaped fixture client while lanes are being
built independently. During consolidation it is connected to the core handler;
matching, consent, authorization, and message rules are not duplicated in the
web folder.

## 5. Parallel deliverables

| Lane | Stage 1 deliverable | Handoff |
|---|---|---|
| Core | One stateful operation surface for the complete fixture journey | [`stage-1/handoffs/00_CORE.md`](stage-1/handoffs/00_CORE.md) |
| Data and Integrations | Fixture identity/profile access and a validated local `MockJacGrid` boundary | [`stage-1/handoffs/01_DATA_INTEGRATIONS.md`](stage-1/handoffs/01_DATA_INTEGRATIONS.md) |
| Intelligence and Workload | Credible data-driven retrieval and viewer-specific cards using the local workload | [`stage-1/handoffs/02_INTELLIGENCE_WORKLOAD.md`](stage-1/handoffs/02_INTELLIGENCE_WORKLOAD.md) |
| Product Experience | The responsive Jac interface for the entire demo journey | [`stage-1/handoffs/03_PRODUCT_EXPERIENCE.md`](stage-1/handoffs/03_PRODUCT_EXPERIENCE.md) |
| Evaluation and Quality | One reproducible two-person scenario, reset, and concise result | [`stage-1/handoffs/04_EVALUATION_QUALITY.md`](stage-1/handoffs/04_EVALUATION_QUALITY.md) |

Each lane delivers one reviewed Stage 1 spec. The numbered objective briefs are
not implemented during this stage unless a handoff explicitly incorporates a
small part of one.

## 6. Shared acceptance scenario

The consolidated Stage 1 is complete when, from a clean checkout and without
external credentials:

1. `./apps/connection-agent/scripts/check.sh --stage-1-integrated` passes,
   including the required Web and Evaluation lane hooks.
2. The documented demo command starts the Jac application.
3. Alice reviews and confirms use of her preapproved synthetic Markdown profile.
4. Alice requests a person; the exact local workload processes all eligible
   fixture profiles through `MockJacGrid`, and Bob is selected credibly.
5. Alice sees her immutable card about Bob and opens privately; no match is
   shown.
6. The presenter switches to Bob, who sees a distinct card about Alice and
   independently opens it.
7. Exactly one canonical match and one private thread appear.
8. Alice sends one human message and Bob reads exactly one copy.
9. Carol cannot read the hidden decisions, match, thread, or message.
10. Reset returns the demo to its starting state and the scenario can be
    repeated.

No raw embeddings, private one-sided decisions, secrets, or real personal data
are displayed or logged.

## 7. Integration and stopping rule

All five branches begin from the same green documentation baseline and work in
parallel. Sessions push their own branches and stop. They do not merge each
other or begin Stage 2.

The orchestration agent later consolidates in this order:

1. additive core contract and operation changes;
2. intelligence/workload and data adapter changes;
3. evaluation scenario;
4. product experience and final handler wiring;
5. integrated fixes owned by orchestration.

If time remains after the consolidated Stage 1 passes, the operator selects the
next smallest Stage 2 brief. Stage 1 is never made incomplete in order to begin
Stage 2.

After local consolidation, the conference release gate in
[`JAC_BACKEND_AND_JACHAMMER.md`](JAC_BACKEND_AND_JACHAMMER.md) hosts the
full-stack Jac application through JacHammer and verifies its actual sandbox
behavior before the demo.
