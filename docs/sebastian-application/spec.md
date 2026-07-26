# Matching Application — Spec

**Owner: Sebastian**

The matching application is the first real product on JacGrid. It is Sebastian's original matching idea, kept intact — profiles in, meaningful human connections out — with one architectural change: **all heavy compute (embedding generation) is purchased from the JacGrid network instead of run locally.** The app submits an embedding job through Contract A, gets verified vectors back, and does the matching on top.

This makes the app the proof that JacGrid works: a product that consumes distributed compute the way apps consume Stripe.

---

## 1. Product concept

People describe themselves (interests, what they're working on, who they want to meet). The app finds the best matches among all participants and explains why. Demo persona: **hackathon attendee matching** — "find me the 3 people here I should talk to" — which lets the demo audience *be* the dataset (or use ~100 seeded profiles).

### User flow

```text
1. Create profile (name + free-text bio + optional tags: skills, interests, looking-for)
2. Browse the pool (see how many participants)
3. Click "Find my matches"
4. App shows: matching job running on the JacGrid network (live task status)
5. Results: top-N matches with similarity score + why-matched snippets
```

Step 4 is deliberate UI: the app *shows* the distributed network working — this is where the two demos connect.

---

## 2. Architecture

```text
┌──────────────┐     ┌───────────────────────┐     ┌──────────────────┐
│  Frontend    │────▶│  App backend          │────▶│  JacGrid          │
│  (web UI)    │     │  profiles store       │ A   │  coordinator      │
│              │◀────│  match engine         │◀────│  (Contract A)     │
└──────────────┘     │  job client           │     └──────────────────┘
                     └───────────────────────┘
```

### Components

**Frontend** — a simple web UI (whatever is fastest: plain HTML+JS, React, or Streamlit). Screens: profile form, pool view, matching-progress view (polls job status and renders per-task progress), results view.

**Profiles store** — SQLite or a JSON file. Fields: `id`, `name`, `bio`, `tags[]`, `embedding` (filled after job completion), `embedding_job_id`.

**Job client** — the only place that talks to JacGrid (Contract A, `../architecture.md` §4):

```text
submit_embedding_job(items) -> job_id        POST /api/jobs
poll(job_id) -> status + task progress       GET  /api/jobs/{id}
fetch_results(job_id) -> vectors + receipt   GET  /api/jobs/{id}/result
```

Design rule: the job client is an interface with two implementations — `MockJacGrid` (returns locally-computed embeddings after a fake delay, with fake task-progress states) and `LiveJacGrid`. Sebastian builds the entire app against the mock and swaps in live at integration time.

**Match engine** — pure local computation on returned vectors:

- Cosine similarity across all profile pairs (≤ a few hundred profiles → a NumPy one-liner).
- Top-N per person, excluding self.
- Optional intent-awareness: if `looking-for` tags are present, boost pairs whose tags complement (e.g. "looking for designer" × "is designer").
- Why-matched: show the overlapping tags and the closest bio phrases (nearest sentence pair between the two bios — reuse the embedding model locally, or just show shared tags for the MVP).

---

## 3. Embedding job details

- One item per profile: `{"id": profile_id, "text": bio + " " + tags joined}`.
- Model: `all-MiniLM-L6-v2` (agreed with Phong/Luke — the allowlisted runner's model; must match exactly, since JacGrid verification recomputes samples).
- Chunking (`chunk_size`) is the coordinator's concern; the app just sends items.
- Incremental behavior: on "Find my matches," embed only profiles without a stored embedding (new/edited), then match across all. First demo run embeds everything — that's good: more tasks on the dashboard.
- Budget fields: `price_per_task: 0.10`, `max_total: 3.0 TESTUSD` — the app is *paying* for compute; surface the receipt ("this match run cost 0.40 TESTUSD across 3 machines") in the results view. Great fintech-track moment.

### Failure handling

- Job `failed` → show a friendly error + "retry"; keep any embeddings already stored.
- Poll timeout (>3 min) → same path.
- The app never retries individual tasks — that's JacGrid's job. The app only resubmits whole jobs.

---

## 4. What stays out (hackathon)

- Accounts/auth (a name field is enough), chat/contact exchange, mutual-match logic, mobile, moderation.
- Any direct knowledge of workers, sandboxes, or payments beyond displaying the receipt JacGrid returns.

---

## 5. Milestones

| # | Milestone | Proves |
|---|---|---|
| S-M1 | Profiles CRUD + seeded dataset (~100 believable profiles) + pool view | App skeleton |
| S-M2 | Full flow against `MockJacGrid`: submit → progress UI → matches rendered | Product works end-to-end |
| S-M3 | Match quality pass on seed data: top matches look right, why-matched reads well | Demo credibility |
| S-M4 | Swapped to `LiveJacGrid` against Phong's coordinator; receipt displayed | The real story |

## 6. Risks & mitigations

- **Coordinator late** → the mock means S-M1–S-M3 never block; the swap is one config change.
- **Model mismatch with the runner** → pin `all-MiniLM-L6-v2` in writing (done here); verify one embedding matches between app-local and network output early in integration.
- **Seed profiles look fake** → write them from real hackathon-attendee archetypes; 100 profiles ≈ 30 min with an LLM assist, curated by hand.
- **Progress UI has nothing to show (jobs finish fast)** → good problem; keep per-task states visible for at least a beat via polling snapshots, and lean on the dashboard for the network view.
