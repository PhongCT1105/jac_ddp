# Sandbox Layer — Spec

**Owner: Luke/Santhos**

The sandbox layer is what makes it safe for a Mac to run someone else's workload. The worker runtime hands the sandbox a task envelope; the sandbox runs the workload in a restricted environment with resource limits and returns a result envelope with full execution metadata (Contract B in `../architecture.md` §5).

For the hackathon, only **allowlisted job types** run — the sandbox's job is to constrain even trusted code (limits, no network, metadata capture) and to establish the boundary that later makes arbitrary code possible.

---

## 1. Responsibilities

- Execute one task envelope at a time in a restricted environment on macOS.
- Enforce limits: wall time, CPU time, memory, no network (per the envelope's `limits`).
- Only run allowlisted immutable workloads (`connection-embedding:1.0.0`, `noop-runner:v1`; training workload stretch).
- Capture execution metadata (timings, peak memory, exit code) — this feeds the Sandbox/Attempt nodes in the Jac graph and the audit timeline.
- Fail safely: any violation or crash returns a well-formed result envelope with `status: error | timeout | limit_exceeded`, never a hung worker.

**Not responsible for:** talking to the coordinator (worker runtime does that), implementing application algorithms (Sebastian supplies them), task-content correctness (verification layer), or scheduling.

---

## 2. Isolation approach on macOS

Recommended ladder — climb it as time allows, each rung is demoable:

| Rung | Mechanism | Provides |
|---|---|---|
| **R1 (baseline)** | Subprocess with `setrlimit` (CPU, memory via RSS polling), wall-clock kill timer, clean env vars, dedicated temp workdir wiped after run | Resource limits, crash containment |
| **R2 (target)** | R1 + `sandbox-exec` profile (macOS Seatbelt): deny network, restrict filesystem to the task workdir + read-only runtime deps | Real OS-enforced confinement |
| **R3 (stretch)** | Container (Docker/OrbStack) or `container` CLI with the runner baked into an image | Portable, closest to production story |

`sandbox-exec` is deprecated-but-functional and is the fastest path to "deny network + filesystem jail" on stock macOS — strongly worth the R2 rung because "the workload physically cannot phone home" is a great demo line.

### Seatbelt profile sketch (R2)

```scheme
(version 1)
(deny default)
(allow process-exec process-fork)
(allow file-read* (subpath "/path/to/runtime"))       ; python + model weights, read-only
(allow file-read* file-write* (subpath "/path/to/task-workdir"))
(deny network*)
(allow sysctl-read)                                    ; what python needs to start
```

Iterate by running the embedding runner under the profile and allowing the minimal set it actually needs.

---

## 3. Interface (Contract B implementation)

Simplest robust shape: **directory-based invocation**.

```text
sandbox_run(task_envelope) -> result_envelope

1. mkdir workdir/{task_id}/
2. write task.json
3. launch the immutable workload entrypoint declared in its manifest
   (workload ID + version selected from the allowlist registry)
4. enforce wall timer; poll RSS for memory limit
5. runner writes result.json (the application `output` part, optionally plus
   reserved `__jacgrid_execution.runtime`)
6. if present, accept that runtime only when the immutable workload manifest
   declares it in `runtime_tags`; promote it into execution metadata and strip
   the reserved object so it cannot leak into application output
7. wrap with execution metadata → result envelope
8. wipe workdir
```

### Runner registry (allowlist)

```json
{
  "connection-embedding@1.0.0": {"manifest": "workloads/connection-embedding/1.0.0/workload.json"},
  "noop-runner@1.0.0":          {"manifest": "workloads/noop-runner/1.0.0/workload.json"}
}
```

Unknown job types, workload IDs, or workload versions produce an immediate structured error. Sebastian owns the code and fixtures inside `connection-embedding`; Luke/Santhos own installation, allowlisting, safe invocation, limits, and result-envelope wrapping.

### Failure mapping

| Event | Result envelope `status` |
|---|---|
| Runner exits 0, valid result.json | `ok` |
| Runner exits non-zero / bad output | `error` (+ stderr tail in `error`) |
| Wall clock exceeded → SIGKILL | `timeout` |
| RSS or CPU limit exceeded → SIGKILL | `limit_exceeded` |
| Seatbelt denial crash | `error` (+ denial info if visible) |

The sandbox must **always** return an envelope. A hung sandbox = a dead worker = a failed heartbeat, which is Phong's failure path — don't rely on it.

---

## 4. Execution metadata

Required in every envelope (Contract B `execution` block): `runtime`, `started_at`, `finished_at`, `cpu_seconds`, `peak_memory_mb`, `exit_code`. Source: `psutil` polling (or `resource.getrusage` on reap) — precision matters less than presence; the dashboard displays this per attempt.

---

## 5. Demo moment (owned by Luke/Santhos)

A 15-second beat inside demo Beat 4, or Q&A ammo:

1. Show a task's audit entry: *ran inside `embedding-runner:v1`, 19.4 cpu-seconds, 812 MB peak, network denied*.
2. Optional live proof: run a `noop` task whose runner tries `curl` — show it blocked by the Seatbelt profile.

---

## 6. Milestones

| # | Milestone | Proves |
|---|---|---|
| L-M1 | R1 runner harness executes `noop` plus Sebastian's supplied embedding workload locally with limits and metadata | Contracts B and C work standalone |
| L-M2 | Wall/CPU/memory kills produce correct envelope statuses | Fail-safe behavior |
| L-M3 | Seatbelt profile: network denied, filesystem restricted, embedding runner still works | Real isolation |
| L-M4 | Integrated with Phong's worker runtime on all three Macs | Full path |

## 7. Risks & mitigations

- **Seatbelt profile fights Python/ML libs** (they touch a lot of paths) → time-box to 90 min; iterate from a permissive profile toward strict; if stuck, ship R1 + `deny network` only (network is the headline anyway).
- **Model download inside sandbox** → never; model weights pre-downloaded to the read-only runtime path before any task runs.
- **Memory limits on macOS are advisory** (`RLIMIT_AS` unreliable) → poll RSS with psutil and SIGKILL over threshold; document as "enforced by supervisor".
- **Different Macs, different paths** → one `setup.sh` that installs the runtime venv + weights to a fixed location on every machine.
