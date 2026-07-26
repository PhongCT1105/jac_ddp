# Proposal: Connection Agent ↔ JacGrid Boundary Contracts

**Status:** Proposed for agreement before implementation

**Participants:** Sebastian, Phong, Luke/Santhos

**Scope:** Only the two boundaries where Connection Agent supplies or consumes something

## 1. Purpose

Define exactly what our application sends to JacGrid, what it receives, and what our application-owned workload package provides to the sandbox. These contracts let every workstream implement its own side without dictating how another workstream works internally.

This proposal deliberately does **not** define the protocol between Phong's worker and Luke/Santhos's sandbox. That interface is owned by Phong and Luke/Santhos.

## 2. Boundary map

```text
Connection Agent
    │
    │ Boundary A: embedding job request, status, complete result
    ▼
Phong's JacGrid platform
    │
    │ Their internal boundary: owned by Phong + Luke/Santhos
    ▼
Luke/Santhos's sandbox
    │
    │ Boundary B: invoke our immutable workload package
    ▼
connection-embedding
```

Inside their respective borders:

- Phong chooses graph structure, scheduling, task splitting, worker selection, retry, verification orchestration, aggregation, payment, reputation, and dashboard behavior.
- Luke/Santhos choose installation, allowlisting, process supervision, filesystem/network isolation, resource enforcement, cleanup, and execution metadata implementation.
- Sebastian chooses embedding model, preprocessing, normalization, schemas, fixtures, and the Connection Agent's candidate retrieval and ranking behavior.

Only the payloads that cross Boundary A or Boundary B require joint agreement.

## 3. Correction to the earlier ranking proposal

The root `CONNECTION_APP_JACMARKET_API_CONTRACT.md` describes an earlier candidate-ranking workload. The accepted ownership decision changed the first workload to embedding generation:

```text
Earlier proposal: JacGrid ranks candidates
Accepted direction: JacGrid returns verified embeddings; Connection Agent ranks candidates
```

If this proposal is accepted, it is authoritative for the first Connection Agent workload and supersedes only the ranking-workload request/result examples in that earlier proposal. The earlier file is preserved as team history and is not renamed or rewritten by this proposal.

## 4. Boundary A: Connection Agent to JacGrid

### 4.1 What Connection Agent sends

Connection Agent submits one logical embedding job containing all profile revisions that need vectors. The request identifies the exact workload release:

```json
{
  "contract_version": 1,
  "application_id": "connection-agent",
  "job_type": "embedding",
  "workload": {
    "id": "connection-embedding",
    "version": "1.0.0",
    "artifact_sha256": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "items": [
    {
      "id": "profile_revision_01",
      "text": "Synthetic or explicitly approved canonical profile text"
    }
  ]
}
```

The authenticated server request includes an `Idempotency-Key`. The browser never submits JacGrid jobs and never receives the JacGrid service credential.

Application requirements:

- `items[].id` is unique within the logical job.
- `items[].text` is synthetic fixture text or canonical profile text explicitly approved for this computation.
- The application does not send unrelated conversation history, phone numbers, credentials, Supabase identifiers that are unnecessary for correlation, candidate rankings, or match decisions.
- Workload identity includes an immutable version and release-artifact hash.
- The application submits the complete batch. It does not assign items to workers or depend on JacGrid's task partitioning.

The platform may choose any internal task sizes and worker distribution that preserve the contract.

### 4.2 Submission response

A successful submission returns an accepted logical job:

```json
{
  "contract_version": 1,
  "job_id": "job_01",
  "status": "queued",
  "accepted_item_count": 30,
  "submitted_at": "2026-07-26T19:03:21Z"
}
```

Idempotency requirements:

- Repeating the same idempotency key with the same canonical request returns the same logical `job_id` and creates no duplicate payment obligation.
- Reusing the key with different content returns `409 idempotency_conflict`.
- A network timeout does not by itself mean the logical job failed; the application retries submission using the same key.

