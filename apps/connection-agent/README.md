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

See [`docs/specs/FOUNDATION_AND_PARALLEL_WORK.md`](docs/specs/FOUNDATION_AND_PARALLEL_WORK.md) for parallel objective boundaries.

The released product interface is [`docs/specs/INTERNAL_CONTRACT_V1.md`](docs/specs/INTERNAL_CONTRACT_V1.md). Start parallel sessions from [`docs/objectives/README.md`](docs/objectives/README.md); each packet defines one goal, writable paths, ordered specs, checks, and completion evidence.

After the foundation is merged, [`docs/SESSION_LAUNCH.md`](docs/SESSION_LAUNCH.md) explains how to create isolated worktrees and provides the exact initial prompt for each Codex session.
