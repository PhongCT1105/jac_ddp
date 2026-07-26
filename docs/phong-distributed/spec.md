# Distributed Compute Layer — Spec

**Owner: Phong**

The distributed compute layer is JacGrid's core: the coordinator, the worker runtime, and the Jac graph that records everything. It accepts jobs from applications (Contract A), splits them into tasks, schedules them onto workers, survives worker failure, verifies results, and pays workers.

---

## 1. Responsibilities

- Coordinator service on Mac 1: job API, scheduler, monitor, verifier, payer, dashboard data.
- Worker runtime on every Mac: registration, heartbeats, task pickup, sandbox invocation (Contract B), result return.
- The Jac graph model and all walkers (see `../architecture.md` §3).
- Verification (`recompute_sample` primary) and the payment backend.
- The dashboard/audit API that the demo runs on.

**Not responsible for:** what happens *inside* a task (Luke's sandbox) or what jobs mean to users (Sebastian's app).

---

## 2. Components

### 2.1 Coordinator (Mac 1)

A Jac application exposing HTTP endpoints. Every endpoint spawns a walker; walkers are the only writers to the graph.

| Endpoint | Walker | Notes |
|---|---|---|
| `POST /api/workers/register` | `register_worker` | Body: hostname, capabilities (cpu cores, memory, supported job_types) |
| `POST /api/workers/{id}/heartbeat` | `monitor_heartbeat` | Every 5s from each worker; includes current task status |
| `POST /api/jobs` | `create_job` → `split_job` | Contract A |
| `GET /api/jobs/{id}` | read-only walk | Contract A |
| `GET /api/jobs/{id}/result` | read-only walk | Contract A |
| `GET /api/tasks/next?worker={id}` | `select_worker` + `assign_task` | Pull-based dispatch (see §3) |
| `POST /api/tasks/{id}/result` | `verify_result` → `release_payment` → `update_reputation` | Worker returns the result envelope |
| `GET /api/audit/{job_id}` | `audit_job` | Dashboard execution graph |
| `GET /api/network` | read-only walk | Dashboard: devices, workers, wallets |

### 2.2 Worker runtime (all Macs)

A small daemon (Jac or Python client — pick whichever is fastest, the graph lives on the coordinator either way):

```text
loop:
  send heartbeat (every 5s, includes status)
  if idle: GET /api/tasks/next?worker=me
  if task received:
      hand task envelope to sandbox        # Contract B — Luke's interface
      wait for result envelope (with timeout = limits.wall_seconds + margin)
      POST result envelope to /api/tasks/{id}/result
```

Until Luke's sandbox is ready, the worker calls a **stub runner**: a plain subprocess that executes the embedding workload with no isolation. The envelope shapes are identical, so swapping in the real sandbox is one line.

### 2.3 Scheduler

Pull-based (workers ask for work) — dramatically simpler than push and naturally handles slow/dead workers.

Selection logic in `select_worker`, first version:

1. Filter tasks: `status == queued`, worker supports `job_type`, worker not in the task's `excluded_workers` (failed attempts).
2. Order by job submission time (FIFO).
3. Stretch: weight by Reputation score.

### 2.4 Failure detection

- Worker is **suspect** after 15s without heartbeat (3 missed), **dead** after 30s.
- `detect_failure` runs every 5s: any Attempt whose worker is dead, or which exceeded `wall_seconds + 60s`, is marked `failed`.
- `reassign_task` re-queues the task with the failed worker added to `excluded_workers`. Max 3 attempts per task; after that the whole job is marked `failed` with a reason.

### 2.5 Verification

`verify_result` for `recompute_sample`:

1. Pick `sample_rate` of the task's items (min 1).
2. Recompute them locally on the coordinator (or dispatch to a verifier worker — stretch).
3. Compare with cosine similarity ≥ 0.999 per sampled embedding (models are deterministic; tolerance covers float noise).
4. Pass → Verification node `passed`, trigger payment. Fail → task re-queued, worker reputation penalized, no payment.

### 2.6 Payment backend

Interface first, implementation second:

```text
PaymentBackend.pay(from_wallet, to_wallet, amount) -> receipt {tx_id, timestamp}
```

- **v1 (build first): `SimulatedLedger`** — balances in the Jac graph, tx_id = uuid. Fully demoable.
- **v2 (stretch): testnet** — real transfer on an EVM testnet; same interface, receipt carries the real tx hash.

Payment rules: pay only on passed verification; one Payment node per verified task; amount = `price_per_task` frozen at submission.

---

## 3. Data & config

- Coordinator URL distributed to workers via env var / config file (`JACGRID_COORDINATOR=http://mac1.local:8000`).
- Worker identity: hostname + generated worker-id persisted locally.
- Auth for the hackathon: shared secret header (`X-JacGrid-Key`) for app and workers.

---

## 4. Milestones

| # | Milestone | Proves |
|---|---|---|
| M1 | Coordinator up; `noop` job submitted via curl; splits into tasks; single local worker completes them | Job lifecycle works end-to-end on one machine |
| M2 | Three Macs registered; heartbeats visible; tasks distributed across all three | Real distribution |
| M3 | Kill a worker mid-job; task reassigned; job still completes | Failure recovery (demo Beat 3) |
| M4 | Embedding job type wired through stub runner; verification passes; simulated payments release | Full economic loop |
| M5 | Luke's sandbox swapped in for the stub runner | Real isolation |
| M6 | Sebastian's app submits the job instead of curl | Full product story |

---

## 5. Risks & mitigations

- **Jac HTTP serving unfamiliar** → spike this in the first hour; if blocked, front the Jac graph with a thin FastAPI shim that spawns walkers.
- **mDNS (`mac1.local`) flaky on venue Wi-Fi** → use raw IPs; consider a phone hotspot as the demo network.
- **Clock skew breaks heartbeat math** → compute liveness from coordinator receive-time only, never worker timestamps.
- **Verification recompute too slow on stage** → keep sample small (min 1 item), pre-warm the model on the coordinator.
