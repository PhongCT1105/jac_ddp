# Stage 1 session index

Read [`../STAGE_1_PRODUCT.md`](../STAGE_1_PRODUCT.md) for the shared product cut
and [`../AGENT_WORKFLOW.md`](../AGENT_WORKFLOW.md) for the mandatory process.
Each implementation session receives exactly one handoff:

| Session | Worktree | Branch | Handoff |
|---|---|---|---|
| Core | `/Users/sebastian/dev/jac_ddp-orchestration-core` | `agent/orchestration-core` | [`handoffs/00_CORE.md`](handoffs/00_CORE.md) |
| Data and Integrations | `/Users/sebastian/dev/jac_ddp-data-integrations` | `agent/data-integrations` | [`handoffs/01_DATA_INTEGRATIONS.md`](handoffs/01_DATA_INTEGRATIONS.md) |
| Intelligence and Workload | `/Users/sebastian/dev/jac_ddp-intelligence-workload` | `agent/intelligence-workload` | [`handoffs/02_INTELLIGENCE_WORKLOAD.md`](handoffs/02_INTELLIGENCE_WORKLOAD.md) |
| Product Experience | `/Users/sebastian/dev/jac_ddp-product-experience` | `agent/product-experience` | [`handoffs/03_PRODUCT_EXPERIENCE.md`](handoffs/03_PRODUCT_EXPERIENCE.md) |
| Evaluation and Quality | `/Users/sebastian/dev/jac_ddp-evaluation-quality` | `agent/evaluation-quality` | [`handoffs/04_EVALUATION_QUALITY.md`](handoffs/04_EVALUATION_QUALITY.md) |

The primary checkout `/Users/sebastian/dev/jac_ddp` stays on `main` and is not
an implementation session. It is reserved for later consolidation.
