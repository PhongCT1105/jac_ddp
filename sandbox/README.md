# Sandbox layer

Owner: Luke/Santhos workstream. Generic, safe execution of approved workload
packages on a worker Mac — Contract B (Task Execution API) in
`docs/architecture.md` §5. **This layer owns no workload-specific logic.**
It does not know what an embedding is; it knows how to run a manifest-declared
entrypoint under limits and hand back a well-formed result envelope. The one
workload it does own (`fixtures/noop`) is a platform test fixture, not an
application.

## Layout

```text
sandbox/
  runner/
    harness.jac       # sandbox_run(task_envelope) -> result_envelope (the public API)
    execute.jac        # generic subprocess launch + wall/cpu/memory enforcement
    registry.jac        # job_type -> approved workload resolution
    allowlist.json       # job_type -> {workload_id, version, manifest path}
  profiles/
    seatbelt.sb          # macOS Seatbelt (sandbox-exec) profile, JACGRID_SEATBELT=1
  fixtures/
    noop/1.0.0/
      workload.json       # Contract C-shaped manifest for the built-in fixture
      runner.jac           # generic entrypoint-contract reference implementation
  tests/
    envelopes/*.json        # hand-written Contract B task envelopes
    run_tests.jac             # jac test suite exercising every result status
    run_tests.sh               # driver script (see "Running the tests")
  work/                        # per-task scratch workdirs, created + wiped at runtime
```

## Public API

```jac
import from sandbox.runner.harness { sandbox_run }

result_envelope: dict[str, any] = sandbox_run(task_envelope);
```

`sandbox_run` takes one Contract B task envelope (`task_id`, `job_type`,
`payload`, `limits`) and returns one Contract B result envelope (`task_id`,
`status`, `output`, `execution`, `error`) — see
`contracts/task-execution/v1/`. **It never raises and never hangs.** Every
failure mode — unknown job_type, launch failure, timeout, resource limit,
non-zero exit, malformed output — is caught and mapped to a well-formed
envelope with the mandatory `execution` block populated (even when no
workload ever ran, `execution.runtime` is `"sandbox-harness:v1"` and
`exit_code` is `-1`).

This is the exact signature the worker runtime imports; do not change it
without coordinating with the worker/coordinator owner.

## The generic invocation mechanism

`sandbox_run` never contains an `if job_type == "embedding"` branch. Instead:

1. `runner/registry.jac` looks up `task_envelope["job_type"]` in
   `runner/allowlist.json`. Unknown job_type → immediate `error` envelope,
   no subprocess ever launched.
