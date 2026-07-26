# Luke/Santhos — Task Breakdown

Workstream: **Sandbox layer** (restricted task execution on worker Macs).

You can build and test this entire layer standalone — you only need Contract B's envelope shapes (frozen by end of Phong's Phase 1) and a sample task envelope, not a running coordinator.

## Phase 1 — Runner harness (L-M1)

- [ ] **L1. Project scaffold** — `sandbox/` module: `sandbox_run(task_envelope) -> result_envelope`, workdir lifecycle (create → run → wipe).
- [ ] **L2. Runner registry** — allowlist mapping immutable `workload_id@version` → workload manifest; unknown types or versions rejected with an `error` envelope.
- [ ] **L3. `noop` runner** — echoes payload; your integration-test workhorse.
- [ ] **L4. Application workload integration** — install and allowlist Sebastian's `connection-embedding:1.0.0` package, pass it the task payload, capture its output, and wrap it in Contract B's result envelope. Luke/Santhos do not implement the embedding algorithm. Use `noop` until the application package arrives.
- [ ] **L5. Execution metadata capture** — timings, exit code, peak RSS (psutil poll), cpu_seconds; assembled into the envelope.
- [ ] ✅ **Checkpoint L-M1:** feed a hand-written task envelope in, get a correct result envelope out.

## Phase 2 — Enforcement (L-M2)

- [ ] **L6. Wall-clock kill** — timer → SIGKILL process group → `status: timeout`.
- [ ] **L7. CPU + memory limits** — `setrlimit(RLIMIT_CPU)` + RSS polling with kill → `status: limit_exceeded`.
- [ ] **L8. Failure-path tests** — runners that hang, OOM, exit non-zero, emit garbage; each must yield a well-formed envelope. *The sandbox never hangs the worker.*
- [ ] ✅ **Checkpoint L-M2:** all failure modes mapped correctly.

## Phase 3 — Real isolation (L-M3)

- [ ] **L9. Seatbelt profile** — `sandbox-exec` profile: deny-default, allow runtime read-only + workdir read-write, `deny network*`. Iterate until the embedding runner passes. **Time-box: 90 min** — fallback is R1 + network denial only.
- [ ] **L10. Network-denial proof** — a test runner that attempts an HTTP call; capture it being blocked (demo/Q&A ammo).
- [ ] ✅ **Checkpoint L-M3:** embedding runner works fully sandboxed, network provably denied.

## Phase 4 — Integration (L-M4)

- [ ] **L11. `setup.sh`** — installs the sandbox runtime plus approved application workload packages and their pinned model artifacts to fixed paths; run it on all three Macs.
- [ ] **L12. Wire into worker runtime** — replace Phong's stub-runner call with `sandbox_run` (joint task, = Phong's P13).
- [ ] **L13. End-to-end soak** — full embedding job through real sandboxes on 3 Macs; check metadata shows up in the audit view.

## Stretch

- [ ] **LS1.** Containerized runner (Docker/OrbStack image) as rung R3.
- [ ] **LS2.** `training-runner:v1` for the `training_shard` job type (pairs with Phong's S4).
- [ ] **LS3.** Per-task disk quota on the workdir.

## Interfaces

| With | What | When |
|---|---|---|
| Phong | Receive frozen Contract B envelopes + share the generic `noop` reference runner | End of Phong Phase 1 |
| Phong | Joint swap-in of sandbox on all workers | Phase 4 |
| Sebastian | Receive immutable workload package, manifest, fixtures, and resource requirements; confirm it runs unchanged in the sandbox | Before L4 integration |
