# Sebastian — Task Breakdown

Workstream: **Matching application** (the product that consumes JacGrid).

You are unblocked from hour zero: build the application against `MockJacGrid`, build the workload against the local Contract C harness, and swap both to the live JacGrid path at integration time.

## Phase 1 — App skeleton (S-M1)

- [ ] **A1. Scaffold** — app backend + frontend framework choice (fastest you're fluent in); profiles store (SQLite/JSON).
- [ ] **A2. Profile create/edit** — name, free-text bio, tags (skills / interests / looking-for).
- [ ] **A3. Seed dataset** — ~100 believable hackathon-attendee profiles (LLM-drafted, hand-curated).
- [ ] **A4. Pool view** — list/grid of participants with count.
- [ ] **A5. `connection-embedding:1.0.0` workload** — implement the application-owned embedding entrypoint, immutable manifest, exact model artifact/revision, schemas, resource requirements, verification tolerance, and deterministic fixtures. It must run locally without Phong's coordinator or the Luke/Santhos sandbox.
- [ ] ✅ **Checkpoint S-M1.**

## Phase 2 — Matching flow on mock (S-M2)

- [ ] **A6. Job client interface + `MockJacGrid`** — `submit_embedding_job / poll / fetch_results`; the mock invokes the exact application workload behind fake task-progress states so the progress UI is buildable.
- [ ] **A7. "Find my matches" flow** — build items from profiles missing embeddings, submit, store `embedding_job_id`.
- [ ] **A8. Progress view** — poll job status; render per-task states (queued/running/complete + which worker). This screen is demo Beat 2's app side — make it look alive.
- [ ] **A9. Match engine** — cosine top-N (exclude self), looking-for tag boost, why-matched via shared tags (bio-phrase similarity = stretch).
- [ ] **A10. Results view** — top-3 matches with score, why-matched, and the **compute receipt** ("cost 0.40 TESTUSD across 3 machines").
- [ ] ✅ **Checkpoint S-M2:** full flow works on mock.

## Phase 3 — Quality pass (S-M3)

- [ ] **A11. Match-quality tuning** — eyeball top matches on seed data; adjust text construction (bio+tags weighting) until matches are defensible on stage.
- [ ] **A12. Demo polish** — the three screens shown live (pool → progress → results) get the styling time; everything else stays plain.
- [ ] ✅ **Checkpoint S-M3.**

## Phase 4 — Go live (S-M4)

- [ ] **A13. `LiveJacGrid` client** — real Contract A calls with the shared-secret header; config-switch between mock and live.
- [ ] **A14. Integration with Luke/Santhos** — install the unchanged application workload package in the sandbox and run the shared fixtures through Contract C.
- [ ] **A15. Integration with Phong** — submit against the live coordinator (= Phong's P14); verify fixture embeddings match the application-owned local workload.
- [ ] **A16. End-to-end demo rehearsal** — full Beat 2 + Beat 5 run on the demo network, including the kill-a-worker run (your progress view should visibly show the reassignment).
- [ ] ✅ **Checkpoint S-M4.**

## Stretch

- [ ] **AS1.** Why-matched via closest bio-sentence pairs.
- [ ] **AS2.** Live attendee sign-up during the demo (QR code → profile form → they appear in the pool).
- [ ] **AS3.** Webhook completion instead of polling.

## Interfaces

| With | What | When |
|---|---|---|
| Phong | Receive frozen Contract A (payload/result shapes) | End of Phong Phase 1 |
| Phong | Live coordinator URL + shared secret; joint integration | Phase 4 |
| Luke/Santhos | Deliver `connection-embedding:1.0.0`, its manifest, fixtures, model artifact, and resource requirements | Before sandbox integration |
