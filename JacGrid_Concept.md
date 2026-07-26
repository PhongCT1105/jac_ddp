# JacGrid

## A Jac-Native Distributed Compute and Payment Infrastructure

### Project summary

**JacGrid** is an open-source infrastructure layer for distributing AI and compute jobs across independent devices.

For the hackathon, we will connect three Macs into a small compute network. A user can submit a job through a web application, JacGrid divides the job into tasks, assigns those tasks to available machines, monitors execution, verifies the results, and pays successful workers with testnet cryptocurrency.

The immediate goal is to build the **distributed infrastructure first**. Applications such as distributed model training, AI agents, human matching, research, inference, and data processing can later run on top of the same network.

### One-line pitch

> JacGrid turns independent devices into a distributed compute network where applications can submit jobs and automatically pay machines for verified work.

---

# 1. The Core Idea

Most distributed-computing systems assume that one organization owns and trusts every machine.

JacGrid is designed around a different model:

- Devices may belong to different people.
- Each device chooses whether to join the network.
- Workers advertise their capabilities and availability.
- Applications submit jobs through one common interface.
- Jobs are divided across available devices.
- Failed work is reassigned.
- Results are verified before payment.
- Successful workers receive testnet cryptocurrency.
- Every job, attempt, result, and payment is recorded.

For the hackathon, all three devices belong to our team. Opening the network to outside device owners is a later phase.

---

# 2. What We Are Building First

The first version focuses only on the infrastructure required to operate a small distributed compute network.

## Core components

### Worker runtime

Each participating Mac runs a JacGrid worker.

The worker:

- Registers itself with the network.
- Reports its hardware and available resources.
- Receives assigned tasks.
- Runs tasks inside a restricted environment.
- Reports progress and heartbeats.
- Returns results and execution metadata.
- Receives payment after successful verification.

### Coordinator

The coordinator manages the network.

It:

- Accepts submitted jobs.
- Splits jobs into smaller tasks.
- Selects suitable workers.
- Tracks worker availability.
- Detects failed tasks.
- Reassigns unfinished work.
- Combines completed results.
- Starts verification and payment.

### Job submission layer

Users or applications submit jobs through a simple website or API.

A job includes:

- The workload
- Required resources
- Number of tasks
- Maximum budget
- Verification rule
- Payment per successful task

### Sandbox layer

Submitted workloads should not run directly with unrestricted access to the worker’s computer.

Each task runs inside a controlled environment such as:

- A container
- A restricted process
- An allowlisted runtime image
- A lightweight virtual machine or sandbox

The first version can use a limited set of trusted task types. Running arbitrary public code can come later.

### Verification and payment layer

Workers are paid only after their output passes verification.

The network records:

- Who performed the task
- Which code or workload was used
- When the task started and finished
- What result was returned
- How the result was verified
- Whether payment was released

---

# 3. Three-Mac Hackathon Demo

The first network consists of three Macs.

| Machine | Role |
|---|---|
| Mac 1 | Jac coordinator, website, and optional worker |
| Mac 2 | Compute worker |
| Mac 3 | Compute worker and optional verifier |

The machines connect over the same local network.

## Demo flow

```text
User submits a compute job
          ↓
Jac creates the job and divides it into tasks
          ↓
Tasks are assigned across three Macs
          ↓
Each worker executes its task in a sandbox
          ↓
Workers return results
          ↓
Jac verifies and combines the results
          ↓
Successful workers receive testnet payment
          ↓
The user receives the final output
```

---

# 4. Main Demonstration

The live demo should prove that JacGrid is more than a normal API.

### Step 1: Register three devices

The dashboard shows:

```text
Mac 1 — online — coordinator and worker
Mac 2 — online — compute worker
Mac 3 — online — compute and verification worker
```

### Step 2: Submit a job

The user submits a distributed workload through the website.

The first workload could be:

- Small-model training
- Parallel inference
- Dataset processing
- Hyperparameter evaluation
- Embedding generation
- Batch document analysis

