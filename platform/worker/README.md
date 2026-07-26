# JacGrid Worker

The runtime that turns a Mac into grid capacity. It registers with the
coordinator, heartbeats, pulls tasks, executes them, and posts back a
**Contract B result envelope**. This is its own Jac project (`kind = "cli"`);
everything lives in `main.jac`.

Reference: `docs/architecture.md` §5 (Contract B), `docs/phong-distributed/spec.md` §2.2.

## Run

```bash
cd platform/worker

../../.venv/bin/jac check .                                    # compile + typecheck
JACGRID_WORKER_SELFTEST=1 ../../.venv/bin/jac run main.jac     # offline runner self-test
JACGRID_COORDINATOR=http://127.0.0.1:8000 ../../.venv/bin/jac run main.jac   # join the grid
```

Run as many as you like — one per Mac in the demo, or several on one box with
different `WORKER_NAME`s.

## Configuration (environment variables)

| Var | Default | Meaning |
|---|---|---|
| `JACGRID_COORDINATOR` | `http://127.0.0.1:8000` | coordinator base URL |
| `JACGRID_KEY` | `jacgrid-dev-key` | shared secret sent as `secret` on every call |
| `WORKER_NAME` | hostname | worker identity on the grid |
| `WORKER_HOSTNAME` | hostname | the Device this worker is hosted on |
| `WORKER_JOB_TYPES` | `noop,embedding` | comma-separated `job_type`s this worker accepts |
| `JACGRID_HEARTBEAT` | `5` | seconds between heartbeats |
| `JACGRID_POLL` | `1` | seconds between `next_task` polls when idle |
| `JACGRID_HTTP_TIMEOUT` | `30` | per-request HTTP timeout |
| `JACGRID_EMBEDDING_DIM` | `384` | stub embedding dimension |
| `JACGRID_TASK_DELAY` | `0` | fake seconds of work per task (demo/test only) |
| `JACGRID_MAX_LOOPS` | `0` (forever) | stop after N loop iterations (tests) |
| `JACGRID_EXIT_WHEN_IDLE` | `0` | `1` = exit after `JACGRID_IDLE_LIMIT` idle polls (tests) |
| `JACGRID_IDLE_LIMIT` | `30` | idle polls before exiting when the above is set |
| `JACGRID_WORKER_SELFTEST` | `0` | `1` runs the offline runner self-test instead of joining |

## The loop

```text
register_worker                       (retries until the coordinator answers)
loop:
    heartbeat every JACGRID_HEARTBEAT seconds (with current task status)
    next_task
    if a task envelope came back:
        heartbeat "busy"
        run_task(envelope)            <-- THE swap point, see below
        submit_result(task_id, result_envelope)
        heartbeat "idle"
```

## The sandbox swap point

Task execution is isolated behind exactly **one** function, `run_task(envelope)`.
It takes a Contract B task envelope and returns a complete Contract B result
envelope, including the mandatory `execution` metadata block:

```json
{
  "task_id": "t-2", "status": "ok",
  "output": {"results": [{"id": "profile-026", "embedding": [0.013, ...]}]},
  "execution": {"runtime": "stub-runner:v0", "started_at": "...", "finished_at": "...",
                "peak_memory_mb": 0, "cpu_seconds": 0.4, "wall_seconds": 0.4, "exit_code": 0},
  "error": null
}
```

Today `run_task` dispatches to the local **stub runner** (`stub_run`), which has
no isolation:

- `noop` — echoes each input item back (integration testing only)
- `embedding` — a deterministic pseudo-embedding: a SHA-256 stream seeded with
  the item's text, folded into `JACGRID_EMBEDDING_DIM` floats and L2-normalised,
  tagged `runtime: "stub-runner:v0"`. The same text always yields the same
  vector, so coordinator-side recompute verification works against the stub.
- anything else — `status: "error"`, which the coordinator treats as a failed
  attempt and requeues.

At integration, `run_task` hands the same envelope to the Luke/Santhos sandbox
(`sandbox/`) and gets the same envelope shape back. **Nothing else in this file
changes** — that is the whole point of the single call site.

## Failure behaviour

The worker deliberately has no recovery logic of its own. If it dies mid-task,
no result and no heartbeat ever arrive; the coordinator declares it dead after
`JACGRID_DEAD_AFTER` seconds, fails the attempt, and requeues the task with this
worker on the `excluded_workers` list. It earns nothing for the dead attempt.
`tests/integration/e2e_reassign.sh` proves exactly that.

Transport errors are non-fatal: a failed call returns an in-band
`{"error": ...}` dict, the worker logs it and keeps polling, so a coordinator
restart does not require restarting workers (re-register manually if the
coordinator's graph was wiped).
