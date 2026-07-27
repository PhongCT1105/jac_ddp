# JacHammer Coordinator Sandbox Deployment Design

Date: 2026-07-26  
Status: Ready for user review  
Selected approach: Host the JacGrid coordinator only

## 1. Goal

Deploy one public HTTPS JacGrid coordinator through a JacHammer sandbox so
workers on different networks can participate without requiring direct
Mac-to-Mac connectivity.

The first hosted proof must:

1. deploy from this GitHub repository through JacHammer;
2. expose the existing coordinator walker API at a public HTTPS URL;
3. accept two or more local workers over outbound HTTPS;
4. complete and pay a distributed `noop` job; and
5. remain compatible with the existing local demo and tests.

## 2. Scope

This phase deploys only the coordinator.

```text
Mac 1 worker ─┐
Mac 2 worker ─┼── outbound HTTPS ──> JacHammer coordinator sandbox
Mac N worker ─┘                            ^
                                             │
Local demo UI / submit script ─── HTTPS ─────┘
```

Local workers keep executing workloads in the existing JacGrid worker
sandbox. JacHammer's "sandbox deployment" is the temporary hosting environment
for the coordinator; it is not a replacement for the worker execution
sandbox.

## 3. Why This Architecture

The campus network has already shown peer-to-peer client isolation: Mac 1
listens on `0.0.0.0:8010`, its firewall is disabled, and Mac 2 still times out.
A public coordinator changes the network requirement from inbound LAN access
to ordinary outbound HTTPS, which is normally permitted on guest and campus
networks.

Hosting workers is deliberately excluded. Worker execution uses local device
resources and must remain under the device owner's control. Hosting the
frontend is also excluded from this phase because the existing scripts and UI
can call a public coordinator directly.

## 4. JacHammer Repository Adapter

The repository is a monorepo with four nested Jac projects and no Jac project
at its root. JacHammer imports the repository as a project, so the deployment
needs an unambiguous root application.

The implementation will add:

- a root `jac.toml` whose project is the hosted JacGrid coordinator;
- a root `main.sv.jac`, which is the only JacHammer server entrypoint; and
- a shared coordinator service module consumed by both the root hosted
  entrypoint and `platform/coordinator/main.sv.jac`.

The coordinator walker declarations and behavior must have one source of
truth. They must not be copied into a second deployment-only implementation.
The refactor will preserve the current nested coordinator project so all
existing local commands continue to work.

A root entry file is required, rather than configuring the root project to
start the nested entry file. Jac-scale derives its user/auth database location
from the entry file directory and its graph anchor database from the project
root. Those locations must coincide to avoid a split guest root and graph
store.

The shared module will retain these coordinator invariants:

- all HTTP walkers remain `walker:pub`;
- every graph mutation and read anchors on `root.shared`;
- `JACGRID_KEY` remains the application-level authorization secret;
- coordinator receive time remains the source of worker liveness;
- verification, audit, and simulated payment remain graph-backed; and
- the existing in-process coordinator self-test remains runnable.

Jac imports and includes used by the adapter will be chosen from current Jac
0.16.7 documentation and validated with the Jac compiler. No Jac syntax will
be assumed.

## 5. Dependency and Path Handling

The hosted project must preserve the full repository layout because
coordinator verification imports:

- `sandbox.runner.harness`; and
- `sandbox.runner.registry`.

The bridge currently derives the repository root from the nested coordinator
source path. The refactor will replace that depth-dependent assumption with a
path resolver that works from both the root JacHammer entrypoint and the
nested local project. It must locate a stable repository marker and fail with
a clear error if the sandbox package is absent.

Phase-one deployment will prove the `noop` workload. It will not depend on a
SentenceTransformer model download. Embedding verification will be tested
only after the hosted runtime has a pinned model dependency and cache strategy
that matches the workers.

## 6. Configuration and Security

JacHammer project settings will provide:

| Variable | Required | Purpose |
|---|---:|---|
| `JACGRID_KEY` | yes | Shared secret used by every JacGrid walker request |
| `JACGRID_HOSTED` | yes, value `1` | Enables hosted fail-closed configuration checks |
| `JACGRID_SUSPECT_AFTER` | no, default `15` | Seconds before a worker is suspect |
| `JACGRID_DEAD_AFTER` | no, default `30` | Seconds before a worker is dead |
| `JACGRID_MAX_ATTEMPTS` | no, default `3` | Maximum task attempts |
| `JACGRID_SWEEP_INTERVAL` | no, default `5` | External sweeper interval |

