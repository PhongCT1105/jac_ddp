# connection-agent

The matching application — JacGrid's first product (Sebastian's workstream).
People describe themselves; the app finds the best matches in the pool and
explains why, using embeddings computed by the JacGrid distributed compute
network (Contract A) and a local cosine + tag-boost match engine.

This is the narrow JacGrid integration slice (`docs/sebastian-application/spec.md`
§4) — profile CRUD, the job client, and matching — not the full connection
product (chat, consent, moderation, etc. are out of scope here).

## Layout

```text
apps/connection-agent/
  jac.toml            # own Jac project (kind = api-service)
  main.sv.jac          # entry point — MUST stay at the project root, see below
  src/
    jacgrid_client.jac  # Contract A job client: MockJacGrid + LiveJacGrid
  web/
    index.html          # single-page frontend (pool -> progress -> results)
  tests/
    e2e_mock.sh          # runnable end-to-end proof, mock mode
```

**Why `main.sv.jac` is at the project root and not in `src/`:** jac-scale
derives the per-project user/auth database's location (`.jac/data/users.db`
— what backs `root.shared`'s guest-root bootstrap) from the *entry file's*
directory, while the graph anchor store (`.jac/data/anchor_store.db`) is
derived from the *project root*. Those only coincide when the entry file
lives at the project root. This was verified the hard way: with the entry
point at `src/main.sv.jac`, every `root.shared` access failed with a
deterministic `{"detail": "Invalid anchor id ... !"}` 500, on a totally
fresh `.jac/data`, every single time — because the guest root's id was
being resolved against `src/.jac/data/users.db` while the actual graph
lived in `.jac/data/anchor_store.db` at the project root. Moving the entry
file to the root fixed it immediately. See the comment block at the top of
`main.sv.jac` for the full story, and keep this in mind if you ever move it
again.

## Run it (mock mode — no coordinator needed)

```bash
cd apps/connection-agent
JACGRID_MODE=mock ../../.venv/bin/jac start main.sv.jac --no_client --port 8080
```

Then either:
- Open `web/index.html` directly in a browser (`file://...`), and set the
  "API base" field to `http://127.0.0.1:8080`. CORS is wide open on the
  jac-scale dev server (`access-control-allow-origin: *`), verified with a
  real cross-origin `Origin: null` request, so a `file://` page can call it.
- Or just drive it with curl / the Swagger UI at `http://127.0.0.1:8080/docs`.

Walkers (all `walker:pub`, no auth — see `jac-baseline.md`):

- `create_profile(name, bio, tags)` / `list_profiles()` / `get_profile(id)`
- `seed_profiles(force=False)` — loads `data/profiles.json` (100 seeded
  attendees, relative to this project's cwd: `../../data/profiles.json`) or
  falls back to 12 inline placeholders if that path isn't reachable.
- `find_matches(profile_id)` — embeds any profile still missing an
  embedding (`bio + " " + joined tags`) via the job client, stores the
  `job_id` on every profile embedded in that job.
- `match_status(profile_id)` — proxies job status (Contract A §4 shape) for
  the progress UI.
- `get_matches(profile_id, top_n=3)` — cosine top-N excluding self, with a
  `looking_for`-tag complementary boost and a `why_matched` breakdown
  (shared vs. complementary tags), plus the job's compute receipt.

## Job client (Contract A) — `src/jacgrid_client.jac`

One interface (`JacGridClient`), switched by env var `JACGRID_MODE`:

- **`mock` (default)** — `MockJacGrid`: deterministic pseudo-embeddings
  (seeded SHA-256 hash → 384 floats, same scheme as the workload package's
  fallback path) computed synchronously at submit time; `poll()` then
  simulates progress across 4 fake tasks on `mac1`/`mac2`/`mac3` — first
  poll `running` (1/4 done), second `running` (2/4 done), third+
  `complete` — with a receipt of `0.10 TESTUSD` per task. Set
  `JACGRID_USE_ST=1` to use the real `all-MiniLM-L6-v2` model instead, if
  sentence-transformers imports cleanly (still deterministic per text).
- **`live`** — `LiveJacGrid`: real HTTP against `JACGRID_COORDINATOR`
  (default `http://127.0.0.1:8000`), hitting `/walker/create_job`,
  `/walker/get_job`, `/walker/get_job_result` with
  `secret: "jacgrid-dev-key"` in the body — matches exactly what
  `platform/coordinator/main.sv.jac` exposes. Unwraps the 0.16 response
  envelope (`data.reports[0]`). Built to contract; not yet integration-run
  against a live coordinator process (that's the next milestone, S-M4).

## Frontend — `web/index.html`

Self-contained HTML+JS, three screens per the spec:

1. **Pool** — seed/refresh buttons, a scrollable grid of profile chips
   (click to select), a "Find my matches" button.
2. **Progress** — polls `match_status` every ~900ms, renders each task's
   worker + status (queued/running/complete) with a pulsing dot and a
   progress bar.
3. **Results** — top-N match cards (name, bio, score, shared/complementary
   tag chips) and the compute receipt line: *"This match run cost 0.40
   TESTUSD across 3 machines (4/4 tasks verified)."*

The API base is configurable in the UI (persisted to `localStorage`) so the
same page works against any port/host without editing the file.

## Proof — `tests/e2e_mock.sh`

Serves the app in mock mode on a scratch port, seeds the pool, then drives
the full flow over curl exactly like the UI would: `create_profile` ->
`find_matches` -> poll `match_status` until `complete` -> `get_matches`,
asserting matches come back non-empty and the receipt's `total_paid > 0`.
Cleans up its own server process on exit (including on failure).

```bash
./tests/e2e_mock.sh
```

Last run: **ALL CHECKS PASSED** — 100 profiles seeded from
`data/profiles.json`, embedding job completed after 3 polls, 3 matches
returned, receipt `total_paid = 0.4 TESTUSD` across 4 tasks / 3 machines.
The match quality on real seed data looks right too — a profile described
as "Python backend engineer building distributed systems and developer
tools" matched with other distributed-systems/backend/ML-infra profiles in
the 100-person pool, not random noise.

## Deviations from the original brief

- `app/` (round-1, jaclang 0.9-style) was deleted; this is a from-scratch
  0.16.7 port under the new `apps/connection-agent/` layout, not a
  line-for-line migration (syntax changed enough — `class __specs__` is
  gone, node filters are `[x-->][?:T]` not `` [x --> (`?T)] ``, `` `root
  entry `` → `Root entry` — that a rewrite was faster and safer than a
  patch).
- Contract A's LiveJacGrid talks to `/walker/create_job` /
  `/walker/get_job` / `/walker/get_job_result` (matching what
  `platform/coordinator` actually implements), not the `/api/jobs` REST
  path shown in `docs/architecture.md` §4's illustrative examples — the
  architecture doc itself says the walker names are the real contract
  (§7's data-flow narrative and the coordinator's own docstrings confirm
  this), and it's what the other workstream actually built.
- `round(x, digits)` (two-arg form) does not type-check under jaclang
  0.16.7 (E1054, no matching overload) in this repo's toolchain — same gap
  `platform/coordinator` hit. Worked around identically: a `PY_ROUND: any
  = round;` alias called through and cast back, in both this app and the
  `connection-embedding` workload.