2. The allowlist entry points at a workload's `workload.json` manifest
   (Contract C shape — `contracts/workload/v1/`). The manifest's
   `entrypoint` field (a path relative to the manifest's own directory) is
   what actually gets executed.
3. `runner/harness.jac` creates a per-task workdir under `sandbox/work/`,
   writes the task envelope's `payload` (plus `task_id`) to `task.json`
   inside it, and launches `<jac_bin> run <entrypoint>` as a subprocess
   with `cwd` set to that workdir and `JACGRID_WORKDIR` / `JACGRID_TASK_ID`
   in its environment.
4. `runner/execute.jac` polls the subprocess for wall-clock, RSS, and CPU
   time against the envelope's `limits` (falling back to the workload
   manifest's `resource_requirements` if a limit is omitted), killing the
   whole process group on any violation.
5. On a clean exit (code 0), it reads `<workdir>/result.json` and returns
   it as `output`. Any other outcome maps to `error` / `timeout` /
   `limit_exceeded` per the table below.
6. The workdir is wiped (`shutil.rmtree`) after every run unless
   `JACGRID_KEEP_WORKDIR=1` is set (debugging only).

**Registering a new workload requires zero sandbox code changes** — add one
entry to `runner/allowlist.json` pointing at the new workload's manifest.
That's the whole integration surface for the real `connection-embedding`
package once it ships to `workloads/connection-embedding/`.

### Entrypoint contract (what every workload's `entrypoint` must do)

Any workload registered in the allowlist must ship an entrypoint script
that:

- reads `JACGRID_WORKDIR` from the environment,
- reads `<workdir>/task.json` for its input (the task envelope's `payload`),
- writes `<workdir>/result.json` with its output object, and
- exits `0` on success (any other exit code is treated as `error`, and a
  clean exit with no `result.json` is also an `error`).

`fixtures/noop/1.0.0/runner.jac` is the reference implementation of this
contract — read it before writing a real workload's entrypoint.

### Failure mapping (Contract B statuses)

| Event | `status` |
|---|---|
| Unknown/unapproved `job_type` | `error` (no subprocess launched) |
| Subprocess fails to launch | `error` |
| Runner exits non-zero, or exits 0 with no/invalid `result.json` | `error` |
| Wall-clock (`limits.wall_seconds`) exceeded | `timeout` |
| RSS (`limits.memory_mb`) or CPU time (`limits.cpu_seconds`) exceeded | `limit_exceeded` |
| Runner exits 0 with valid `result.json` | `ok` |

## Resource enforcement

Wall-clock, RSS, and CPU are all enforced by a ~100ms poll loop in
`runner/execute.jac` (not `setrlimit`/`RLIMIT_CPU`, which is unreliable
across the Jac subprocess tree on macOS) — on any violation the harness
`SIGKILL`s the whole process group (`os.killpg` on a session started via
`start_new_session=True`), so a wedged workload cannot become a wedged
worker. RSS/CPU sampling uses `psutil` (installed into `.venv` for this
task — `uv pip install --python .venv/bin/python psutil`) summed over the
workload process and all its children; if `psutil` is ever unavailable,
RSS falls back to shelling out to `ps` (direct pid only, not children) and
`cpu_seconds` degrades to `0.0` — presence of the field matters more than
precision here (see `docs/luke-sandbox/spec.md` §4).

## Seatbelt profile (`JACGRID_SEATBELT=1`)

Set `JACGRID_SEATBELT=1` in the worker's environment to run every task
under `sandbox/profiles/seatbelt.sb` via `sandbox-exec`. **Verified working
on this machine** (macOS 26.5.1 / 25F80, Darwin 25.5.0): outbound network
is denied (`deny network*` — proven by `sandbox/tests/run_tests.jac`'s
Seatbelt test, which has the noop fixture attempt a real HTTPS request and
asserts it fails only when `JACGRID_SEATBELT=1`), and writes outside the
task's own workdir are denied (`deny file-write* (require-not (subpath
(param "WORKDIR")))`).

**Deviation from the spec's original sketch, and why:** `docs/luke-sandbox/spec.md`
§2 sketches a `(deny default)` profile with narrow `(allow file-read*
(subpath ...))` for the runtime + workdir. That was tried first and is
**verified broken on this OS build**: the instant a profile combines `(deny
default)` with *any* `(subpath ...)`/`(literal ...)` filter — even just
`(allow file-read* (subpath "/usr/lib"))` — `dyld` itself aborts before the
target binary's first instruction runs (`SIGABRT` in
`dyld4::CacheFinder::CacheFinder`, confirmed from
`/Library/Logs/DiagnosticReports/echo-*.ips`). This reproduces for
`/bin/echo`, not just `jac` — it is a platform incompatibility between
classic deny-default Seatbelt profiles and this OS build's dyld bootstrap,
not something fixable by adjusting the allow-path list. Per the spec's own
§7 risk mitigation ("if stuck, ship R1 + `deny network*` only"), the
shipped profile instead starts from `(allow default)` (verified: dyld
initializes normally) and layers two independently-verified denials on
top — network, and writes outside the workdir. Read access outside the
workdir is **not** jailed on this build; if you're iterating on this later
on a different macOS version, retrying the full deny-default + narrow-allow
form is the natural next step (see the comment block at the top of
`profiles/seatbelt.sb` for the exact reproduction).

Isolation rung reached: **R2, network + write scope; read-jail deferred**
(documented platform limitation above), R1 (limits + crash containment)
fully working underneath it regardless of `JACGRID_SEATBELT`.

## Running the tests

```bash
sandbox/tests/run_tests.sh
```

This wraps `jac test sandbox/tests/run_tests.jac -v`. Direct invocation of
`jac test` needs the repo root on `PYTHONPATH` — unlike `jac run`, `jac
test <file>` does not add it automatically when the target module uses a
no-dot (project-root-absolute) import — hence the driver script:

```bash
PYTHONPATH="$(pwd):$PYTHONPATH" .venv/bin/jac test sandbox/tests/run_tests.jac -v
```

Seven tests, covering: happy path (`ok`), hang → `timeout`, memory hog →
`limit_exceeded`, non-zero exit → `error`, unknown `job_type` → `error`,
malformed envelope (never raises), and the Seatbelt network-denial proof
(auto-skips as a trivial pass if `sandbox-exec` isn't on `PATH`).

## Environment variables

| Var | Meaning |
|---|---|
| `JACGRID_WORKDIR` | Set by the harness for the workload subprocess: its scratch directory (`task.json` in, `result.json` out). |
| `JACGRID_TASK_ID` | Set by the harness for the workload subprocess: the task's id, for logging. |
| `JACGRID_SEATBELT` | Set to `1` by the *caller* of `sandbox_run` (worker runtime) to wrap every task in the Seatbelt profile. |
| `JACGRID_KEEP_WORKDIR` | Set to `1` to skip workdir cleanup after a run — debugging only. |

## What changed from the round-1 (pre-reorg) sandbox code

The first pass at this layer (flat `sandbox/runners/noop.jac`,
`sandbox/setup.sh`, `sandbox/setup_models.jac`, `sandbox/models/`) assumed
the sandbox would own the embedding runner directly. `docs/workload-ownership-decision.md`
corrected that: the embedding algorithm belongs to Sebastian's application
team (`workloads/connection-embedding/`), and this layer only installs,
allowlists, and safely invokes whatever workload it's handed. Salvaged: the
noop echo behavior (now `fixtures/noop/1.0.0/runner.jac`, extended with
`crash`/`hang`/`memory_hog`/`network` test modes so one fixture can drive
every harness failure path). Discarded: the sentence-transformers-specific
`setup.sh`/`setup_models.jac`/model cache — pre-downloading model weights is
now that workload package's own responsibility, not a generic sandbox
concern.