Distributed training can be the primary technical workload, but JacGrid itself remains general infrastructure.

### Step 3: Distribute the work

Jac divides the workload into several tasks and sends them to the available machines.

The dashboard shows:

```text
Job 001

Task A → Mac 1
Task B → Mac 2
Task C → Mac 3
```

### Step 4: Demonstrate failure recovery

One worker process is intentionally stopped.

```text
Mac 2 heartbeat expired
        ↓
Task B marked incomplete
        ↓
Task B reassigned to Mac 3
        ↓
Execution continues
```

### Step 5: Verify results

Returned outputs are checked using a predefined verification rule.

Examples include:

- Expected output hash
- Test-set accuracy
- Recomputed sample
- Metric range
- Independent verifier
- Matching output from multiple workers

### Step 6: Pay successful workers

Tasks that pass verification receive testnet payment.

```text
Task A verified → worker paid
Task B failed   → no payment
Task C verified → worker paid
Reassigned B verified → replacement worker paid
```

### Step 7: Show the execution graph

The final dashboard shows the entire lifecycle:

```text
Job
 ├── Task
 │    ├── Attempt
 │    ├── Worker
 │    ├── Sandbox
 │    ├── Result
 │    ├── Verification
 │    └── Payment
 └── Final output
```

---

# 5. Platform Rules

1. Workers are paid only for accepted results.
2. Every task must define a verification method.
3. Failed or disconnected tasks are reassigned.
4. Invalid or incomplete results receive no payment.
5. Every execution attempt is recorded.
6. Submitted workloads run inside a restricted environment.
7. Workers declare their capabilities before accepting tasks.
8. Device owners control when their device participates.
9. Payment terms cannot change after a worker accepts a task.
10. The hackathon demo uses testnet or simulated cryptocurrency only.
11. The initial network accepts only trusted or allowlisted workloads.
12. Public arbitrary-code execution is a later security milestone.

---

# 6. How Jac Powers the Infrastructure

Jac should implement the distributed system itself rather than only wrapping Python functions.

## Main graph objects

```text
Device
Worker
Job
Task
Attempt
Sandbox
Checkpoint
Result
Verification
Wallet
Payment
Reputation
Application
```

## Important relationships

```text
Application ── submits ──> Job
Job ── contains ──> Task
Task ── assigned to ──> Worker
Worker ── hosted on ──> Device
Task ── runs inside ──> Sandbox
Attempt ── produces ──> Result
Result ── checked by ──> Verification
Task ── settled by ──> Payment
Worker ── has ──> Reputation
```

## Main walkers

- `RegisterWorkerWalker`
- `CreateJobWalker`
- `SplitJobWalker`
- `SelectWorkerWalker`
- `AssignTaskWalker`
- `MonitorHeartbeatWalker`
- `DetectFailureWalker`
- `ReassignTaskWalker`
- `VerifyResultWalker`
- `ReleasePaymentWalker`
- `UpdateReputationWalker`
- `AuditJobWalker`

Jac manages the control plane, while Python, MLX, or another runtime performs the numerical computation.

---

# 7. Payment Model

JacGrid connects compute execution directly to financial settlement.

Each task has:

- A fixed or proposed price
- A worker
- A returned result
- A verification outcome
- A payment receipt

For the initial version:

- Each Mac has a test wallet.
- Payments use a testnet stablecoin or simulated crypto receipt.
- Payment occurs only after verification.
- Failed work receives no payment.
- Every payment is connected to the corresponding task in the Jac graph.

The project does not need its own token.

The financial value comes from creating a market where software and AI agents can automatically purchase verified computation.

---

# 8. Initial Workload

The infrastructure should support one strong workload for the demo.

## Recommended workload: distributed model training

The three Macs jointly process parts of a small training job.

JacGrid handles:

