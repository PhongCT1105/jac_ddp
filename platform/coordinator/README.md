# JacGrid Coordinator

The control plane. The Jac graph **is** the system of record: every job, task,
attempt, result, verification, wallet and payment is a node, and walkers are the
only mutators. This is its own Jac project (`kind = "api-service"`).

- `main.sv.jac` — the walkers, i.e. the whole HTTP surface
- `src/model.jac` — nodes, edges, and the helper `def`s the walkers call
  (verification, simulated ledger, failure sweep, Contract A/B views)

Reference: `docs/architecture.md` §3 (graph model), §4 (Contract A), §5
(Contract B), §8 (verification), §9 (payment); `docs/phong-distributed/spec.md`.

## Run

```bash
cd platform/coordinator

../../.venv/bin/jac check .                                   # compile + typecheck
JACGRID_SELFTEST=1 ../../.venv/bin/jac run main.sv.jac        # in-process lifecycle self-test
../../.venv/bin/jac start main.sv.jac --no_client --port 8000 # serve the REST API
```

`jac start` **requires a `jac.toml` in the cwd** — always start it from this
directory. `jac serve` no longer exists.

Once it is up:

| URL | What |
|---|---|
| `http://127.0.0.1:8000/docs` | Swagger for every walker endpoint |
| `http://127.0.0.1:8000/graph` | live graph visualizer (demo gold) |
| `http://127.0.0.1:8000/healthz` | health check |

### Configuration (environment variables)

| Var | Default | Meaning |
|---|---|---|
| `JACGRID_KEY` | `jacgrid-dev-key` | shared secret every caller must send as `secret` |
| `JACGRID_SUSPECT_AFTER` | `15` | seconds of silence before a worker is *suspect* |
| `JACGRID_DEAD_AFTER` | `30` | seconds of silence before a worker is *dead* |
| `JACGRID_MAX_ATTEMPTS` | `3` | attempts per task before the task — and job — fail |
| `JACGRID_SELFTEST` | `0` | `1` runs the in-process lifecycle self-test at startup |

Persistence lives in `.jac/data` (SQLite). **After changing any node schema,
`rm -rf .jac/data`** or you will get `Invalid anchor id` 500s.

## Calling convention

Every walker is `walker:pub`, so no JWT is needed. Real authorization is the
shared secret carried in the request body:

```bash
curl -s -X POST http://127.0.0.1:8000/walker/<walker_name> \
  -H 'Content-Type: application/json' \
  -d '{"secret": "jacgrid-dev-key", ...}'
```

The 0.16 response envelope wraps walker output; the payload you want is the
first element of `data.reports`:

```json
{"ok": true, "type": "response",
 "data": {"result": null, "reports": [ <-- YOUR PAYLOAD --> ]},
 "error": null, "meta": {}}
```

```bash
... | jq -c '.data.reports[0]'
```

**Errors are in-band.** A wrong secret or an unknown job still returns HTTP 200
with an error object in the report (`{"error": "unauthorized", ...}`). Clients
must inspect the report, never the HTTP status code.

### Why every caller sees one grid

All coordinator state is anchored on `root.shared`, jac-scale's single public
commons graph. Note the distinction — the general rule cuts the other way, and
the `jac-sv-multi-user` guide says so plainly: *"Anonymous callers land on the
guest graph, token-holders on their own root — so a `:pub` 'global graph' isn't
even one graph."* That applies to `here` / `root`. `root.shared` is the
exception the same guide documents: the one public commons that *"resolves to
it from any request context"*.

Verified live on jac-scale 0.2.31: a registered, logged-in user (own `root_id`)
calling `network_status` with `Authorization: Bearer <jwt>` saw a job created
anonymously, and a worker registered *with* that token was visible to a later
anonymous read.

**This holds only because every walker ability anchors on `root.shared`.** An
ability that touched `here` or `root` would land on the caller's own root and
silently fragment the grid. If you add a walker here, anchor it the same way;
authenticated clients must not assume shared state without `root.shared` or an
explicit `grant(...)`.

## Endpoints

`POST /walker/<name>` for each of:

| Walker | Body fields (besides `secret`) | Reports |
|---|---|---|
| `register_worker` | `hostname`, `worker_name`, `capabilities` | `worker_id`, `device_id`, wallet, reputation, `dead_after_seconds` |
| `heartbeat` | `worker_id`, `current_task_status` | liveness ack + the failure sweep it triggered |
| `create_job` | Contract A §4: `app_id`, `job_type`, `payload`, `partitioning`, `verification`, `budget`, `limits` | `job_id`, `status`, `task_count` |
| `get_job` | `job_id` | Contract A status: per-task `status`/`worker`/`paid`, `progress` |
| `get_job_result` | `job_id` | Contract A result: merged `results` + payment `receipt` |
| `next_task` | `worker_id` | the Contract B **task envelope** under `task` (or `task: null`) |
| `submit_result` | `task_id`, `result_envelope` | verification outcome, payment, reputation |
| `detect_failures` | optional `dead_after` | dead/suspect workers and every task it requeued |
| `audit_job` | `job_id` | the full execution tree: job → tasks → attempts → worker/sandbox/result/verification/payment |
| `network_status` | — | devices, workers, liveness, wallets, jobs |

