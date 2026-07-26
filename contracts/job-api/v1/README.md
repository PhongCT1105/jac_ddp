# Job Submission API (Contract A)

**Between:** Application (Sebastian) → Coordinator (Phong). HTTP + JSON on the coordinator, e.g. `http://mac1.local:8000`.

## POST /api/jobs

Submit a job for distributed computation.

### Request Fields (`create-request.json`)

| Field | Type | Meaning |
|---|---|---|
| `app_id` | string | Identifier of the application submitting the job (e.g., "matching-app") |
| `job_type` | string | Type of computation to run; allowlist: `embedding`, `training_shard`, `noop` |
| `payload` | object | Job-specific input data; structure depends on `job_type` |
| `payload.model` | string | Model name or identifier (for embedding: HuggingFace model name) |
| `payload.items` | array | Items to process; each with `id` (string) and `text` (string) for embedding jobs |
| `partitioning` | object | How to split the job into tasks |
| `partitioning.strategy` | string | Split strategy; for hackathon: `chunk` |
| `partitioning.chunk_size` | integer | Number of items per task |
| `verification` | object | How to verify result correctness |
| `verification.method` | string | Verification approach; hackathon set: `recompute_sample`, `output_hash`, `metric_range`, `redundant_compute` |
| `verification.sample_rate` | number | For `recompute_sample`: fraction of items to re-verify (0.0–1.0) |
| `budget` | object | Cost constraints |
| `budget.max_total` | number | Maximum total cost for entire job |
| `budget.price_per_task` | number | Fixed cost per task (cannot change after workers accept) |
| `budget.currency` | string | Currency code (e.g., "TESTUSD" for testnet) |

### Response Fields (`create-response.json`)

| Field | Type | Meaning |
|---|---|---|
| `job_id` | string | Unique identifier for this job; used to poll status and fetch results |
| `status` | string | Initial job status; always `queued` on creation |
| `task_count` | integer | Number of tasks the job was split into |

## GET /api/jobs/{job_id}

Poll job status and task progress.

### Response Fields (`status-response.json`)

| Field | Type | Meaning |
|---|---|---|
| `job_id` | string | The job identifier |
| `status` | string | Job state: `queued` (waiting), `running` (tasks executing), `verifying` (checking results), `complete` (all verified), `failed` (unrecoverable error) |
| `tasks` | array | Array of task status objects |
| `tasks[].task_id` | string | Unique task identifier |
| `tasks[].status` | string | Task state: `queued`, `running`, `complete`, `failed` |
| `tasks[].worker` | string | Hostname of the worker executing (or completed) this task |
| `tasks[].paid` | boolean | Whether this task's worker has been paid |
| `progress` | number | Fraction of tasks completed (0.0–1.0) |

## GET /api/jobs/{job_id}/result

Retrieve combined results (available when `status == "complete"`).

### Response Fields (`result-response.json`)

| Field | Type | Meaning |
|---|---|---|
| `job_id` | string | The job identifier |
| `results` | array | Aggregated output from all tasks, structure depends on job_type |
| `results[].id` | string | Item identifier (from input payload) |
| `results[].embedding` | array of numbers | For embedding jobs: the computed vector |
| `receipt` | object | Payment and verification summary |
| `receipt.tasks` | integer | Total number of tasks in the job |
| `receipt.verified` | integer | Number of tasks that passed verification |
| `receipt.total_paid` | number | Total amount paid to workers (in `budget.currency`) |
| `receipt.payments` | array | Individual payment records |
| `receipt.payments[].task_id` | string | Task identifier |
| `receipt.payments[].worker` | string | Worker hostname |
| `receipt.payments[].amount` | number | Amount paid for this task |
| `receipt.payments[].tx` | string | Transaction reference or hash |

## Job Types (Hackathon Allowlist)

| `job_type` | Payload | Result per item |
|---|---|---|
| `embedding` | items with `id` + `text`, model name | vector of floats |
| `training_shard` | dataset shard reference + hyperparams | gradients / trained weights + metrics |
| `noop` | anything | echo (integration testing only) |
