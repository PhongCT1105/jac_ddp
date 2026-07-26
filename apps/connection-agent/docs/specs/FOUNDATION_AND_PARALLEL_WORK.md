# Spec: Connection Agent Foundation and Parallel Work

**Status:** Proposed for team review

**Owner:** Sebastian / Connection Agent workstream

**Applies to:** `apps/connection-agent/` and `workloads/connection-embedding/`

## 1. Purpose

Prepare our part of `jac_ddp` so several Codex sessions can implement the Connection Agent concurrently without editing Phong's platform or Luke/Santhos's sandbox.

This is foundation work performed by the orchestration agent before the implementation sessions split. It establishes our directories, internal contracts, fake adapters, walking skeleton, quality gate, and ownership rules.

## 2. Hard repository boundary

Our implementation sessions may write only inside:

```text
apps/connection-agent/
workloads/connection-embedding/
```

The following are read-only to our implementation sessions:

```text
platform/                  # Phong
sandbox/                   # Luke/Santhos
docs/phong-distributed/    # Phong
docs/luke-sandbox/         # Luke/Santhos
```

Shared root paths such as `contracts/`, `docs/`, `tests/integration/`, root scripts, and CI configuration are changed only by the orchestration/integration agent in a small reviewable commit. A shared-boundary proposal must be accepted by the affected team members before our implementation agents depend on it.

Our agents never repair, refactor, complete, or reorganize another workstream's implementation, even when they can see a problem there. They record the issue for the orchestration agent at the boundary.

## 3. Our target structure

```text
apps/connection-agent/
├── src/
│   ├── contracts/       # internal domain types and operation interfaces
│   ├── core/            # suggestion, consent, match, thread, message rules
│   ├── adapters/        # Supabase, JacGrid, LLM, identity, notifications
│   └── intelligence/    # profile, retrieval, assessment, card workflows
├── web/                 # first-party client/PWA
├── supabase/            # migrations, RLS policies, local fixture seed
├── evals/               # personas, scenarios, rubrics, reports
├── tests/               # application-level and adapter tests
├── scripts/
│   ├── setup.sh
│   ├── check.sh
│   └── run-demo.sh
├── docs/
│   ├── specs/
│   ├── PRODUCT_BOOK.md
│   ├── TECHNICAL_DIRECTION.md
│   ├── BUILD_PLAN.md
│   ├── HACKATHON_DEMO.md
│   └── OPEN_QUESTIONS.md
├── .env.example
├── jac.toml
└── README.md

workloads/connection-embedding/
├── src/
├── schemas/
├── fixtures/
├── tests/
├── workload.json
├── jac.toml
└── README.md
```

The five existing product documents are copied into our application folder with their filenames preserved and content verified. Existing shared or team-authored documents are not renamed or rewritten as part of that copy.

## 4. Foundation that precedes the session split

The orchestration agent completes and merges these items in order:

### F0 — Bootstrap our folders

- Create only our application and workload structures.
- Copy our product documents.
- Document local prerequisites and safe configuration examples.
- Ignore our local secrets, dependencies, caches, build output, and model caches.
- Establish one application setup command and one smoke check.

**Exit:** a fresh worktree can follow our README and run the smoke check without touching `platform/` or `sandbox/`.

### F1 — Release our internal contracts

Define the transport-independent types and operations for:

- authenticated actor and fixture actor;
- canonical profile and immutable profile revision;
- profile proposal, approval, and rejection;
- embedding request, state, result, and failure;
- candidate reference and reciprocal pair assessment;
- recipient-specific card and suggestion lifecycle;
- private interest decision;
- match, thread, and message;
- trace event and stable application error;
- idempotency keys and authorization context.

The contract fixes identifiers, revision references, exact lifecycle states, authorization expectations, retry/idempotency behavior, and successful/error outputs. It does not bind operations to HTTP, MCP, a browser, Supabase, or an in-process Jac agent call.

**Exit:** every planned implementation session can compile or validate fixtures against one released internal contract version.

### F2 — Build fake adapters and fixture people

Create in-memory adapters for identity, profiles, embedding compute, candidate retrieval, pair assessment, cards, suggestions, interests/matches, threads/messages, and captured notifications. `MockJacGrid` invokes the exact local `connection-embedding` workload; it does not implement another embedding algorithm.

**Exit:** tests can act as multiple fixture people and exercise every core interface without phone authentication, Supabase, a live LLM, or live JacGrid.

