# JacGrid Documentation

JacGrid is a Jac-native distributed compute network. Applications submit jobs, JacGrid splits them into tasks, runs them across independent devices inside sandboxes, verifies the results, and pays successful workers with testnet cryptocurrency.

The hackathon build runs across three Macs and powers one real application: **Sebastian's matching app**, which submits embedding jobs to the network and uses the returned vectors to match people.

## How the pieces fit

```text
┌─────────────────────────────────────────────────────┐
│  Matching Application (Sebastian)                   │
│  profiles → embedding job → JacGrid → matches       │
└───────────────────────┬─────────────────────────────┘
                        │  Job Submission API
┌───────────────────────▼─────────────────────────────┐
│  Distributed Compute Layer (Phong)                  │
│  coordinator · scheduling · heartbeats · recovery   │
│  verification · payment · Jac graph of everything   │
└───────────────────────┬─────────────────────────────┘
                        │  Task Execution API
┌───────────────────────▼─────────────────────────────┐
│  Sandbox Layer (Luke)                               │
│  restricted execution · allowlisted runtimes        │
│  resource limits · execution metadata               │
└─────────────────────────────────────────────────────┘
```

## Documents

| Document | Purpose |
|---|---|
| [architecture.md](architecture.md) | System architecture, Jac graph model, walkers, and the API contracts between the three workstreams |
| [demo-plan.md](demo-plan.md) | The three-Mac live demo script, including failure recovery |
| [phong-distributed/spec.md](phong-distributed/spec.md) | Distributed compute layer: coordinator, workers, scheduling, verification, payment |
| [phong-distributed/tasks.md](phong-distributed/tasks.md) | Phong's task breakdown |
| [luke-sandbox/spec.md](luke-sandbox/spec.md) | Sandbox layer: restricted task execution on worker Macs |
| [luke-sandbox/tasks.md](luke-sandbox/tasks.md) | Luke's task breakdown |
| [sebastian-application/spec.md](sebastian-application/spec.md) | Matching application: profiles, embedding jobs, match results |
| [sebastian-application/tasks.md](sebastian-application/tasks.md) | Sebastian's task breakdown |

The original concept document lives at the repo root: [`JacGrid_Concept.md`](../JacGrid_Concept.md).

## Ownership

| Person | Workstream | Owns |
|---|---|---|
| **Phong** | Distributed compute | Coordinator, worker runtime, Jac graph, scheduling, heartbeats, failure recovery, verification, payment |
| **Luke** | Sandbox | Restricted execution environment, allowlisted task runtimes, resource limits, execution metadata |
| **Sebastian** | Application | Matching product: profile intake, embedding job submission, similarity matching, results UI |

## Working agreements

1. **Interfaces first.** The two API contracts in `architecture.md` (Job Submission API, Task Execution API) are frozen early. Each person builds against the contract, not against each other's code.
2. **Mock before integrate.** Sebastian develops against a mock coordinator; Luke's sandbox is tested with a fake task before real ones; Phong stubs the sandbox with a plain subprocess until Luke's runner is ready.
3. **One integration branch.** Everyone merges to `main` frequently; integration checkpoints are listed in each tasks file.
4. **The demo is the spec.** If a feature is not needed for the demo flow in `demo-plan.md`, it is out of scope for the hackathon.
