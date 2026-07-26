# Task Execution API (Contract B)

**Between:** Worker runtime (Phong) → Sandbox (Luke/Santhos). A local interface on each worker Mac: the worker hands the sandbox a task envelope, the sandbox returns a result envelope.

## Task Envelope (Worker → Sandbox)

Input passed by the worker runtime to the sandbox for execution.

### Fields (`task-envelope.json`)

| Field | Type | Meaning |
|---|---|---|
| `task_id` | string | Unique identifier for this task; used in result envelope and payment records |
| `job_type` | string | Type of computation; sandbox only runs allowlisted types (e.g., `embedding`, `noop`) |
| `payload` | object | Job-specific input; structure depends on `job_type` |
| `payload.model` | string | Model identifier (for embedding jobs) |
| `payload.items` | array | Items to process (e.g., profiles with `id` and `text` for embeddings) |
| `limits` | object | Resource constraints enforced by the sandbox |
| `limits.cpu_seconds` | integer | Maximum CPU time allowed (seconds) |
| `limits.memory_mb` | integer | Maximum memory allocation (megabytes) |
| `limits.wall_seconds` | integer | Maximum wall-clock time allowed (seconds) |
| `limits.network` | string | Network access; for hackathon: `none` (no external network) |

## Result Envelope (Sandbox → Worker)

Output returned by the sandbox after execution. **The `execution` block is mandatory.**

### Fields (`result-envelope.json`)

| Field | Type | Meaning |
|---|---|---|
| `task_id` | string | Echo of the input task ID |
| `status` | string | Execution outcome: `ok` (success), `error` (runtime error), `timeout` (wall-time exceeded), `limit_exceeded` (CPU/memory limit hit) |
| `output` | object | Job-type-specific result (only populated if `status == "ok"`) |
| `output.results` | array | For embedding jobs: array of objects with `id` (string) and `embedding` (array of floats) |
| `execution` | object | **Mandatory.** Execution metadata fed to the Jac graph and audit timeline |
| `execution.runtime` | string | Identifier of the workload runner (e.g., `embedding-runner:v1`) |
| `execution.started_at` | string | ISO 8601 timestamp when execution began |
| `execution.finished_at` | string | ISO 8601 timestamp when execution completed |
| `execution.peak_memory_mb` | integer | Peak memory used (megabytes) |
| `execution.cpu_seconds` | number | Total CPU time consumed (seconds) |
| `execution.exit_code` | integer | Process exit code (0 = success) |
| `error` | string or null | Human-readable error message (non-null only if `status != "ok"`) |

## Sandbox Behavior

- The sandbox **never talks to the coordinator**; only the worker runtime communicates with the coordinator.
- The sandbox **only runs allowlisted `job_type`s**. Unknown types return `status: "error"` immediately.
- The sandbox **enforces all resource limits** (`cpu_seconds`, `memory_mb`, `wall_seconds`) and returns `limit_exceeded` if a constraint is violated.
- The sandbox **must populate the `execution` block completely**, even on failure. This is critical for the Jac graph audit trail and worker reputation tracking.

## Failure Status Values

| Status | Cause | Next Action |
|---|---|---|
| `ok` | Execution completed successfully | Coordinator verifies output and pays worker |
| `error` | Unhandled runtime error (e.g., missing model, invalid JSON input) | Coordinator marks task failed, reassigns to another worker |
| `timeout` | Execution exceeded `wall_seconds` limit | Coordinator marks task failed, reassigns to another worker |
| `limit_exceeded` | CPU (`cpu_seconds`) or memory (`memory_mb`) limit was hit | Coordinator marks task failed, reassigns to another worker, may increase limits for retry |
