# JacMarket

## Verifiable AI Compute Marketplace Built with Jac

**Status:** Initial concept document  
**Hackathon:** JacHacks SF 2026  
**Primary track:** Fintech / Open  
**Additional tracks:** Best JacHammer, Best Use of Jaclang, and optionally AI for Defense

---

## 1. Project Summary

**JacMarket** is an open marketplace where people or AI agents can submit compute jobs, discover available workers, verify completed work, and automatically pay successful workers with testnet stablecoins.

For the hackathon demo, the team’s four Macs act as independent compute providers. Each Mac advertises its capabilities and price. Jac manages the job market, worker reputation, task assignment, verification, recovery, and payment history.

### One-line pitch

> JacMarket lets AI jobs buy compute from independent machines and pay only for verified results.

---

## 2. The Problem

Today, distributed-compute systems usually assume that all workers belong to one trusted cluster.

An open compute market has harder problems:

- Workers may charge different prices.
- A worker may disconnect before finishing.
- A worker may return an incorrect result.
- The buyer needs proof that useful work was completed.
- Payments, job history, and worker reputation must be traceable.
- AI agents need a simple way to purchase services automatically.

JacMarket combines distributed execution and financial settlement into one graph-native system.

---

## 3. Main Idea

A requester submits a job with:

- A task or workload
- Required capabilities
- Maximum budget
- Verification rules
- Payment amount

Workers advertise:

- Hardware and software capabilities
- Current availability
- Price per task
- Reliability history
- Wallet address

Jac walkers match the job with workers, monitor execution, verify the result, and release payment only when the work is accepted.

### Basic flow

```text
Requester submits a job
        ↓
Workers offer price and capability
        ↓
Jac selects a worker
        ↓
Worker executes the task
        ↓
Jac verifies the result
        ↓
Accepted result → payment released
Failed result   → task reassigned
        ↓
Worker reputation updated
```

---

## 4. Demo Setup with Four Macs

Each Mac represents an independent compute provider.

| Machine | Demo role |
|---|---|
| Mac 1 | Jac coordinator, dashboard, and optional worker |
| Mac 2 | Training or data-processing worker |
| Mac 3 | Training or inference worker |
| Mac 4 | Verification worker or competing compute provider |

Possible tasks include:

- Training a small model on one data shard
- Running model inference
- Processing part of a dataset
- Evaluating a submitted model update
- Computing a result that another worker can independently verify

The demo should include one normal worker, one failed worker, and one incorrect or suspicious result.

---

## 5. Core Project Rules

These are product rules for JacMarket.

1. **Workers are paid only for accepted work.**
2. **Every job must define a verification method before execution.**
3. **Failed or disconnected tasks are reassigned.**
4. **Incorrect results receive no payment.**
5. **Every bid, assignment, result, verification, and payment is recorded.**
6. **Worker reputation changes based on completed, failed, and rejected jobs.**
7. **The demo uses testnet funds only.**
8. **The project uses an existing stablecoin rather than creating a speculative custom token.**
9. **Jac controls the market and execution state; Python or MLX may perform the numerical workload.**
10. **A requester cannot change the payment or verification conditions after a worker accepts the job.**

---

## 6. Payment Model

The planned payment layer is an x402-style machine-to-machine payment flow using a testnet stablecoin.

For the first version:

- Each worker has a test wallet.
- Every task has a fixed payment amount.
- Payment is released after verification.
- Failed or rejected tasks are not paid.
- All payment receipts are linked to the related job and result in the Jac graph.

### Example

```text
Task price: $0.02 testnet USDC
Worker completes task
Verification passes
Payment receipt created
Worker reputation increases
```

### Why not create a new token?

A custom token creates unnecessary questions about value, supply, and utility. A stablecoin keeps the project focused on automated payment for useful compute.

A custom reward token can remain a future extension.

---

## 7. How Jac Is Used

Jac should implement the core system rather than acting only as an API wrapper.

### Main graph objects

```text
Requester
Worker
Job
Task
Bid
Result
Verification
Payment
Wallet
Reputation
Incident
```

### Important relationships

```text
Requester → creates → Job
Worker → submits → Bid
Job → assigned_to → Worker
Worker → produces → Result
Result → checked_by → Verification
Job → settles_as → Payment
Worker → has → Reputation
```

### Main walkers

- **CreateJobWalker** — creates a new compute request
- **FindWorkersWalker** — finds workers with the required capability
- **SelectBidWalker** — compares price, reputation, and availability
- **AssignTaskWalker** — assigns the task
- **MonitorWorkerWalker** — checks progress and heartbeat
- **VerifyResultWalker** — validates the output
- **ReleasePaymentWalker** — approves payment for accepted work
- **ReassignTaskWalker** — moves failed work to another provider
- **UpdateReputationWalker** — updates worker history
- **AuditJobWalker** — reconstructs the complete job and payment timeline

