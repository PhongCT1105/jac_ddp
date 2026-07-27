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

The five lanes have been consolidated in the primary checkout on `main`.
Core, Data and Integrations, Intelligence and Workload, Product Experience,
and Evaluation and Quality all have implementation specifications and handoff
reports under `docs/specs/stage-1/`.

Run the complete integrated gate from the repository root:

```bash
./apps/connection-agent/scripts/check.sh --stage-1-integrated
```

Run the browser product locally with:

```bash
./apps/connection-agent/web/start.sh
```

Run the concise deterministic product evaluation with:

```bash
./apps/connection-agent/evals/check.sh
```