### Example: submit a job, watch it, collect the receipt

```bash
K='{"secret":"jacgrid-dev-key"'

# 1. submit (4 items, one item per task)
curl -s -X POST localhost:8000/walker/create_job -H 'Content-Type: application/json' -d '{
  "secret": "jacgrid-dev-key",
  "app_id": "matching-app",
  "job_type": "noop",
  "payload": {"items": [{"id":"i1","text":"a"},{"id":"i2","text":"b"},
                        {"id":"i3","text":"c"},{"id":"i4","text":"d"}]},
  "partitioning": {"strategy": "chunk", "chunk_size": 1},
  "verification": {"method": "recompute_sample", "sample_rate": 1.0},
  "budget": {"max_total": 1.0, "price_per_task": 0.1, "currency": "TESTUSD"}
}' | jq -c '.data.reports[0]'
# -> {"job_id":"job-dbf26e8a","status":"queued","task_count":4}

# 2. poll
curl -s -X POST localhost:8000/walker/get_job -H 'Content-Type: application/json' \
  -d '{"secret":"jacgrid-dev-key","job_id":"job-dbf26e8a"}' | jq -c '.data.reports[0]'

# 3. results + payment receipt (only once status == "complete")
curl -s -X POST localhost:8000/walker/get_job_result -H 'Content-Type: application/json' \
  -d '{"secret":"jacgrid-dev-key","job_id":"job-dbf26e8a"}' | jq '.data.reports[0].receipt'

# 4. the whole execution tree
curl -s -X POST localhost:8000/walker/audit_job -H 'Content-Type: application/json' \
  -d '{"secret":"jacgrid-dev-key","job_id":"job-dbf26e8a"}' | jq '.data.reports[0]'

# 5. who is on the grid right now
curl -s -X POST localhost:8000/walker/network_status -H 'Content-Type: application/json' \
  -d '{"secret":"jacgrid-dev-key"}' | jq '.data.reports[0].workers'
```

## Behaviour worth knowing

- **Pull dispatch.** Workers ask for work; `next_task` picks the FIFO-oldest
  queued task the worker's declared `job_types` supports and whose
  `excluded_workers` list does not contain it.
- **Self-healing without a cron.** `next_task` and `heartbeat` each run the
  failure sweep before doing their own job, so a stranded task becomes
  schedulable again on the very next worker poll. `detect_failures` exposes the
  same sweep explicitly for a scheduler or for the demo.
- **Liveness uses coordinator receive time only** — worker clocks are never
  trusted.
- **Contract B is enforced at the door.** `submit_result` rejects any envelope
  that is missing `status` / `output` / `execution`, carries a status outside
  `ok|error|timeout|limit_exceeded`, or ships an `execution` block missing any
  of `runtime`, `started_at`, `finished_at`, `peak_memory_mb`, `cpu_seconds`,
  `exit_code`. The reply is `{"error": "protocol_violation", ...}` listing the
  missing fields. Nothing enters the graph and the Attempt is left untouched,
  so the task stays `running` and is reassigned by the normal timeout path — a
  malformed submission can never be verified or paid.
- **`price_per_task` is frozen on the Task node at creation**; `create_job`
  rejects a submission whose `price_per_task × task_count` exceeds
  `budget.max_total`.
- **Payment is the `SimulatedLedger`**: Wallet nodes hold balances, the
  coordinator wallet is seeded with 10000 TESTUSD, and each Payment node carries
  a uuid `tx`. Swapping in a real testnet only changes `ledger_pay()` in
  `src/model.jac`.
- **Verification** (`run_verification`): `recompute_sample` on a `noop` job
  re-derives the echo and compares it item by item; on an `embedding` job it
  checks vector structure and dimension and leaves a `TODO(verify-recompute)`
  hook (`recompute_embedding_items`) for the real model recompute at
  integration. `output_hash` is fully implemented.

## Run a sweeper alongside it (recommended)

Spec §2.4 wants the failure sweep every 5s regardless of traffic. The
coordinator **cannot** schedule that internally on this stack — see the long
note at the top of `main.sv.jac`: jaclang's `@schedule` builtin does register
background tasks, but a scheduled *walker* fails every tick with
`Invalid walker object`, and a scheduled *function* runs in a deliberately
isolated context whose graph writes are never committed. Both were tried live.

So drive the sweep from outside the process, through the ordinary endpoint:

```bash
cd platform/worker && JACGRID_MODE=sweeper ../../.venv/bin/jac run main.jac
```

or equivalently

```bash
while true; do
  curl -s -X POST localhost:8000/walker/detect_failures \
    -H 'Content-Type: application/json' -d '{"secret":"jacgrid-dev-key"}' >/dev/null
  sleep 5
done
```

One sweeper per grid. Without it the network still self-heals via the implicit
sweeps inside `next_task`/`heartbeat` — but only while at least one worker is
alive and polling. The sweeper covers the case where **every** worker has died.

## Tests

```bash
bash tests/integration/e2e_noop.sh       # M1: full lifecycle, verified + paid
bash tests/integration/e2e_reassign.sh   # M3: kill a worker, task reassigned
bash tests/integration/e2e_sweeper.sh    # §2.4: heals with NO worker alive
bash tests/integration/e2e_contract_b.sh # §5: malformed envelopes rejected
```