### F3 — Prove the walking skeleton

Implement [`WALKING_SKELETON.md`](WALKING_SKELETON.md) through the shared application operations and fake adapters.

**Exit:** one deterministic scenario completes profile → embedding → candidate → two private opens → one match/thread → one message.

### F4 — Establish our quality gate

`./apps/connection-agent/scripts/check.sh` runs:

1. formatting checks without modifying files;
2. internal type/schema and fixture validation;
3. workload schema, fixture, and local-runner tests;
4. application unit tests;
5. the mock walking-skeleton scenario;
6. checks that our code does not import platform or sandbox implementation modules.

The command returns nonzero on any failure. The orchestration agent may add a path-filtered CI job that invokes this command, but our implementation agents do not edit shared CI independently.

**Exit:** every new worktree runs the same fast pre-merge command successfully.

## 5. Parallel objectives after foundation

After F0–F4 are merged, separate Codex sessions may own these objectives:

| Objective | Writable paths | Typical specs |
|---|---|---|
| Core lifecycle | `apps/connection-agent/src/core/` | Profile approval, suggestions, reciprocal consent, atomic match/thread |
| Persistence and service adapters | `apps/connection-agent/src/adapters/`, `apps/connection-agent/supabase/` | Repositories, RLS, identity, realtime, `LiveJacGrid` client |
| Intelligence and workload | `apps/connection-agent/src/intelligence/`, `workloads/connection-embedding/` | Profile generation, embeddings, retrieval, pair assessment, cards |
| Product experience | `apps/connection-agent/web/` | Conversation UI, cards, phone sign-in, private chat |
| Evaluation and quality | `apps/connection-agent/evals/`, assigned application test paths | Fixture scenarios, invariants, qualitative rubrics, regression reporting |

An objective can contain a sequence of smaller specs. The objective owner works through those specs in order on its own branch and worktree.

## 6. Shared-path ownership during parallel work

The orchestration agent remains responsible for:

- `apps/connection-agent/src/contracts/`;
- cross-objective application integration tests;
- product documentation and accepted decision notes;
- coordinating Supabase migration order;
- incorporating agreed boundary-contract changes;
- reviewing directory scope before merge;
- merging small vertical increments and keeping the integration branch green.

If an objective needs a contract change, its session stops at the boundary, proposes the smallest change, and continues only after the orchestration agent releases the revised contract. It does not edit the shared contract opportunistically.

## 7. Git and worktree rules

- Every active objective uses its own branch and worktree; separate sessions never share one checked-out directory.
- Branches start from the same tested foundation commit.
- Commits stay inside the objective's declared writable paths.
- Sessions incorporate small released contract changes before continuing dependent work.
- No objective merges directly to `main`; the orchestration agent reviews scope, checks, and integration order.
- Another workstream's files are not changed to make our tests pass. Their service is represented by the accepted boundary contract and our fake adapter.

## 8. Configuration and safety

- Commit safe examples only; never commit credentials, service-role keys, phone-provider secrets, JacGrid credentials, wallet keys, or private model tokens.
- Browser code never receives server credentials.
- Fixture identity and reset functionality are local/test-only and fail closed against production-marked services.
- Synthetic fixture profiles are used for local and distributed-compute tests unless a person explicitly approves their profile text for that purpose.
- Production data is never copied to workers or committed as a fixture.

## 9. Acceptance criteria

The parallel foundation is ready when:

- Our application and workload folders contain the documented structure and README files.
- The five product documents are copied into our folder without renaming team documents.
- Phong's and Luke/Santhos's paths have no changes from our foundation branch.
- Internal application types and operation contracts have one released version.
- `MockJacGrid` and the fake repositories satisfy those interfaces.
- The complete walking skeleton passes.
- `./apps/connection-agent/scripts/check.sh` passes in a clean worktree and catches a deliberately broken invariant.
- Every parallel objective has explicit writable paths and an ordered starting spec.
- The two external boundaries we participate in are accepted or represented by recorded fakes; no agent depends on Phong-to-Luke/Santhos internals.

## 10. Out of scope

This foundation does not implement or prescribe coordinator scheduling, JacGrid task graphs, worker registration, worker heartbeats, retries inside the platform, payment, reputation, dashboard behavior, sandbox isolation, allowlist storage, resource enforcement, or the task protocol between Phong and Luke/Santhos.
