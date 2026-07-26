# Spec: Connection Agent Fake Walking Skeleton

**Status:** Proposed for team review

**Covers:** Foundation steps F2 and F3

**Depends on:** our released internal application contracts and the accepted [`Connection Agent ↔ JacGrid boundary proposal`](../../../../docs/specs/CONNECTION_AGENT_JACGRID_BOUNDARIES.md)

## 1. Purpose

Prove one complete Connection Agent state transition before production persistence, live LLM calls, a live JacGrid coordinator, worker machines, or polished UI exist.

The skeleton uses the real application operation boundaries with deterministic in-memory adapters. Replacing an adapter later—or hosting the application on a different conventional provider—must not require rewriting the product flow.

## 2. Demo flow

One automated scenario performs this sequence:

```text
fixture profiles
    → application-owned connection-embedding workload
    → MockJacGrid contract response
    → candidate retrieval/ranking
    → recipient-specific card for each person
    → Alice opens Bob
    → Bob independently opens Alice
    → exactly one match and one private thread
    → Alice sends one message
    → Bob can read that message
```

The flow must use at least 30 fixture candidate profiles when testing retrieval. Partitioning the embedding computation into tasks does not partition the matching pool: all returned embeddings are combined before candidate retrieval and ranking.

## 3. Fixture people

Seed deterministic, synthetic profiles with stable IDs and profile-revision IDs. At minimum include:

| Fixture | Useful contrast |
|---|---|
| `alice_builder` | Software builder seeking thoughtful technical collaborators; enjoys climbing |
| `bob_researcher` | Distributed-systems researcher; enjoys outdoor activities and mentoring |
| `carol_designer` | Product designer interested in creative tools and community events |
| `diego_organizer` | Community organizer focused on education and introductions |

Add enough synthetic profiles to reach the retrieval fixture size without copying real personal data. Alice and Bob are the positive reciprocal scenario. Carol and Diego help prove that retrieval and card generation are not hardcoded to one pair.

Each fixture contains:

- actor ID;
- full name safe for display;
- canonical Markdown profile;
- immutable profile revision ID;
- eligibility and block state;
- optional current matching request;
- expected embedding fixture metadata, not a hand-authored alternate vector.

No phone number, production account, external message, or real private profile is used.

## 4. Fake adapters

Implement small in-memory adapters for the same interfaces production code will use:

| Boundary | Fake behavior |
|---|---|
| Identity | Select a fixture actor explicitly |
| Profiles | Store versioned Markdown profiles and return only authorized records |
| Embedding compute | `MockJacGrid` invokes the real local workload package and emits Boundary A-compatible lifecycle/results |
| Candidate retrieval | Rank the complete fixture vector set deterministically; exclude self, blocks, and ineligible actors |
| Pair assessment | Return recorded, schema-valid reciprocal evidence for fixture inputs |
| Card generation | Produce distinct immutable card snapshots for Alice viewing Bob and Bob viewing Alice |
| Suggestions | Enforce one active suggestion per viewer and idempotent lifecycle transitions |
| Interest/match | Atomically turn reciprocal independent opens into one match and one thread |
| Messages | Append ordered messages to a thread and enforce participant access |
| Notifications | Capture events in an in-memory outbox without sending anything |

Fakes contain storage or external-service behavior only. Suggestion, consent, match, authorization, and message rules remain in the shared application core.

## 5. One embedding implementation

`MockJacGrid` is a local adapter around the exact package in `workloads/connection-embedding/`:

1. Validate the Boundary A request.
2. Report deterministic `queued`, `running`, and `verifying` fixture states.
3. Partition input using the request's chunk size.
4. Invoke the package through the Boundary B local workload harness for every task.
5. Combine task outputs by input ID.
6. Validate completeness, vector dimensions, normalization, workload identity, and hashes.
7. Return one Boundary A-compatible result and fake compute receipt.

