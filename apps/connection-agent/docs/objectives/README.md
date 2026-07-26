# Parallel objective packets

These packets define the five concurrent Connection Agent sessions after the foundation commit is merged.

| Session | Objective | Packet |
|---|---|---|
| 1 | Orchestration and Core | [`00_ORCHESTRATION_AND_CORE.md`](00_ORCHESTRATION_AND_CORE.md) |
| 2 | Data and Integrations | [`01_DATA_AND_INTEGRATIONS.md`](01_DATA_AND_INTEGRATIONS.md) |
| 3 | Intelligence and Workload | [`02_INTELLIGENCE_AND_WORKLOAD.md`](02_INTELLIGENCE_AND_WORKLOAD.md) |
| 4 | Product Experience | [`03_PRODUCT_EXPERIENCE.md`](03_PRODUCT_EXPERIENCE.md) |
| 5 | Evaluation and Quality | [`04_EVALUATION_AND_QUALITY.md`](04_EVALUATION_AND_QUALITY.md) |

Every session uses its own branch and worktree from the same green foundation commit. Read [`INTERNAL_CONTRACT_V1.md`](../specs/INTERNAL_CONTRACT_V1.md), the relevant packet, and the product documents before implementation.

Phong's `platform/` and Luke/Santhos's `sandbox/` are read-only to every Connection Agent session.