When `JACGRID_HOSTED=1`, the coordinator must refuse an empty key or the
development default `jacgrid-dev-key`. The key must never be committed, printed
by scripts, returned by an endpoint, or embedded in the frontend.

The existing public walker endpoints remain protected by their `secret` body
field. Jac-scale's generated admin account and JWT system are not part of the
JacGrid client authentication contract.

## 7. State and Sandbox Lifetime

The JacHammer sandbox is an ephemeral demo environment. According to the
current JacHammer deployment documentation, a sandbox deployment expires
automatically after seven days.

The demo must therefore assume:

- workers re-register after a deployment or restart;
- jobs may disappear after a redeploy or sandbox reset;
- the public URL may change when a new sandbox is created; and
- the local UI and workers receive the URL through
  `JACGRID_COORDINATOR`, not through committed code.

Durable production state, MongoDB, custom domains, and permanent deployment
are follow-up work. This phase must not claim production durability.

## 8. Tooling to Add

The implementation will add a small hosted-deployment toolkit:

1. A packaging test that proves the root Jac project is complete and does not
   duplicate coordinator walker declarations.
2. A local root-entry smoke test that starts the same application JacHammer
   will start and calls authenticated `network_status`.
3. `scripts/deploy/jachammer/smoke_coordinator.sh`, which validates a supplied
   HTTPS URL using `JACGRID_KEY`.
4. `scripts/deploy/jachammer/connect_worker.sh`, which validates the public URL
   and launches a named local worker using the existing worker runtime.
5. A concise deployment runbook with exact JacHammer UI steps, environment
   variables, two-Mac commands, job submission, status inspection, and
   troubleshooting.

Scripts will continue to bypass ambient HTTP proxies for coordinator calls,
because that behavior is already required by the local demo environment.

## 9. Verification Strategy

Implementation follows test-first gates:

1. Add failing tests for the root deployment contract.
2. Refactor to a shared coordinator service without changing API behavior.
3. Run `jac check` and the coordinator self-test for both the root and nested
   entrypoints.
4. Run existing worker mode, sandbox, coordinator, and end-to-end tests.
5. Start the root application locally on an unused port and prove:
   - correct key returns `network_status`;
   - wrong key returns `unauthorized`;
   - a worker can register and heartbeat;
   - a `noop` job completes.
6. After the user deploys through JacHammer, run the hosted smoke script.
7. Connect at least two physical workers and submit a 12-task `noop` job.

The first hosted distributed acceptance requires:

- at least two distinct live worker names in `network_status`;
- a completed job with all tasks verified;
- at least two distinct workers receiving successful task payments; and
- an audit tree with no abandoned running attempts.

## 10. User Actions Required Later

Codex can prepare and verify the repository, but it cannot use the user's
JacHammer account without the user opening the service. After implementation
is green, the user will:

1. sign in to JacHammer;
2. create a project and import the GitHub repository;
3. select the `main` branch;
4. add the required environment variables in project settings;
5. run Preview and inspect build logs;
6. open Deploy, select Sandbox, and click Deploy Sandbox;
7. copy the generated public HTTPS URL; and
8. run the provided smoke and worker commands on each Mac.

The runbook will give copy-paste commands with a placeholder for the generated
URL. The URL is not known until JacHammer creates the deployment.

## 11. Non-Goals

This phase does not:

- host or autoscale workers;
- host the demo frontend;
- provide durable production storage;
- configure a custom domain;
- deploy the embedding model cache;
- replace application authentication with Jac-scale user JWTs;
- enable real-money payment; or
- convert the sandbox deployment to permanent hosting.

## 12. Acceptance Criteria

The design is implemented when all of the following are true:

- the repository root is a valid Jac 0.16.7 API-service project;
- the root and nested coordinator entrypoints compile and pass self-tests;
- no duplicate coordinator walker implementation exists;
- existing local distributed tests remain green;
- the root entrypoint works locally with authenticated HTTP calls;
- the JacHammer Preview and Sandbox deployment both build successfully;
- the generated HTTPS URL passes the hosted smoke test;
- two physical Macs register workers through the hosted URL; and
- a distributed 12-task `noop` job completes, verifies, audits, and pays at
  least two workers.

Only after this gate is green should the team add hosted embedding verification
or deploy the frontend.
