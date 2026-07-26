# Stage 1 handoff report: Product Experience

**Branch:** `agent/product-experience`

**Baseline SHA:** `7f9f0cfa1f6c6ac395637f8126761c8eaac640c8`

**Implementation commit:** `464e88e358ab029aeb953267b0d688dec236ef48`

**Remote:** `origin/agent/product-experience`

## Delivered

Implemented the complete showable Stage 1 Jac experience: explicit synthetic
profile confirmation, Alice's private viewer-specific open, persona-safe switch
to Bob, Bob's distinct suggestion and independent open, the Core-returned
match/thread transition, one ordered private message, deterministic reset, and
safe loading/error/retry states. Safe profile and card items remain in each
persona's conversation history. The local command is:

```bash
./apps/connection-agent/web/start.sh
```

## Boundary correction

The released Core types and semantics remain intact. The Jac 0.34.6 browser
client could not hydrate returned `ProfileRevision` and nested `Suggestion`
archetypes, and importing the shared server type module into `cl` caused
server/wasm code to enter the browser build. The final boundary keeps canonical
types on the server, delegates every operation to released Core `DemoApp`, and
serializes exact-field JSON records only at the endpoint return. Unit and browser
regressions prove both typed shapes reach and render in the client.

The branch was fast-forwarded from baseline to owner-reviewed Core commit
`80f685a` before applying the Product Experience diff. Those Core/contract
changes are unchanged owner history, not Product Experience edits.

## Authorized configuration

The focused `jac.toml` change was explicitly authorized. It changes the project
from `cli`/`src/main.jac` to `web-app`/`main.jac` and adds only Jac's standard
React/Vite client dependency set listed exactly in `IMPLEMENTATION_SPEC.md`.
The root `main.jac` is a minimal Jac entry shim for the Jac 0.34.6 nested-entry
output path and contains no product logic. `jac build --client web` succeeds and
emits the client bundle under `.jac/client/dist/`.

## Validation

| Command | Result |
|---|---|
| `jac fmt main.jac web tests/experience --check` | Passed |
| `jac check main.jac web tests/experience --nowarn` | Passed |
| `jac test -d tests/experience` | Passed; wire shape, privacy, Core lifecycle, idempotency, authorization, reset |
| `jac build --client web` | Passed; hashed client bundle emitted |
| `./apps/connection-agent/web/check.sh` | Passed; mandatory 390×844 Alice → Bob flow, hydration, focus, error/retry/reset, plus 1280×800 smoke |
| `./apps/connection-agent/scripts/check.sh` | Passed; workload, application, lane smoke, and Jac-native policy |

## Review panel

| Reviewer | Final verdict | Evidence |
|---|---|---|
| Current Jac client | READY | Independently completed `web/check.sh` through browser success with actual exit code 0 |
| Application-operation boundary | READY | Confirmed serialization-only Web boundary over released `DemoApp` and complete replay/privacy/reset coverage |
| Mobile UX/accessibility | READY | Confirmed retained actor-scoped history and the accessible 390px/desktop journey |

## Git confirmation

All required reviewers returned ready. This report will record the implementation
SHA before its final documentation commit. The scoped commits are pushed to
`origin/agent/product-experience`; no merge to `main` is performed.