### 4.3 Status response

Connection Agent can query one application-level lifecycle:

```json
{
  "contract_version": 1,
  "job_id": "job_01",
  "status": "running",
  "progress": {
    "completed_items": 12,
    "total_items": 30
  },
  "error": null
}
```

Job states visible to Connection Agent are exactly:

- `queued`
- `running`
- `verifying`
- `complete`
- `failed`

Worker IDs, task attempts, sandbox details, scheduling state, and payment internals are not required by our application contract. Phong may expose them separately for the JacGrid dashboard.

### 4.4 Complete result

A complete job returns the full embedding set:

```json
{
  "contract_version": 1,
  "job_id": "job_01",
  "workload": {
    "id": "connection-embedding",
    "version": "1.0.0",
    "artifact_sha256": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "results": [
    {
      "id": "profile_revision_01",
      "embedding": [0.125, -0.25],
      "dimensions": 2,
      "normalized": true
    }
  ],
  "result_sha256": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "receipt": {
    "item_count": 30,
    "verified": true
  }
}
```

Result requirements:

- There is exactly one result for every submitted item ID and no additional ID.
- Task or worker partitioning never changes the result set. If 30 people are processed as three groups of 10, Connection Agent still receives all 30 vectors and ranks across the eligible 30-person set.
- Every vector has the pinned model's fixed dimensions, finite numeric values, and declared normalization.
- The response repeats the exact workload version and artifact hash accepted at submission.
- A partial, malformed, unverified, or mixed-version result is a failed job, never a successful result.
- JacGrid does not return candidate rankings, pair assessments, cards, consent decisions, matches, threads, or messages.

Connection Agent validates these invariants before storing vectors in Supabase.

### 4.5 Error contract

Boundary A errors have one safe shape:

```json
{
  "error": {
    "code": "stable_machine_code",
    "message": "Safe human-readable explanation",
    "retryable": false,
    "details": {}
  },
  "request_id": "request_01"
}
```

Minimum errors our adapter must handle:

| HTTP | Code | Meaning | Retryable |
|---|---|---|---|
| `400` | `invalid_request` | JSON or required field is invalid | No |
| `401` | `unauthenticated` | Missing or invalid application credential | No |
| `403` | `forbidden` | Application cannot use workload or read job | No |
| `404` | `job_not_found` | Job is unavailable to this application | No |
| `409` | `idempotency_conflict` | Key reused for different request | No |
| `409` | `job_not_complete` | Result requested before completion | Yes |
| `422` | `unsupported_workload` | Workload version/hash is not accepted | No |
| `429` | `capacity_unavailable` | Platform temporarily cannot accept work | Yes |
| `500` | `internal_error` | Unexpected platform error | Yes |
| `503` | `service_unavailable` | Platform temporarily unavailable | Yes |

`details` never contains credentials, raw stack traces, another application's data, or worker secrets. Connection Agent uses bounded retries only when `retryable` is true.

## 5. Boundary B: Our workload package to the sandbox

### 5.1 What Sebastian supplies

`workloads/connection-embedding/` is one immutable, independently runnable package containing:

- `workload.json` manifest;
- Jac entrypoint and source;
- locked runtime dependencies;
- exact model identity, immutable revision, and artifact SHA-256;
- input and output JSON schemas;
- resource requirements or recommendations;
- numeric verification tolerance and normalization rule;
- deterministic valid and invalid fixtures;
- a local runner and tests.

The package contains no Supabase, candidate retrieval, candidate ranking, pair assessment, consent, matching, chat, worker scheduling, payment, or UI logic.

### 5.2 Manifest

The proposed V1 manifest includes only information needed to identify and invoke our workload:

