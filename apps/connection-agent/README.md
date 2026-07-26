# Connection Agent

This folder contains Sebastian's application code. It owns profiles, candidate retrieval and ranking, pair assessment, recipient-specific cards, consent, matches, threads, messages, product adapters, and the first-party experience.

JacGrid is a replaceable embedding-compute provider. Application code does not import `platform/` or `sandbox/` implementation modules.

## Prerequisites

- Jac `0.34.6` or a compatible `0.34.x` release
- A POSIX shell for the repository scripts

No external service or secret is required for the foundation demo.

## Commands

Run from the repository root:

```bash
./apps/connection-agent/scripts/setup.sh
./apps/connection-agent/scripts/check.sh
./apps/connection-agent/scripts/run-demo.sh --mock
```

The demo uses 30 synthetic profiles, invokes the exact local `connection-embedding` workload through `MockJacGrid`, ranks the complete candidate pool, records two independent opens, creates one match and thread, and appends one message.

## Ownership

Connection Agent implementation sessions may edit `apps/connection-agent/` and, only when assigned, `workloads/connection-embedding/`. Phong's `platform/` and Luke/Santhos's `sandbox/` are read-only.

See [`docs/STAGE_1_PRODUCT.md`](docs/STAGE_1_PRODUCT.md) for the current showable
product cut and [`docs/AGENT_WORKFLOW.md`](docs/AGENT_WORKFLOW.md) for the
mandatory spec-driven implementation/review process.

The released product interface is [`docs/specs/INTERNAL_CONTRACT_V1.md`](docs/specs/INTERNAL_CONTRACT_V1.md). Start parallel sessions from [`docs/SESSION_LAUNCH.md`](docs/SESSION_LAUNCH.md); each Stage 1 handoff defines one goal, writable paths, reviews, checks, push destination, and completion evidence.

The older [`docs/objectives/`](docs/objectives/) packets remain the Stage 2/3
backlog and are not the current launch instructions.
