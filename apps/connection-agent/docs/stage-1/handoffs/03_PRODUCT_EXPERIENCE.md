# Stage 1 handoff: Showable Jac product experience

**Execution directive:** Implement this handoff end to end, following the
mandatory workflow linked below.

**Worktree:** `/Users/sebastian/dev/jac_ddp-product-experience`

**Branch:** `agent/product-experience`

**Push destination:** `origin/agent/product-experience`

## Goal

Build the responsive Jac first-party interface that lets a presenter complete
the entire Stage 1 two-person journey. It begins against a contract-shaped local
fixture handler and remains ready to connect to the integrated core façade
without changing product rules.

This is one thin Stage 1 specification spanning only the visible minimum of
U1–U6. Do not implement the production experience backlog.

## Required reading

- [`../../AGENT_WORKFLOW.md`](../../AGENT_WORKFLOW.md)
- [`../../JAC_NATIVE_ENGINEERING.md`](../../JAC_NATIVE_ENGINEERING.md)
- [`../../JAC_BACKEND_AND_JACHAMMER.md`](../../JAC_BACKEND_AND_JACHAMMER.md)
- [`../../STAGE_1_PRODUCT.md`](../../STAGE_1_PRODUCT.md)
- [`../../specs/INTERNAL_CONTRACT_V1.md`](../../specs/INTERNAL_CONTRACT_V1.md)
- [`../../specs/STAGE_1_OPERATION_CONTRACT.md`](../../specs/STAGE_1_OPERATION_CONTRACT.md)
- [`../../HACKATHON_DEMO.md`](../../HACKATHON_DEMO.md) for product language, not production requirements
- [`../../objectives/03_PRODUCT_EXPERIENCE.md`](../../objectives/03_PRODUCT_EXPERIENCE.md) as backlog context only
- Current installed/official `jac-client` guidance selected by the Jac reviewer

## Writable paths

```text
apps/connection-agent/web/
apps/connection-agent/tests/experience/
apps/connection-agent/docs/specs/stage-1/product-experience/
```

Everything else is read-only, including `src/contracts/`, `src/core/`,
`src/adapters/`, `src/backend/`, `src/intelligence/`, `evals/`, `workloads/`,
`platform/`, and `sandbox/`.

## Required deliverable

Build one clear mobile-first Jac experience with:

1. A local-demo label and fixture selector for Alice, Bob, and Carol.
2. A conversation-style history and composer shell with safe loading, empty,
   and retry states.
3. A readable, preapproved synthetic Markdown profile with an explicit “Use
   this demo profile” confirmation. Editing and persistence are not Stage 1.
4. A “show me someone” action and one immutable viewer-specific suggestion card
   with open and pass actions.
5. No visible reciprocity after Alice opens; persona switching must not leak her
   hidden decision.
6. A match transition only after Bob sees his distinct card and independently
   opens.
7. One private human-message thread with ordered messages and clear sender
   identity.
8. A reset action that restores the deterministic starting state.
9. A documented single command that starts the local interface without secrets.

Use the exact typed shapes and behavior in
[`STAGE_1_OPERATION_CONTRACT.md`](../../specs/STAGE_1_OPERATION_CONTRACT.md).
The fixture handler may use scripted, contract-valid operation responses while
this branch is isolated, but it must not implement
candidate ranking, consent, authorization, match creation, or messaging rules.
Those responses are replaced by the core façade during consolidation.

## Explicit deferrals

- Phone OTP and production identity.
- Durable Jac graph persistence, production auth, and WebSocket delivery.
- Separate devices, refresh persistence, offline recovery, and deep links.
- Live LLM/JacGrid requirements.
- Public MCP, notifications, coordination, and final production polish.

## Required review panel

- Current `jac-client` expert using installed/current guidance.
- Application-operation and integration-boundary reviewer.
- Mobile UX and accessibility specialist.

Create:

```text
apps/connection-agent/docs/specs/stage-1/product-experience/IMPLEMENTATION_SPEC.md
apps/connection-agent/docs/specs/stage-1/product-experience/HANDOFF_REPORT.md
```

## Acceptance

- The documented command starts the app from a clean worktree without external
  credentials.
- A presenter completes profile confirmation → suggestion → Alice open → Bob open →
  one match/thread → one message entirely through the interface.
- The primary flow is usable at approximately 390 px width and remains usable
  on desktop.
- No screen reveals a one-sided decision, raw embedding, hidden assessment,
  secret, or another actor's private data.
- Cards and messages remain visually distinct in conversation history.
- Basic keyboard focus, labels, contrast, loading, and error states are covered.
- The lane provides a deterministic component/browser smoke test and a
  `web/check.sh` hook that the root quality gate can call.
- `./apps/connection-agent/scripts/check.sh` passes.
- The authored client and server-call surface is Jac; generated JavaScript is
  build output, and any authored non-Jac exception is explicitly approved.

## Completion and handback

Complete both reviews, commit the implementation/spec/report, push with
`git push -u origin HEAD`, and stop. Do not merge to `main`. Return the final SHA,
demo command, and complete workflow evidence.
