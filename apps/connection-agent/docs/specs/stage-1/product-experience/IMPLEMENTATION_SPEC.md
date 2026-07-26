# Stage 1 implementation spec: Product Experience

**Handoff:** `docs/stage-1/handoffs/03_PRODUCT_EXPERIENCE.md`

**Branch:** `agent/product-experience`

**Baseline SHA:** `7f9f0cfa1f6c6ac395637f8126761c8eaac640c8`

**Toolchain:** `jac 0.34.6 (Darwin arm64)`

**Status:** Implemented and final-panel ready

## Outcome

The branch provides one mobile-first Jac application for the complete Stage 1
presentation. A fresh reset has no suggestion, decision, match, or thread. Alice
confirms her immutable synthetic profile, receives Bob's viewer-specific card,
and can open without seeing reciprocity. Switching to Bob clears Alice's visible
context while retaining the Core-owned private decision. Bob confirms his own
profile, receives a distinct card about Alice, and only his independent open can
return the one match and thread. The resulting private thread begins empty and
accepts an ordered human message.

Demo command from the repository root:

```bash
./apps/connection-agent/web/start.sh
```

No credentials or external services are required.

## Architecture and state ownership

- `web/main.jac` is the Jac client. It calls only the seven frozen Stage 1
  operations through `sv import`, renders returned data, and owns presentation
  state such as current screen, pending state, safe errors, and focus. It does
  not infer reciprocity, authorization, idempotency, match creation, or message
  access.
- `web/fixture.jac` is the local server boundary. It delegates all seven frozen
  operations—including suggestion ownership/idempotency and reset—to the
  owner-authored `src.core.demo_app.DemoApp` façade at released commit
  `80f685a`. It does not contain competing lifecycle rules.
- Canonical server objects are converted at the endpoint boundary to plain JSON
  records with the exact frozen field names. This is necessary because returning
  `ProfileRevision` and nested `Suggestion` archetypes directly through the Jac
  0.34.6 client endpoint hydrated as `null`, while importing their server module
  into `cl` pulled server/wasm code into the browser bundle. The DTO conversion
  changes transport representation only; canonical contracts and Core semantics
  remain unchanged.
- `reset_demo` replaces the local façade instance only through Core's released
  reset operation. Actor/profile selection and deterministic suggestions remain
  released fixture dependencies behind that façade.
- `main.jac` at the project root is a Jac-only entry shim. Jac 0.34.6 compiles a
  nested `web/main.jac` entry to `compiled/web/main.js` while its generated Vite
  entry imports `compiled/main.js`; the shim imports and renders `web.main.app`
  and contains no product behavior.

## User states and accessibility

The interface renders explicit start, profile review, profile confirmation,
suggestion, private response, match, empty thread, populated thread, pending,
safe error, and retry states. Network-returned null payloads are guarded before
any contract field is read. A failed fixture selection remains on a labelled
loading/error screen with a retry action rather than entering an invalid profile
or card view.

Controls have visible labels and at least 44px targets. Pending operations
disable their action. Status changes use a polite live region and errors use
`role="alert"`. New stages focus their labelled heading. Focus-visible controls
have a high-contrast outline. The 390px layout uses one column and 16px gutters;
the sticky composer is backed by bottom page padding and remains reachable by
keyboard. Each persona keeps an actor-scoped conversation history: the confirmed
profile and immutable card remain visible as the private response, match, and
thread items are appended. Switching from Alice to Bob replaces the visible
history with Bob's safe context. Cards, match state, empty thread, and messages
have distinct surfaces.

Alice's pass response does not offer the scripted switch-to-Bob continuation.
The continuation is shown only after the returned Alice decision has kind
`open`; match rendering still depends exclusively on a returned `match` record.

## Files

- `jac.toml`: authorized minimal Jac web-client project configuration.
- `main.jac`: Jac 0.34.6 root entry shim.
- `web/main.jac`: client UI and Stage 1 operation calls.
- `web/fixture.jac`: client-safe serialization over released fixtures/Core.
- `web/styles.css`: responsive and accessible presentation.
- `web/start.sh`: secret-free local start command.
- `web/check.sh`: build, regression, 390px journey, focus/error/retry, reset,
  and desktop smoke automation.
- `tests/experience/product_experience_tests.jac`: exact wire-shape and Core
  lifecycle regression.
- `web/README.md`: operator instructions.

## Authorized project configuration

The operator explicitly authorized a focused `apps/connection-agent/jac.toml`
change. Installed Jac client guidance requires a `web-app` project and a client
entry. The exact change is:

- `entry-point = "src/main.jac"` → `entry-point = "main.jac"`
- `kind = "cli"` → `kind = "web-app"`
- add runtime npm dependencies: `react ^18.2.0`, `react-dom ^18.2.0`,
  `react-router-dom ^6.22.0`, `react-error-boundary ^5.0.0`,
  `@tanstack/react-form ^1.33.0`, and `zod ^4.3.6`
- add development npm dependencies: `vite ^6.4.1`,
  `@vitejs/plugin-react ^4.2.1`, `typescript ^5.3.3`,
  `@types/react ^18.2.0`, and `@types/react-dom ^18.2.0`

`jac build --client web` builds the client successfully and emits a hashed
bundle in `.jac/client/dist/`. No package or shared configuration outside this
authorized file is changed.

## Regression and acceptance evidence

`tests/experience/product_experience_tests.jac` proves the client wire contains
the full `ProfileRevision` fields and nested `Suggestion`/`CardSnapshot` fields,
the two cards differ, Alice's first open returns no match, a same-input retry is
idempotent, Bob's reciprocal open returns one thread, the message retry returns
the same record, Carol is forbidden from the thread, and reset clears Core
state.

`web/check.sh` then proves those wires hydrate in the browser by rendering the
canonical Alice profile text and suggestion evidence. At a 390×844 viewport it
automates Alice profile confirmation → Bob card → private Alice open → Bob
profile confirmation → distinct Alice card → reciprocal match → private thread
→ one message → reset. It asserts no match text appears after Alice's open,
asserts focus after each major transition, verifies retained safe history, and
exercises the failed-selection error/retry boundary. A second 1280×800 session
verifies desktop startup. The browser check is
mandatory and has no skip path.

## Jac-native evidence

The client, server boundary, and regression are authored in Jac. The only
format-native supporting files are CSS and POSIX shell start/check scripts; no
JavaScript, TypeScript, Python, generated source, secret, or external service is
added. Current Jac client/full-stack, project-kind, endpoint, `sv import`, type,
styling, testing, and browser guidance informed the implementation.

## Final reviews

| Reviewer | Verdict | Resolution evidence |
|---|---|---|
| Current Jac client/full-stack | READY | Verified the DTO/Core boundary, build, and completed `web/check.sh` through actual exit code 0 with browser-ready and final success markers |
| Application-operation boundary | READY | Verified every released operation delegates to `DemoApp`, exact-field JSON is serialization-only, and replay/privacy/reset regressions cover the boundary |
| Mobile UX/accessibility | READY | Verified actor-scoped retained history, private Alice state, focus, labels, loading/error/retry/reset, 390px flow, and desktop startup |

Earlier blocking findings around static completed state, direct server-type
imports, missing idempotency replay, stage-replacement UI, unstable selectors,
and long-running hook yields were resolved before these final verdicts.