### Division of responsibility

| Layer | Responsibility |
|---|---|
| Jac | Jobs, graph state, matching, policies, verification flow, reputation, audit, and payment records |
| Python / MLX | Model training, inference, or data processing |
| Payment integration | Testnet stablecoin authorization and settlement |
| Jac client | Live marketplace and execution dashboard |

---

## 8. Verification

Payment must be connected to proof of useful work.

The first version can support simple verification methods:

- Compare the returned output with a known expected result
- Re-run a small sample independently
- Check a result hash
- Validate model accuracy against a test set
- Compare a submitted update against basic statistical limits
- Ask a separate Mac to verify the result

For the demo, verification should be deterministic and easy to explain.

### Recommended demo verification

Split a dataset-processing or model-evaluation job into tasks. The verifier knows the expected checksum, metric range, or sample output. A deliberately corrupted result fails verification and receives no payment.

---

## 9. Failure and Dispute Rules

### Worker disconnects

1. The heartbeat expires.
2. The current attempt is marked failed.
3. No payment is released.
4. The task is offered to another worker.
5. The failed worker’s reliability score decreases.

### Worker submits an invalid result

1. Verification fails.
2. The result is stored as rejected.
3. No payment is released.
4. The task is reassigned or independently checked.
5. The worker’s reputation decreases.

### Verification is uncertain

1. Payment is paused.
2. A second verifier is assigned.
3. The result is accepted only when the verification policy is satisfied.

Full on-chain dispute resolution is outside the initial MVP.

---

## 10. Hackathon Demo Story

1. The requester submits a compute job with a budget.
2. Three Macs advertise different prices and capabilities.
3. Jac selects workers and shows the assignments in a live graph.
4. The workers begin processing tasks.
5. One Mac is disconnected.
6. Jac detects the failure and reassigns its task.
7. Another Mac submits an intentionally incorrect result.
8. The verifier rejects the result and blocks payment.
9. A replacement worker completes the task correctly.
10. Jac releases testnet payments to the successful workers.
11. The dashboard shows the complete path from job to result to payment.

### Main visual moment

```text
Worker failed → task reassigned
Invalid result → payment blocked
Verified result → payment released
```

---

## 11. Track Positioning

### Fintech / Open

The project creates financial infrastructure for machine-to-machine commerce. AI agents and applications can purchase compute services automatically and settle payment based on verified delivery.

### Best JacHammer / Best Use of Jaclang

Jac represents the marketplace itself:

- Workers
- Jobs
- Bids
- Results
- Reputation
- Verification
- Payments
- Failures

Walkers operate the full market and execution lifecycle.

### Optional AI for Defense

The same system can coordinate paid compute across disconnected or independently operated edge devices. A defense-oriented version could focus on trusted procurement of compute, resilient task reassignment, and verification of results from untrusted nodes.

The defense framing should remain secondary unless the demo clearly supports it.

---

## 12. Hackathon Requirements

The project must follow the official JacHacks rules:

- Team size is limited to four people.
- All coding must happen during the official hacking period.
- The project must be working software.
- At least 40% of the code must use Jac meaningfully.
- The submission must include a GitHub repository, demo video, and written project description.
- A partial submission is required by 5:50 PM.
- Final submission closes at 7:15 PM.
- The first-round demo is four minutes.
- The judging guidance favors working demos and clear problem-solution stories over slide decks and feature lists.

---

## 13. Minimum Viable Product

The MVP should contain only:

1. Worker registration
2. Job creation
3. Fixed-price task assignment
4. Execution across at least two Macs
5. Result verification
6. Failure-based reassignment
7. Testnet payment or a clearly simulated payment fallback
8. Worker reputation update
9. Live Jac graph or status dashboard
10. Job audit timeline

---

## 14. Stretch Features

Only add these after the MVP works:

- Worker bidding
- Escrow smart contract
- Dynamic pricing
- Model-update contribution scoring
- Multiple verification policies
- Privacy-preserving federated learning
- Paid Jac walkers or paid MCP tools
- NVIDIA-backed result evaluation
- Defense-oriented edge-compute scenario
- Public reusable `jac-x402` package

---

## 15. Current Project Boundary

JacMarket is **not**:

- A new cryptocurrency
- An NFT platform
- A replacement for PyTorch or MLX
- A full blockchain
- A general cloud provider
- A copy of FlashML

FlashML coordinates compute owned by one runtime. JacMarket coordinates economically independent providers and connects execution to verification, reputation, and payment.

---

## 16. Final Pitch

> Compute marketplaces should not pay machines simply because they claim a task is complete. JacMarket is a graph-native marketplace where AI jobs discover independent compute providers, recover failed work, verify useful results, and automatically pay only the workers that delivered.