There is no `mock_embedding()` algorithm and no separate hand-written production vector path. Tests may cache outputs from the pinned workload for speed, but must include a parity test proving the cache matches a real local invocation.

## 6. Application operations exercised

The scenario calls transport-independent operations rather than writing repositories directly:

- select/authenticate fixture actor;
- read or save an approved profile revision;
- request the next suggested person;
- read the immutable recipient-specific card snapshot;
- record `open` or `pass` idempotently;
- load a match and its private thread;
- send and list messages.

HTTP, MCP, Jac agent tools, and the web client may later adapt these operations. They must not each recreate the lifecycle.

## 7. Required state invariants

- Candidate retrieval considers the complete eligible fixture set after all embedding task results are combined.
- The current actor is never their own candidate.
- Blocks and system-ineligible fixtures never become candidates.
- Alice's card about Bob and Bob's card about Alice are separate immutable snapshots.
- Alice's open is private and creates no match by itself.
- Bob must receive and independently open his own suggestion.
- Repeated or concurrent opens create exactly one decision per viewer, one unordered pair identity, one match, and one thread.
- A pass does not create a match and cannot reveal the other person's decision.
- Only the two matched actors can read or append thread messages.
- Repeating a message request with the same idempotency key creates one message.
- All stored derived data records the source profile revision and workload version.

## 8. Deterministic failure fixtures

The automated checks include:

- invalid profile revision;
- duplicate job submission;
- unknown or mismatched workload version/hash;
- one failed embedding task;
- partial embedding result;
- duplicate or extra result ID;
- wrong vector dimension;
- no eligible candidate;
- self, blocked, or ineligible candidate leakage;
- repeated and simultaneous opens;
- Alice opens while Bob passes;
- unauthorized third actor reads or writes the thread;
- repeated message submission.

Each failure asserts a stable application or contract error code. Tests do not depend on matching an incidental exception string.

## 9. Commands and test layers

The implementation provides:

- a fast unit test for every fake adapter;
- contract tests for `MockJacGrid` and the local workload harness;
- one end-to-end fixture test for the complete flow;
- `./apps/connection-agent/scripts/run-demo.sh --mock` for a human-readable local run;
- inclusion of all required checks in `./apps/connection-agent/scripts/check.sh`.

The human-readable run prints fixture IDs, job/task progress, selected pair, private decision transitions, match/thread IDs, and the final message. It does not print raw profile text, embeddings, hidden one-sided decisions, secrets, or stack traces.

## 10. Acceptance scenario

Given 30 or more fixture profiles and no external services:

1. Run `./apps/connection-agent/scripts/check.sh`; all contract, unit, and end-to-end checks pass.
2. Run `./apps/connection-agent/scripts/run-demo.sh --mock`.
3. Alice's approved profile revision is embedded through `MockJacGrid` using the real workload.
4. Candidate retrieval ranks across the complete eligible fixture pool and selects Bob deterministically.
5. Alice receives a contract-valid card about Bob and opens it.
6. Bob receives his own card about Alice; before Bob's action, no match is visible.
7. Bob opens his card; exactly one match and one thread now exist.
8. Alice sends one message; Bob reads the same persisted message.
9. Repeating the job, open, match, and message requests with their original idempotency keys creates no duplicates.
10. Carol cannot inspect Alice and Bob's decisions, match, thread, or message.

## 11. Exit condition

The walking skeleton is complete when the full scenario passes entirely through released contracts and application operations, and swapping in a future Supabase repository, `LiveJacGrid`, or another compatible compute adapter requires no change to the scenario's product rules.

## 12. Out of scope

The foundation skeleton does not require phone OTP, production Supabase, Supabase Realtime, live LLM reasoning, polished web UI, MCP hosting, live notifications, a live JacGrid coordinator, physical workers, sandbox isolation, verification payments, venue booking, or production deployment.

It also does not import, modify, or test the internal implementation of `platform/` or `sandbox/`. Live integration is tested later only through the accepted boundary contracts.
