# JacGrid Architecture

This document defines the system architecture shared by all three workstreams: the components, the Jac graph model, the walkers, and — most importantly — the two API contracts that let Phong, Luke, and Sebastian build in parallel.

---

## 1. System overview

JacGrid has three layers, each owned by one person:

| Layer | Owner | Responsibility |
|---|---|---|
| Application | Sebastian | A real product (the matching app) that consumes the network by submitting jobs |
| Distributed compute | Phong | Coordinator + workers: job lifecycle, scheduling, monitoring, recovery, verification, payment |
| Sandbox | Luke | Safe, restricted execution of task workloads on each worker Mac |

The layers communicate only through two contracts:

1. **Job Submission API** — between the application and the coordinator (HTTP/JSON).
2. **Task Execution API** — between the worker runtime and the sandbox (local process interface).

Everything inside a layer can change freely; the contracts cannot change without all three agreeing.

---

## 2. Physical topology (hackathon)

```text
Mac 1  — Coordinator (Jac), web dashboard, matching app backend, optional worker
Mac 2  — Worker + sandbox
Mac 3  — Worker + sandbox, optional verifier
```

All machines share one local network. Workers discover the coordinator via a configured URL (no discovery protocol needed for the hackathon).

---

## 3. Jac graph model

Jac is not a wrapper — the graph **is** the system of record. Every job, task, attempt, result, verification, and payment exists as a node, and walkers drive all state transitions.

### Nodes

```text
Device        — a physical Mac: hostname, hardware profile, owner
Worker        — a runtime on a Device: capabilities, status, last heartbeat
Application   — a registered job source (the matching app)
Job           — a submitted workload: spec, budget, status
Task          — one unit of a Job: payload slice, price, status
Attempt       — one execution of a Task by one Worker
Sandbox       — execution environment metadata for an Attempt
Result        — output artifact + metadata from an Attempt
Verification  — the check applied to a Result and its outcome
Wallet        — testnet wallet for a Worker or the coordinator
Payment       — a settled transfer tied to a verified Task
Reputation    — rolling success/failure record for a Worker
```

### Edges

```text
Application ── submits ──────> Job
Job ────────── contains ─────> Task
Task ───────── attempted_by ─> Attempt
Attempt ────── executed_by ──> Worker
Worker ─────── hosted_on ────> Device
Attempt ────── ran_inside ───> Sandbox
Attempt ────── produced ─────> Result
Result ─────── checked_by ───> Verification
Task ───────── settled_by ───> Payment
Payment ────── paid_to ──────> Wallet
Worker ─────── rated_by ─────> Reputation
```

### Walkers

Walkers own all mutations. No REST handler mutates the graph directly; handlers spawn walkers.

| Walker | Trigger | Effect |
|---|---|---|
| `register_worker` | Worker POSTs registration | Creates/updates Worker + Device nodes |
| `create_job` | Application submits a job | Creates Job node, validates spec and budget |
| `split_job` | After `create_job` | Creates Task nodes from the job's partitioning rule |
| `select_worker` | Task needs assignment | Picks an idle Worker matching task requirements (reputation-weighted later) |
| `assign_task` | After `select_worker` | Creates Attempt, marks Task `running`, dispatches payload to Worker |
| `monitor_heartbeat` | Periodic | Updates Worker liveness from heartbeat timestamps |
| `detect_failure` | Periodic | Marks Attempts failed when heartbeat or deadline expires |
| `reassign_task` | After `detect_failure` | Re-enters the Task into scheduling, excluding the failed Worker |
| `verify_result` | Result received | Runs the Job's verification rule, creates Verification node |
| `release_payment` | Verification passed | Creates Payment node, executes testnet transfer, links receipt |
| `update_reputation` | After verification | Adjusts Worker reputation up/down |
| `audit_job` | Dashboard request | Walks the full Job subtree and returns the execution timeline |

---

## 4. Contract A — Job Submission API

**Between:** application (Sebastian) → coordinator (Phong). HTTP + JSON on the coordinator, e.g. `http://mac1.local:8000`.

### `POST /api/jobs`

Submit a job.

```json
{
  "app_id": "matching-app",
  "job_type": "embedding",
  "payload": {
    "model": "all-MiniLM-L6-v2",
    "items": [
      {"id": "profile-001", "text": "ML engineer who loves climbing..."},
      {"id": "profile-002", "text": "Designer into generative art..."}
    ]
  },
  "partitioning": {"strategy": "chunk", "chunk_size": 25},
  "verification": {"method": "recompute_sample", "sample_rate": 0.1},
  "budget": {"max_total": 3.0, "price_per_task": 0.10, "currency": "TESTUSD"}
}
```

Response:

```json
{"job_id": "job-001", "status": "queued", "task_count": 4}
```

### `GET /api/jobs/{job_id}`

Poll status.

```json
{
  "job_id": "job-001",
  "status": "running",            // queued | running | verifying | complete | failed
  "tasks": [
    {"task_id": "t-1", "status": "complete", "worker": "mac2", "paid": true},
    {"task_id": "t-2", "status": "running",  "worker": "mac3", "paid": false}
  ],
  "progress": 0.5
}
```

