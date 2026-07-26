# connection-embedding

The versioned embedding workload supplied by the connection-agent app team
(Contract C, `docs/architecture.md` §6 and `docs/workload-ownership-decision.md`).
This package owns the ONE embedding algorithm in JacGrid — the coordinator
schedules and verifies it, the sandbox installs and invokes it, neither
reimplements it.

## What it does

Turns `{"id": ..., "text": ...}` items into 384-dimensional embedding
vectors using `sentence-transformers/all-MiniLM-L6-v2`, pinned to revision
`1110a243fdf4706b3f48f1d95db1a4f5529b4d41` (already cached locally — see
`jac-baseline.md`). If the model import or load fails for any reason, it
falls back to a deterministic seeded-hash scheme so a task still completes
with contract-shaped output — reported under a **different** runtime tag
(`connection-embedding-fallback:1.0.0` vs `connection-embedding:1.0.0`) so
the coordinator/verifier can tell which path actually ran.

## Invocation contract

Mirrors the file-I/O convention already used by `sandbox/runners/noop.jac`
and follows `docs/luke-sandbox/spec.md` §3 exactly: **the runner writes only
the `output` object; the sandbox is what wraps it into the full Contract B
result envelope.** This workload does not construct `task_id`/`status`/
`execution`/`error` on disk at all.

1. Caller creates a scratch directory and writes a Contract B task envelope
   (`docs/architecture.md` §5) to `<workdir>/task.json`.
2. Caller sets `JACGRID_WORKDIR=<workdir>` and runs `jac run src/embed.jac`.
3. **On success:** entrypoint writes `{"results": [{"id": ..., "embedding": [...]}]}`
   — and only that — to `<workdir>/result.json`, exits 0.
4. **On failure:** entrypoint writes NOTHING to `result.json`, prints a
   human-readable reason to stderr, exits non-zero. The sandbox's own
   "runner exits non-zero / bad output → `status: error`" path (spec §3's
   Failure mapping table) is what builds the error envelope — this
   workload never fakes one.

```bash
mkdir -p /tmp/work
cat > /tmp/work/task.json <<'EOF'
{"task_id": "t-1", "job_type": "embedding",
 "payload": {"model": "all-MiniLM-L6-v2",
             "items": [{"id": "profile-001", "text": "ML engineer who loves climbing"}]}}
EOF
JACGRID_WORKDIR=/tmp/work ../../.venv/bin/jac run src/embed.jac
cat /tmp/work/result.json   # {"results": [{"id": "profile-001", "embedding": [...]}]}
```

The entrypoint forces `HF_HUB_OFFLINE=1` / `TRANSFORMERS_OFFLINE=1` itself
(task `limits.network` is always `"none"` — see `workload.json`), so it
never phones home even if the sandbox doesn't set those env vars.

`run_task(task: dict) -> dict` in `src/embed.jac` is the pure, file-I/O-free
core and still returns the FULL internal envelope shape (`task_id`,
`status`, `output`, `execution`, `error`) — that's what the 6 tests below
exercise directly, and what any future in-process caller (recompute-sample
verification) should call instead of shelling out. The
`with entry:__main__` block is the only place that narrows `run_task`'s
result down to the on-disk output-only contract described above.

**Known limitation:** because the on-disk contract only carries `results`,
the primary-vs-fallback runtime distinction (`connection-embedding:1.0.0`
vs `connection-embedding-fallback:1.0.0`) doesn't reach the sandbox's
wrapped envelope — it's only visible via a stderr line
(`connection-embedding: ok, runtime=...`). The sandbox's own
`execution.runtime` will reflect whichever workload id it invoked from its
allowlist registry, not which internal code path actually ran. Flagged for
Phong/Luke-Santhos as a follow-up if the demo wants that distinction
visible in the audit trail.

## Manifest

`workload.json` is the Contract C manifest: entrypoint, pinned model
revision, locked dependency versions, input/output JSON Schemas, resource
requirements (matches the architecture doc's example task-envelope limits),
verification tolerance (`cosine_similarity_min >= 0.999` — real-model
embeddings are deterministic per machine but float32 BLAS reductions can
differ in the last few bits across CPU/GPU backends, so bit-exact equality
is not the bar), and fixture references.

## Tests

```bash
../../.venv/bin/jac test src/embed.jac -v
```

6 tests, all pure-function (no file I/O, no coordinator, no sandbox):

- Fallback hash embeddings match an independently-computed golden fixture
  exactly (cosine > 0.999999) — proves the deterministic scheme really is
  deterministic.
- Bad `job_type`, empty `items`, and malformed items all return
  Contract-B-shaped `status: "error"` results instead of raising.
- A full 3-item task produces a contract-shaped `status: "ok"` envelope
  with 384-d embeddings and a complete `execution` block.
- If the primary model path ran, its output matches a golden fixture
  (generated once via this exact entrypoint against the pinned
  model/revision) within the declared verification tolerance.

Fixtures live in `tests/fixtures/`:

- `task-embedding.json` — 3 short bio-style texts (Contract B task envelope).
- `expected-fallback.json` — golden output of the hash fallback scheme,
  computed independently in plain Python from the same formula as
  `_hash_embed`.
- `expected-model.json` — golden output of the pinned real model, captured
  once by actually running this entrypoint offline.
- `task-bad-job-type.json` — an unsupported `job_type` for the error-path test.

## Dependencies

`sentence-transformers` 5.6.1 / `torch` 2.13.0 / `numpy` 2.5.1 / Python 3.12
— all already present in the repo's shared `.venv` (see `jac-baseline.md`);
this project's `jac.toml` declares them for documentation, `jac install`
was not run against the shared venv to avoid disturbing it.
