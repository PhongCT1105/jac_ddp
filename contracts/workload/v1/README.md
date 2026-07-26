# Application Workload Contract (Contract C)

**Supplied by:** Application (Sebastian). **Executed by:** Sandbox (Luke/Santhos). **Verified by:** Coordinator (Phong).

## Overview

Sebastian supplies a versioned, immutable workload package containing the computation logic, exact dependencies, and correctness criteria. This package is installed once on worker machines and re-invoked for each task without modification.

The workload is **application-specific** (not platform-generic); the embedding algorithm, model selection, and preprocessing are Sebastian's responsibility. Phong schedules and verifies executions; Luke/Santhos install and safely invoke the package under resource limits.

## Workload Package Contents

### `workload.json` Manifest

A JSON manifest at the workload root describes everything needed to install, invoke, and verify the workload.

| Field | Type | Meaning |
|---|---|---|
| `name` | string | Workload identifier (e.g., `connection-embedding`) |
| `version` | string | Semantic version (e.g., `1.0.0`); used in task execution records |
| `entrypoint` | string | Path to the executable Jac file (e.g., `src/embed.jac`) |
| `model` | object | Model specification |
| `model.name` | string | Model identifier (e.g., HuggingFace model name) |
| `model.artifact_hash` | string | SHA256 hash of the model artifact for integrity verification |
| `dependencies` | object | Locked dependency versions (package name → version string); must be exact (not ranges) |
| `input_schema` | object | JSON Schema defining expected input structure (from task envelope `payload`) |
| `output_schema` | object | JSON Schema defining expected output structure (for task envelope `output`) |
| `resource_requirements` | object | Typical resource needs |
| `resource_requirements.cpu_seconds` | integer | Expected CPU seconds (informs sandbox limits) |
| `resource_requirements.memory_mb` | integer | Expected memory (informs sandbox limits) |
| `resource_requirements.wall_seconds` | integer | Expected wall-clock seconds (informs sandbox limits) |
| `verification` | object | Correctness criteria |
| `verification.tolerance` | number | Numeric tolerance for comparing outputs (e.g., 0.001 for embedding cosine distance) |
| `fixtures` | object | Deterministic test cases for local development and verification |

### Additional Files

The workload package must also include:

- **`src/` or equivalent directory:** Source code (Jac, Python, etc.) referenced by `entrypoint`
- **`tests/` directory:** Local unit and integration tests verifiable without the coordinator
- **`README.md`:** Usage, setup, and debugging instructions
- **`LICENSE`:** License for the workload code

## Ownership Boundaries

| Responsibility | Owner |
|---|---|
| Workload code, model selection, schemas, input preprocessing | **Sebastian's application team** |
| Installation, allowlisting, invocation under resource limits, safety | **Luke/Santhos (sandbox)** |
| Scheduling, task distribution, result aggregation, verification orchestration, payment | **Phong (coordinator)** |

## Verification

During job completion, the coordinator uses the same workload (same model, same code, same version) to verify a sample of results:

1. Submit the same input to a re-verification task
2. Invoke the workload under the same resource limits
3. Compare outputs within `verification.tolerance`
4. If verification passes: release payment to the worker; if it fails: mark the attempt as failed and reassign

## Immutability

Once `version` X is registered and used in a job, it **cannot be modified**. The coordinator pins job execution to a specific workload version so results are always reproducible. New iterations must use incremented version numbers (e.g., `1.0.1`, `1.1.0`).

## Deployment

1. **Development & Testing:** Sebastian tests locally using the fixture inputs.
2. **Registration:** Submit the workload manifest to the coordinator for allowlisting.
3. **Installation:** Luke/Santhos (sandbox) receives the workload, verifies the manifest, downloads dependencies, and caches it.
4. **Execution:** Workers invoke via the Task Execution API (Contract B); the sandbox loads the workload and runs the entrypoint.
