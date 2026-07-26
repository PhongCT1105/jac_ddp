# Decision Note: Application Workload Ownership

**Status:** Agreed architecture correction

**Applies to:** Sebastian application, Phong distributed layer, Luke/Santhos sandbox

## Summary

This is a small ownership clarification, not a redesign of JacGrid:

> Sebastian defines what the computation does; Phong decides where and when it runs; Luke/Santhos ensure it runs safely.

The first task breakdown accidentally assigned the embedding runner to both Phong and Luke/Santhos. The corrected plan gives the application-specific embedding code one owner: Sebastian's application team.

## Before and after

Earlier wording implied:

```text
Phong or Luke/Santhos write the embedding algorithm
        ↓
Sebastian's app submits jobs and consumes the result
```

The corrected boundary is:

```text
Sebastian supplies connection-embedding:1.0.0
        ↓
Phong distributes, retries, verifies, aggregates, and pays
        ↓
Luke/Santhos install, allowlist, and safely invoke the package
        ↓
Sebastian's app uses the verified vectors for matching
```

## Why

- It prevents Phong, Luke/Santhos, and Sebastian from building different embedding implementations.
- It lets every workstream proceed in parallel against stable interfaces.
- It keeps JacGrid general, like an AWS-style compute platform that runs application-supplied workloads.
- It gives model selection, preprocessing, schemas, and matching-quality defects one clear owner.

## Responsibilities that do not change

Phong still owns the coordinator, Jac graph, scheduling, workers, heartbeats, retries, verification orchestration, result aggregation, payment, reputation, and audit history.

Luke/Santhos still own the sandbox, workload allowlist, process invocation, CPU/memory/time limits, filesystem and network restrictions, execution metadata, error handling, cleanup, and worker-machine installation.

Only the application-specific algorithm moves to Sebastian's team. Phong and Luke/Santhos integrate and execute that package; they do not implement a second embedding algorithm.

## Sebastian's deliverable

Sebastian supplies a versioned workload containing:

- Entrypoint
- Exact model revision or artifact hash
- Locked dependencies
- Input and output schemas
- Resource requirements
- Numeric verification tolerance
- Deterministic fixtures

It must run locally without the coordinator and produce contract-compatible output inside the Luke/Santhos sandbox.

## Matching remains in the application

The distributed workload generates embeddings. It does not decide who should meet.

```text
JacGrid returns verified embeddings
        ↓
The connection app stores the vectors
        ↓
Our Jac logic retrieves and ranks candidates
        ↓
Our Jac logic assesses pairs and creates cards
```

Candidate ranking, pair reasoning, consent, matches, and private chat remain application responsibilities.

## Instruction for coding agents

Use the corrected ownership above when implementing tasks. Do not change the existing Job Submission API or Task Execution API without team agreement. Use the platform-owned `noop` fixture until Sebastian's immutable workload package is ready.