- Worker discovery
- Dataset or job partitioning
- Task assignment
- Heartbeats
- Failure recovery
- Checkpoint tracking
- Result aggregation
- Verification
- Payment

The training library handles the actual model computation.

This proves that JacGrid can support a technically demanding workload without limiting the platform to training alone.

---

# 9. Future Public Network

After the three-machine prototype works, JacGrid could allow outside users to contribute their own devices.

A future device owner could:

1. Visit the JacGrid website.
2. Install or launch a worker.
3. Select approved workload types.
4. Set CPU, memory, storage, and time limits.
5. Set a price or accept market pricing.
6. Make the device available.
7. Complete verified jobs.
8. Receive payment.

Future network requirements include:

- Stronger VM or container isolation
- Worker identity
- Secure code distribution
- Resource enforcement
- Fraud and Sybil resistance
- Escrow
- Dispute resolution
- Public reputation
- Malicious-result detection

These are future infrastructure milestones rather than hackathon requirements.

---

# 10. Applications Built Later

JacGrid is the platform. Applications are separate products built on top of it.

Potential applications include:

- Distributed AI training
- Paid model inference
- AI research agents
- Batch document processing
- Rendering and media generation
- Scientific simulation
- Federated learning
- Data analysis
- Hyperparameter optimization
- AI Connection Agent

## AI Connection Agent as a later application

The AI Connection Agent could submit profile-matching jobs to JacGrid.

```text
Connection Agent submits candidate evaluation job
                     ↓
JacGrid divides candidates across workers
                     ↓
Workers evaluate possible connections
                     ↓
JacGrid verifies and combines assessments
                     ↓
Connection Agent shows the selected person
```

The connection application would demonstrate how a real product can consume JacGrid, but it is not part of the infrastructure MVP.

The same applies to other future products: they submit jobs through JacGrid without needing to manage distributed workers, failure recovery, verification, or payment themselves.

---

# 11. Project Scope

## Hackathon MVP

1. Three registered Macs
2. One coordinator
3. Worker heartbeat system
4. Job submission interface
5. Task splitting and assignment
6. Restricted task execution
7. Worker failure and reassignment
8. Result verification
9. Testnet or simulated payment
10. Execution graph and audit timeline
11. One distributed AI workload

## Later

- Public device hosting
- Arbitrary workloads
- Full VM isolation
- Worker bidding
- Escrow contracts
- Dynamic pricing
- External application marketplace
- AI Connection Agent
- Paid APIs and agent tools
- Large distributed-training jobs

---

# 12. Difference from FlashML

FlashML focuses on running distributed machine-learning workloads across a managed cluster.

JacGrid focuses on creating an open economic infrastructure for compute:

- Machines can belong to different owners.
- Workers advertise resources and availability.
- Applications submit independent jobs.
- Tasks run in controlled sandboxes.
- Results are verified.
- Workers are paid per accepted task.
- Reputation influences future assignments.
- Multiple applications can use the same network.

Distributed training is the first workload, not the entire product.

---

# 13. Track Positioning

## Fintech / Open

JacGrid creates a machine-to-machine market for compute.

Applications purchase execution from independent devices, while payment depends on verified delivery.

## Best Use of Jac

Jac represents and operates the infrastructure:

- Devices
- Workers
- Jobs
- Tasks
- Attempts
- Results
- Verification
- Reputation
- Payments

Walkers control scheduling, monitoring, recovery, verification, settlement, and auditing.

## AI for Defense

JacGrid can later support distributed computation across unreliable or independently controlled edge devices.

For the hackathon, the defense angle can focus on resilient execution and trusted result verification, but it should remain secondary to the infrastructure and fintech story.

---

# Final pitch

> JacGrid is a Jac-native infrastructure layer for distributed compute. Applications submit AI jobs, JacGrid divides the work across independent devices, recovers failed tasks, verifies returned results, and automatically pays successful machines. Our hackathon prototype runs across three Macs, while the long-term vision allows anyone to contribute a device and earn from unused compute.
