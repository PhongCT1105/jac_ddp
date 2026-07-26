# Proposal: JacGrid Repository Folder Organization

**Status:** Proposal for team discussion

## Purpose

Keep the JacGrid platform, sandbox, reference application, and application-supplied workloads in one repository without combining them into one codebase.

Each independently runnable component has its own folder, configuration, dependencies, tests, and README. Shared contracts and integration fixtures have clearly named locations at the repository root.

## Proposed structure

```text
jac_ddp/
├── apps/
│   └── connection-agent/
│       ├── jac.toml
│       ├── src/
│       ├── web/
│       ├── supabase/
│       ├── tests/
│       ├── docs/
│       └── README.md
│
├── workloads/
│   └── connection-embedding/
│       ├── jac.toml
│       ├── workload.json
│       ├── src/
│       ├── tests/
│       └── README.md
│
├── platform/
│   ├── coordinator/
│   │   ├── jac.toml
│   │   ├── src/
│   │   ├── tests/
│   │   └── README.md
│   ├── worker/
│   │   ├── src/
│   │   ├── tests/
│   │   └── README.md
│   └── dashboard/
│       ├── src/
│       ├── tests/
│       └── README.md
│
├── sandbox/
│   ├── runner/
│   ├── profiles/
│   ├── fixtures/
│   ├── tests/
│   └── README.md
│
├── contracts/
│   ├── job-api/
│   │   └── v1/
│   ├── task-execution/
│   │   └── v1/
│   └── workload/
│       └── v1/
│
├── tests/
│   └── integration/
│
├── scripts/
│   ├── setup-demo.sh
│   ├── run-demo.sh
│   └── check-all.sh
│
├── docs/
├── LICENSE
└── README.md
```

## Folder purposes

### `apps/connection-agent/`

The complete connection product:

- Profile and conversation experience
- Supabase schema, policies, and adapters
- Candidate retrieval and ranking
- Jac pair assessment and card generation
- Consent, matches, and private chat
- Application UI and application-level tests
- Product-specific documentation

The application calls JacGrid through the shared Job API. It does not contain coordinator, worker, or sandbox implementations.

### `workloads/connection-embedding/`

The versioned computation supplied by the connection application and executed on JacGrid workers:

- Workload manifest
- Jac entrypoint
- Exact model and dependency declarations
- Input and output schemas
- Resource requirements
- Verification tolerance
- Deterministic fixtures and tests

This is separate from `apps/connection-agent/` so worker machines can install the workload without installing the complete web application or Supabase integration.

### `platform/coordinator/`

The JacGrid control plane:

- Job API
- Jac graph model and walkers
- Task splitting and scheduling
- Worker health and failure recovery
- Verification orchestration
- Result aggregation
- Payment, reputation, and audit data

### `platform/worker/`

The runtime installed on participating compute machines:

- Registration and capabilities
- Heartbeats
- Task retrieval
- Sandbox invocation
- Result-envelope return

### `platform/dashboard/`

The network and job-lifecycle interface:

- Devices and worker status
- Jobs, tasks, and attempts
- Verification and payment status
- Audit visualization

### `sandbox/`

The Luke/Santhos restricted-execution component:

- Approved workload registry
- Generic workload invocation
- Temporary work directories
- CPU, memory, and wall-time limits
- Filesystem and network restrictions
- Execution metadata and cleanup
- Failure and isolation fixtures

### `contracts/`

Versioned interface definitions shared by otherwise independent components:

- `job-api/v1/`: application to coordinator
- `task-execution/v1/`: worker to sandbox
- `workload/v1/`: application-supplied workload to sandbox

This folder can contain JSON schemas, example envelopes, and contract fixtures. It should not contain application or platform implementation logic.

### `tests/integration/`

End-to-end fixtures and checks that cross component boundaries, such as:

- Application job submission to coordinator
- Worker task retrieval
- Sandbox execution of the embedding workload
- Worker failure and reassignment
- Verified result aggregation

### `scripts/`

Repository-level setup, checking, and demo commands. Component-specific scripts stay inside their component folders.

### `docs/`

Shared JacGrid documentation:

- Platform architecture
- API and workload contracts
- Demo plan
- Cross-component decisions
- Component specifications

Product-only documentation belongs under `apps/connection-agent/docs/`.

## Placement of existing documentation

The current shared JacGrid documents remain under the root `docs/` folder.

The complete Connection Agent product documents would live under:

```text
apps/connection-agent/docs/
├── PRODUCT_BOOK.md
├── TECHNICAL_DIRECTION.md
├── BUILD_PLAN.md
├── HACKATHON_DEMO.md
└── OPEN_QUESTIONS.md
```

The root-level JacGrid concept, license, hacker guide, and repository README remain at the repository root.

## Component relationship

```text
apps/connection-agent/
        │ submits jobs through contracts/job-api/v1
        ↓
platform/coordinator/
        │ assigns tasks through platform/worker
        ↓
sandbox/
        │ safely invokes
        ↓
workloads/connection-embedding/
        │ returns vectors
        ↓
apps/connection-agent/
```

## Scope of this proposal

This document proposes folder placement only. It does not move existing files, change API payloads, or change component responsibilities. Any physical reorganization can happen after the team agrees on the structure.
