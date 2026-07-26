# JacGrid Documentation

JacGrid is a Jac-native distributed compute network. Applications submit jobs, JacGrid splits them into tasks, runs them across independent devices inside sandboxes, verifies the results, and pays successful workers with testnet cryptocurrency.

The hackathon build runs across three Macs and powers one real application: **Sebastian's matching app**, which supplies a versioned embedding workload, submits embedding jobs to the network, and uses the returned vectors to match people.

## How the pieces fit

```text
┌─────────────────────────────────────────────────────┐
│  Matching Application + Workload (Sebastian)        │
│  profiles → our embedding code → JacGrid → matches  │
└───────────────────────┬─────────────────────────────┘
                        │  Job Submission API
┌───────────────────────▼─────────────────────────────┐
│  Distributed Compute Layer (Phong)                  │
│  coordinator · scheduling · heartbeats · recovery   │
│  verification · payment · Jac graph of everything   │
└───────────────────────┬─────────────────────────────┘
                        │  Task Execution API
┌───────────────────────▼─────────────────────────────┐
│  Sandbox Layer (Luke/Santhos)                               │
│  restricted execution · allowlisted runtimes        │
│  resource limits · execution metadata               │
└─────────────────────────────────────────────────────┘
```

## Documents

| Document | Purpose |
|---|---|
| [architecture.md](architecture.md) | System architecture, Jac graph model, walkers, and the API contracts between the three workstreams |
| [workload-ownership-decision.md](workload-ownership-decision.md) | Why the application owns its computation while Phong distributes it and Luke/Santhos run it safely |
| [Connection Agent foundation](../apps/connection-agent/docs/specs/FOUNDATION_AND_PARALLEL_WORK.md) | Proposed foundation and directory ownership for our parallel implementation sessions |
| [specs/CONNECTION_AGENT_JACGRID_BOUNDARIES.md](specs/CONNECTION_AGENT_JACGRID_BOUNDARIES.md) | Accepted contracts only where Connection Agent exchanges data or code with JacGrid |
| [Connection Agent walking skeleton](../apps/connection-agent/docs/specs/WALKING_SKELETON.md) | Implemented fake-adapter scenario proving the complete two-person product loop |
| [Connection Agent internal contract](../apps/connection-agent/docs/specs/INTERNAL_CONTRACT_V1.md) | Released transport-independent product types, lifecycle states, operations, errors, and adapter rules |
| [Connection Agent objective packets](../apps/connection-agent/docs/objectives/README.md) | Five-session parallel implementation map with strict writable paths |
| [demo-plan.md](demo-plan.md) | The three-Mac live demo script, including failure recovery |
| [phong-distributed/spec.md](phong-distributed/spec.md) | Distributed compute layer: coordinator, workers, scheduling, verification, payment |
| [phong-distributed/tasks.md](phong-distributed/tasks.md) | Phong's task breakdown |
| [luke-sandbox/spec.md](luke-sandbox/spec.md) | Sandbox layer: restricted task execution on worker Macs |
| [luke-sandbox/tasks.md](luke-sandbox/tasks.md) | Luke/Santhos task breakdown |
| [sebastian-application/spec.md](sebastian-application/spec.md) | Matching application: profiles, embedding jobs, match results |
| [sebastian-application/tasks.md](sebastian-application/tasks.md) | Sebastian's task breakdown |

The original concept document lives at the repo root: [`JacGrid_Concept.md`](../JacGrid_Concept.md).

## Ownership

| Person | Workstream | Owns |
|---|---|---|
| **Phong** | Distributed compute | Coordinator, worker runtime, Jac graph, scheduling, heartbeats, failure recovery, verification orchestration, payment |
| **Luke/Santhos** | Sandbox | Generic restricted execution environment, workload allowlist, resource limits, execution metadata |
| **Sebastian** | Application + workload | Matching product plus the versioned embedding runner, its input/output contract, fixtures, and domain verification rules |

## Working agreements

1. **Interfaces first.** The three contracts in `architecture.md` (Job Submission API, Task Execution API, Application Workload Contract) are frozen early. Each person builds against the contracts, not against another person's implementation.
2. **Mock before integrate.** Sebastian develops against a mock coordinator; the Luke/Santhos sandbox is tested with a fake task before real ones; Phong stubs the sandbox with a plain subprocess until the Luke/Santhos runner is ready.
3. **One integration branch.** Everyone merges to `main` frequently; integration checkpoints are listed in each tasks file.
4. **The demo is the spec.** If a feature is not needed for the demo flow in `demo-plan.md`, it is out of scope for the hackathon.
