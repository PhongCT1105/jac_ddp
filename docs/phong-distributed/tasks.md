# Phong — Task Breakdown

Workstream: **Distributed compute layer** (coordinator, workers, Jac graph, scheduling, verification, payment).

Ordered for dependency; each phase ends at a milestone from `spec.md` §4.

## Phase 1 — Skeleton (M1)

- [ ] **P1. Jac graph model** — define all nodes and edges from `../architecture.md` §3 in Jac.
- [ ] **P2. Coordinator HTTP layer** — serve the endpoints table (spec §2.1). Spike Jac-native serving first; fall back to FastAPI shim if blocked after ~45 min.
- [ ] **P3. `create_job` + `split_job` walkers** — accept Contract A payload, validate, create Job + Task nodes (chunk partitioning).
- [ ] **P4. Worker runtime v0** — registration + heartbeat + pull loop + stub runner (plain subprocess, no sandbox), running on Mac 1 only.
- [ ] **P5. `select_worker` + `assign_task`** — FIFO pull dispatch; Attempt nodes created.
- [ ] ✅ **Checkpoint M1:** `noop` job via curl completes on one machine.

## Phase 2 — Distribution & recovery (M2–M3)

- [ ] **P6. Multi-machine bring-up** — workers on Mac 2 and Mac 3 pointed at Mac 1 by IP; shared-secret auth header.
- [ ] **P7. `monitor_heartbeat` + `detect_failure`** — liveness from coordinator receive-time; suspect 15s, dead 30s; deadline overrun detection.
- [ ] **P8. `reassign_task`** — excluded-workers list, max 3 attempts, job-level failure state.
- [ ] ✅ **Checkpoint M2/M3:** kill Mac 2 worker mid-job; job completes anyway. Rehearse this — it's demo Beat 3.

## Phase 3 — Economic loop (M4)

- [ ] **P9. Embedding runner (stub)** — sentence-transformers (or MLX) runner invoked by the worker; produces Contract B result envelopes. *Coordinate with Luke: this same runner becomes his allowlisted sandbox image.*
- [ ] **P10. `verify_result`** — `recompute_sample` with cosine ≥ 0.999; Verification nodes; failed verification re-queues + penalizes reputation.
- [ ] **P11. `SimulatedLedger` + `release_payment`** — Wallet + Payment nodes, per-task receipts, frozen `price_per_task`.
- [ ] **P12. `update_reputation`** — simple +1/−1 rolling score.
- [ ] ✅ **Checkpoint M4:** embedding job → verified → paid, visible balances.

## Phase 4 — Integration & demo surface (M5–M6)

- [ ] **P13. Swap in Luke's sandbox** — replace stub runner call with Contract B sandbox invocation. (Joint with Luke.)
- [ ] **P14. Point Sebastian at the live coordinator** — replace his mock; walk through Contract A together. (Joint with Sebastian.)
- [ ] **P15. `audit_job` + dashboard endpoints** — `/api/audit/{job}` and `/api/network` returning the execution-graph JSON the dashboard renders.
- [ ] **P16. Demo hardening** — pre-warm models, raw-IP config, hotspot fallback, record backup run video.

## Stretch (only if ahead)

- [ ] **S1.** Testnet `PaymentBackend` (real tx hashes in receipts).
- [ ] **S2.** Reputation-weighted scheduling.
- [ ] **S3.** `redundant_compute` verification demo.
- [ ] **S4.** `training_shard` job type (distributed training story).

## Interfaces you owe others

| To | What | When |
|---|---|---|
| Sebastian | Contract A frozen + a mock/real endpoint to hit | End of Phase 1 |
| Luke | Contract B envelopes frozen + the stub runner as reference implementation | End of Phase 1 |
| Both | Live coordinator on the demo network | Phase 4 |
