# JacGrid Demo Plan

The live demo tells one story: **a real application buys verified compute from a network of independent machines, and the machines get paid.**

Total target time: **4 minutes** plus Q&A.

---

## Setup (before going on stage)

- [ ] Mac 1: coordinator running, dashboard open in browser, matching app backend running
- [ ] Mac 2: worker + sandbox running, terminal visible
- [ ] Mac 3: worker + sandbox running, terminal visible
- [ ] All three registered and showing **online** on the dashboard
- [ ] Matching app seeded with ~100 profiles (pre-written, believable)
- [ ] Wallet balances visible (before-state screenshot as backup)
- [ ] A rehearsed way to kill the Mac 2 worker (`Ctrl-C` in its terminal)
- [ ] Backup: screen recording of a successful full run, in case of network issues

---

## Script

### Beat 1 — The network (30s)

Show the dashboard:

```text
Mac 1 — online — coordinator + worker
Mac 2 — online — compute worker
Mac 3 — online — compute + verification worker
```

Say: "Three independent machines. Any of them can leave at any time. None of them is trusted by default — they get paid only for verified work."

### Beat 2 — A real application submits a job (45s)

Switch to the matching app. Sebastian's flow:

1. Show the profile list (100 people).
2. Click **"Find my matches"**.
3. The app submits an **embedding job** to JacGrid — show the job appear on the dashboard:

```text
Job 001 — embedding — 100 items → 4 tasks
Task t-1 → Mac 1    Task t-2 → Mac 2
Task t-3 → Mac 3    Task t-4 → queued
```

Say: "The app doesn't manage machines, retries, or payments. It submits a job and gets results — JacGrid does everything else, and the whole control plane is a Jac graph driven by walkers."

### Beat 3 — Kill a worker live (45s)

While tasks run, `Ctrl-C` the Mac 2 worker.

```text
Mac 2 heartbeat expired
  → Attempt on t-2 marked failed
  → t-2 reassigned to Mac 3
  → execution continues
```

Say: "Mac 2 just died mid-task. No human intervened — the `detect_failure` and `reassign_task` walkers rescheduled the work. And Mac 2 will not be paid for that task."

### Beat 4 — Verification and payment (45s)

When tasks complete:

```text
t-1 verified (recomputed sample matched) → Mac 1 paid 0.10 TESTUSD
t-2 (reassigned) verified               → Mac 3 paid 0.10
t-3 verified                            → Mac 3 paid 0.10
t-4 verified                            → Mac 1 paid 0.10
Mac 2: 0 payments (failed mid-task)
```

Show wallet balances changing. Say: "Payment is settlement for verified delivery — not a subscription, not trust."

### Beat 5 — The application gets its answer (45s)

Back to the matching app: embeddings returned, similarity computed, matches displayed.

Say: "Sebastian's app just consumed distributed compute the way apps consume Stripe. That's the product: any application can plug into this network."

### Beat 6 — The execution graph (30s)

Show the audit view (`audit_job` walker output):

```text
Job 001
 ├── t-1: attempt(mac1) → sandbox → result → verified → paid
 ├── t-2: attempt(mac2) FAILED → attempt(mac3) → verified → paid
 ├── t-3: attempt(mac3) → verified → paid
 └── t-4: attempt(mac1) → verified → paid
Final output → delivered to matching-app
```

Say: "Every attempt, result, verification, and payment is a node in the Jac graph. The audit trail *is* the data structure."

---

## Q&A ammunition

- **"Why Jac?"** The distributed control plane is literally a graph: devices, jobs, tasks, attempts, payments. Walkers are the scheduler, the monitor, and the auditor. We didn't wrap Python in Jac — the system of record is the graph.
- **"Is the payment real?"** Testnet/simulated — same receipt flow as real settlement, no real money at a hackathon.
- **"What about malicious workers?"** Verification before payment (sample recompute, redundant compute). Sybil resistance and escrow are the roadmap, not the MVP.
- **"How is this different from Ray/Spark?"** Those assume one owner who trusts every machine. JacGrid assumes independent owners and untrusted results — that's why verification and payment are in the core loop.

---

## Track positioning

- **Fintech:** machine-to-machine market — compute purchased per verified task.
- **Best Use of Jac:** the entire control plane is Jac graph + walkers.
- **Defense (secondary):** resilient execution across unreliable, independently-owned devices — demonstrated live by killing a worker.