```json
{
  "contract_version": 1,
  "id": "connection-embedding",
  "version": "1.0.0",
  "entrypoint": ["jac", "run", "src/main.jac"],
  "input_schema": "schemas/input.schema.json",
  "output_schema": "schemas/output.schema.json",
  "model": {
    "id": "chosen-model-id",
    "revision": "immutable-revision",
    "artifact_sha256": "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  },
  "resources": {
    "cpu_seconds": 120,
    "memory_mb": 2048,
    "wall_seconds": 180,
    "network": "none"
  },
  "verification": {
    "numeric_tolerance": 0.00001,
    "normalized": true
  }
}
```

The package-release hash is calculated over a canonical release archive and recorded outside the archive, avoiding a self-referential hash. The model hash is pinned separately inside the manifest.

### 5.3 Invocation payloads

The proposed input is:

```json
{
  "contract_version": 1,
  "items": [
    {"id": "profile_revision_01", "text": "Approved profile text"}
  ]
}
```

The proposed output is:

```json
{
  "contract_version": 1,
  "model": {
    "id": "chosen-model-id",
    "revision": "immutable-revision",
    "artifact_sha256": "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  },
  "results": [
    {"id": "profile_revision_01", "embedding": [0.125, -0.25]}
  ]
}
```

Boundary requirements:

- Output IDs and order match input IDs and order exactly.
- Every vector has the model's fixed dimension and contains only finite numbers.
- Preprocessing and normalization live in the package and are not reimplemented elsewhere.
- The same package and fixtures run through our local harness, Luke/Santhos's sandbox, and JacGrid workers.
- Runtime network access is not required; all runtime artifacts are installed and verified beforehand.
- Logs must not contain profile text or vectors by default.

The exact process transport—such as standard input/output, file envelopes, or a local socket—requires agreement with Luke/Santhos. Our package will provide a thin adapter for the selected transport without changing the embedding algorithm or schemas.

### 5.4 What remains Luke/Santhos's decision

This proposal does not prescribe:

- sandbox technology;
- allowlist storage;
- installation layout;
- operating-system permissions;
- filesystem or network isolation mechanism;
- CPU, memory, or timeout enforcement mechanism;
- temporary-directory strategy;
- log capture implementation;
- cleanup implementation;
- the interface between the sandbox and Phong's worker.

We provide the declared package and prove that it runs locally. Luke/Santhos decide how to run it safely while satisfying the accepted boundary.

## 6. Versioning

- Changing model, model revision, model bytes, preprocessing, normalization, dependencies, or output semantics creates a new workload version.
- Removing or renaming a boundary field, changing its meaning, or changing an enum creates a new contract version.
- Running jobs remain pinned to the workload version and package hash accepted at submission.
- A new workload release does not silently replace an old allowlisted release.
- Proposed changes are reviewed by every owner whose boundary is affected before implementations emit them.

## 7. Fixtures and acceptance tests

Our side supplies fixtures for:

- valid one-item and multi-item jobs;
- duplicate idempotent submission;
- idempotency-key conflict;
- unsupported workload version/hash;
- complete result across multiple internal task partitions;
- missing, extra, and duplicate result IDs;
- wrong vector dimension or normalization;
- partial and terminal failure;
- workload valid input/output;
- workload invalid input;
- exact model identity and deterministic tolerance.

Acceptance requires:

1. Our `MockJacGrid` satisfies Boundary A without importing platform code.
2. Phong's live coordinator satisfies the same recorded Boundary A fixtures.
3. Our local workload runner satisfies Boundary B.
4. Luke/Santhos can invoke the unchanged workload package using the agreed transport.
5. Local, sandboxed, and distributed runs produce contract-compatible vectors within the declared tolerance.
6. Our tests never require access to Phong's or Luke/Santhos's implementation modules.

## 8. Non-goals

This proposal does not tell Phong how to distribute, retry, verify, aggregate, pay, or represent jobs in Jac. It does not tell Luke/Santhos how to isolate or supervise the workload. It does not define their shared worker-to-sandbox task envelope. It defines only what Connection Agent sends and receives, and what our workload package promises at its execution boundary.