### `GET /api/jobs/{job_id}/result`

Available when `status == "complete"`. For embedding jobs:

```json
{
  "job_id": "job-001",
  "results": [
    {"id": "profile-001", "embedding": [0.013, -0.221, ...]},
    {"id": "profile-002", "embedding": [0.157, 0.043, ...]}
  ],
  "receipt": {
    "tasks": 4, "verified": 4, "total_paid": 0.40,
    "payments": [{"task_id": "t-1", "worker": "mac2", "amount": 0.10, "tx": "0xabc..."}]
  }
}
```

Optional for the demo, nice to have: `POST /api/jobs/{job_id}/webhook` for push notification instead of polling.

### Job types (allowlist, hackathon)

| `job_type` | Payload | Result per item |
|---|---|---|
| `embedding` | items with `id` + `text`, model name | vector of floats |
| `training_shard` | dataset shard reference + hyperparams | gradients / trained weights + metrics |
| `noop` | anything | echo (integration testing only) |

---

## 5. Contract B — Task Execution API

**Between:** worker runtime (Phong) → sandbox (Luke). A local interface on each worker Mac: the worker hands the sandbox a task envelope, the sandbox returns a result envelope. Implementation detail (subprocess + JSON files, or a local socket) is Luke's choice, but the envelope shapes are fixed.

### Task envelope (worker → sandbox)

```json
{
  "task_id": "t-2",
  "job_type": "embedding",
  "payload": {
    "model": "all-MiniLM-L6-v2",
    "items": [{"id": "profile-026", "text": "..."}]
  },
  "limits": {"cpu_seconds": 120, "memory_mb": 2048, "wall_seconds": 180, "network": "none"}
}
```

### Result envelope (sandbox → worker)

```json
{
  "task_id": "t-2",
  "status": "ok",                 // ok | error | timeout | limit_exceeded
  "output": {"results": [{"id": "profile-026", "embedding": [...]}]},
  "execution": {
    "runtime": "embedding-runner:v1",
    "started_at": "2026-07-26T14:03:21Z",
    "finished_at": "2026-07-26T14:03:44Z",
    "peak_memory_mb": 812,
    "cpu_seconds": 19.4,
    "exit_code": 0
  },
  "error": null
}
```

Rules:

- The sandbox never talks to the coordinator; only the worker runtime does.
- The sandbox only runs allowlisted `job_type`s. Unknown types return `status: "error"` immediately.
- The `execution` block is mandatory — it feeds the Sandbox and Attempt nodes in the Jac graph and the audit timeline.

---

## 6. End-to-end data flow

```text
 1. Matching app POSTs an embedding job (100 profiles)          [Sebastian → Contract A]
 2. create_job + split_job walkers → 4 Tasks of 25 items        [Phong]
 3. select_worker + assign_task dispatch tasks to Mac 1/2/3     [Phong]
 4. Worker runtime hands each task envelope to the sandbox      [Phong → Contract B]
 5. Sandbox runs the allowlisted embedding runner under limits  [Luke]
 6. Result envelopes return to the coordinator                  [Luke → Phong]
 7. verify_result recomputes a 10% sample and compares          [Phong]
 8. release_payment pays each verified task's worker (testnet)  [Phong]
 9. Matching app fetches combined embeddings + payment receipt  [Phong → Sebastian]
10. Matching app computes similarity and shows matches          [Sebastian]
```

Failure path: if a worker dies mid-task, `detect_failure` marks the attempt failed, `reassign_task` reschedules it on another worker, and the dead worker's attempt receives no payment.

---

## 7. Verification methods (hackathon set)

| Method | How it works | Good for |
|---|---|---|
| `recompute_sample` | Coordinator (or a verifier worker) re-runs a random sample of items and compares outputs within a tolerance | Embeddings (deterministic models) |
| `output_hash` | Expected hash provided at submission | Fixed test workloads, `noop` |
| `metric_range` | Returned metric (e.g. loss) must fall in a declared range | Training shards |
| `redundant_compute` | Same task sent to two workers; outputs must agree | Demo of trustless mode (stretch) |

`recompute_sample` is the primary demo method.

---

## 8. Payment model

- Each worker Mac has a testnet wallet (or a simulated ledger — see decision below).
- `price_per_task` is fixed at submission; it cannot change after a worker accepts.
- Payment executes only after `verify_result` passes.
- Every Payment node stores the transaction reference, linked to Task → Worker → Wallet in the graph.

**Decision point (Phong, hour 2):** real testnet (e.g. Base Sepolia USDC-style transfer) vs. an internal simulated ledger with the same receipt shape. Start with the simulated ledger behind a `PaymentBackend` interface; swap in testnet only if time allows. The demo story is identical either way.

---

## 9. Out of scope (hackathon)

- Public device onboarding, Sybil resistance, escrow, disputes
- Arbitrary user-submitted code (only allowlisted `job_type`s run)
- Full VM isolation (restricted process/container is enough)
- Worker bidding and dynamic pricing
- Production auth (a static `app_id` + shared secret is fine)
