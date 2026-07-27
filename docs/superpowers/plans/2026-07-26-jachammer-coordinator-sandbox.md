# JacHammer Coordinator Sandbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the repository directly deployable as a coordinator-only JacHammer sandbox and provide copy-paste tooling to connect local Mac workers through its public HTTPS URL.

**Architecture:** A root Jac API-service project becomes the JacHammer entrypoint. Both the root entrypoint and the existing nested coordinator entrypoint include the same model and service modules, preserving one coordinator implementation while keeping local commands compatible. Shell tooling authenticates against the hosted walker API, then reuses the existing worker and job launchers.

**Tech Stack:** Jac 0.16.7, jac-scale 0.2.31, Bash, curl, jq, GitHub/JacHammer sandbox deployment.

## Global Constraints

- Deploy only the coordinator; workers and the demo frontend remain local.
- Root `main.sv.jac` must be the hosted entrypoint so Jac-scale auth and graph databases share the repository project root.
- Coordinator walker declarations and behavior must have one source of truth; do not copy walkers into a deployment-only implementation.
- All coordinator HTTP walkers remain `walker:pub` and every graph operation remains anchored on `root.shared`.
- `JACGRID_KEY` is never committed, printed, returned by an endpoint, or embedded in frontend code.
- `JACGRID_HOSTED=1` must reject an empty key and the development key `jacgrid-dev-key`.
- First hosted acceptance uses the `noop` workload; hosted embedding verification is out of scope.
- JacHammer sandbox state and URL are ephemeral; do not claim production durability.
- Use current Jac 0.16.7 documentation, run Jac MCP validation for changed Jac code, and run the local Jac compiler.
- Follow red-green-refactor: every production behavior is preceded by a test that fails for the expected reason.

---

### Task 1: Root JacHammer Coordinator Project

**Files:**
- Create: `jac.toml`
- Create: `main.sv.jac`
- Create: `platform/coordinator/src/service.jac`
- Create: `tests/deploy/test_jachammer_root.sh`
- Modify: `platform/coordinator/main.sv.jac`
- Modify: `platform/coordinator/src/model.jac`

**Interfaces:**
- Produces: root API-service entrypoint `main.sv.jac`.
- Produces: shared coordinator service module
  `platform.coordinator.src.service`.
- Produces: `JACGRID_HOSTED=1` fail-closed startup behavior.
- Preserves: nested commands from `platform/coordinator`, including
  `JACGRID_SELFTEST=1 ../../.venv/bin/jac run main.sv.jac`.
- Preserves: existing walker names and request/response contracts.

- [ ] **Step 1: Write the failing root deployment test**

Create `tests/deploy/test_jachammer_root.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JAC="$REPO_ROOT/.venv/bin/jac"
TEST_KEY="jachammer-root-test-key"

fail() {
    echo "[jachammer root test] FAIL: $*" >&2
    exit 1
}

[ -x "$JAC" ] || fail "missing Jac executable at $JAC"
[ -f "$REPO_ROOT/jac.toml" ] || fail "missing root jac.toml"
[ -f "$REPO_ROOT/main.sv.jac" ] || fail "missing root main.sv.jac"

(
    cd "$REPO_ROOT"
    "$JAC" check main.sv.jac
    JACGRID_KEY="$TEST_KEY" JACGRID_HOSTED=1 JACGRID_SELFTEST=1 \
        "$JAC" run main.sv.jac
)

(
    cd "$REPO_ROOT/platform/coordinator"
    "$JAC" check main.sv.jac
    JACGRID_KEY="$TEST_KEY" JACGRID_HOSTED=1 JACGRID_SELFTEST=1 \
        "$JAC" run main.sv.jac
)

set +e
HOSTED_OUTPUT="$(
    cd "$REPO_ROOT"
    JACGRID_HOSTED=1 JACGRID_KEY= "$JAC" run main.sv.jac 2>&1
)"
HOSTED_STATUS=$?
set -e
[ "$HOSTED_STATUS" -ne 0 ] || fail "hosted mode accepted an empty key"
printf '%s' "$HOSTED_OUTPUT" | grep -Fq \
    "JACGRID_HOSTED=1 requires a non-development JACGRID_KEY" \
    || fail "hosted failure did not explain the key requirement"

set +e
DEFAULT_OUTPUT="$(
    cd "$REPO_ROOT"
    JACGRID_HOSTED=1 JACGRID_KEY=jacgrid-dev-key \
        "$JAC" run main.sv.jac 2>&1
)"
DEFAULT_STATUS=$?
set -e
[ "$DEFAULT_STATUS" -ne 0 ] || fail "hosted mode accepted jacgrid-dev-key"
printf '%s' "$DEFAULT_OUTPUT" | grep -Fq \
    "JACGRID_HOSTED=1 requires a non-development JACGRID_KEY" \
    || fail "default-key failure did not explain the requirement"

echo "[jachammer root test] OK"
```

The production change this test catches is a missing/broken root Jac project,
a nested coordinator regression, or hosted startup accepting an unsafe key.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
bash tests/deploy/test_jachammer_root.sh
```

Expected: exit non-zero with
`[jachammer root test] FAIL: missing root jac.toml`.

- [ ] **Step 3: Extract the shared coordinator service**

Move the coordinator helpers, walkers, explanatory comments, and self-test
entry block from `platform/coordinator/main.sv.jac` into
`platform/coordinator/src/service.jac`.

Do not copy or rename walkers. The nested entrypoint becomes:

```jac
"""JacGrid coordinator local entrypoint."""

include src.model;
include src.service;
```

The root entrypoint becomes:

```jac
"""JacGrid coordinator JacHammer entrypoint."""

::py::
import platform as _stdlib_platform
from pathlib import Path as _Path
_stdlib_platform.__path__ = [
    str(_Path(__file__).resolve().parent / "platform")
]
::py::

include platform.coordinator.src.model;
include platform.coordinator.src.service;
```

The inline bridge loads Python's real standard-library `platform` module
first, preserving APIs used by Jac itself, then makes that loaded module a
package namespace whose search path includes this repository's `platform/`
directory. Do not add `platform/__init__.jac`: that would shadow the standard
library during Jac CLI bootstrap.

The service module must not include the model itself; each entrypoint includes
the same two modules into one program namespace.

- [ ] **Step 4: Add hosted fail-closed configuration**

In the shared service's `with entry` block, before the existing self-test,
enforce:

```jac
if os.environ.get("JACGRID_HOSTED", "0") == "1" {
    assert API_KEY != "" and API_KEY != "jacgrid-dev-key",
        "JACGRID_HOSTED=1 requires a non-development JACGRID_KEY";
}
```

Keep the existing self-test body unchanged after this guard.

- [ ] **Step 5: Make repository discovery independent of source depth**

Inside the Python section of `platform/coordinator/src/model.jac`, replace
both `Path(__file__).resolve().parents[3]` expressions with one helper:

```python
def _coordinator_repo_root():
    from pathlib import Path

    for candidate in Path(__file__).resolve().parents:
        if (
            (candidate / "sandbox" / "runner" / "registry.jac").is_file()
            and (candidate / "platform" / "coordinator" / "jac.toml").is_file()
        ):
            return str(candidate)
    raise RuntimeError(
        "JacGrid repository root not found; sandbox package is missing"
    )
```

Both bridge functions call `repo_root = _coordinator_repo_root()`.

- [ ] **Step 6: Add the root Jac project**

Create root `jac.toml`:

```toml
[project]
name = "jacgrid-jachammer-coordinator"
version = "0.1.0"
description = "JacGrid public coordinator for JacHammer sandbox deployment"
entry-point = "main.sv.jac"
kind = "api-service"

[serve]
port = 8000

[dependencies]

[dev-dependencies]
watchdog = ">=3.0.0"
```

- [ ] **Step 7: Validate Jac syntax and run GREEN**

Read the complete changed Jac files and call Jac MCP `validate_jac` on each
entrypoint/module combination. Fix errors using `explain_error`, then rerun:

```bash
bash tests/deploy/test_jachammer_root.sh
```

Expected terminal lines include two `[selftest] OK` lines and:

```text
[jachammer root test] OK
```

- [ ] **Step 8: Run coordinator regression tests**

Run:

```bash
bash tests/integration/e2e_noop.sh
bash tests/integration/e2e_contract_b.sh
```

Expected: both commands exit 0 and print their `OK` markers.

- [ ] **Step 9: Commit Task 1**

```bash
git add jac.toml main.sv.jac \
  platform/coordinator/main.sv.jac \
  platform/coordinator/src/model.jac \
  platform/coordinator/src/service.jac \
  tests/deploy/test_jachammer_root.sh
git commit -m "Add JacHammer coordinator root project"
```

---

### Task 2: Hosted Smoke and Worker Connection Tooling

**Files:**
- Create: `scripts/deploy/jachammer/smoke_coordinator.sh`
- Create: `scripts/deploy/jachammer/connect_worker.sh`
- Create: `tests/deploy/test_jachammer_tools.sh`
- Modify: `scripts/demo/start_worker.sh`
- Modify: `scripts/demo/submit_demo_job.sh`

**Interfaces:**
- Consumes: `POST <URL>/walker/network_status` with body
  `{"secret":"<JACGRID_KEY>"}`.
- Produces: `smoke_coordinator.sh [--allow-http] URL`.
- Produces:
  `connect_worker.sh [--allow-http] --url URL --name NAME`.
- Delegates worker execution to:
  `scripts/demo/start_worker.sh --coordinator URL --name NAME`.

- [ ] **Step 1: Write the failing tooling test**

Create `tests/deploy/test_jachammer_tools.sh`. It starts the root coordinator
on an unused local port, waits for `/healthz`, and verifies observable script
behavior:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JAC="$REPO_ROOT/.venv/bin/jac"
PORT="${JACGRID_TEST_PORT:-18110}"
URL="http://127.0.0.1:$PORT"
KEY="jachammer-tools-test-key"
SERVER_LOG="$(mktemp)"
SERVER_PID=""

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f "$SERVER_LOG"
}
trap cleanup EXIT

(
    cd "$REPO_ROOT"
    JACGRID_KEY="$KEY" JACGRID_HOSTED=1 \
        "$JAC" start main.sv.jac --no_client --port "$PORT"
) >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 60); do
    curl --noproxy '*' -fsS "$URL/healthz" >/dev/null 2>&1 && break
    kill -0 "$SERVER_PID" 2>/dev/null \
        || { cat "$SERVER_LOG" >&2; exit 1; }
    sleep 0.5
done
curl --noproxy '*' -fsS "$URL/healthz" >/dev/null

JACGRID_KEY="$KEY" \
    "$REPO_ROOT/scripts/deploy/jachammer/smoke_coordinator.sh" \
    --allow-http "$URL" \
    | grep -F "JacGrid coordinator ready: $URL"

set +e
WRONG_OUTPUT="$(
    JACGRID_KEY=wrong \
        "$REPO_ROOT/scripts/deploy/jachammer/smoke_coordinator.sh" \
        --allow-http "$URL" 2>&1
)"
WRONG_STATUS=$?
set -e
[ "$WRONG_STATUS" -ne 0 ]
printf '%s' "$WRONG_OUTPUT" \
    | grep -Fq "coordinator rejected JACGRID_KEY"

set +e
HTTP_OUTPUT="$(
    JACGRID_KEY="$KEY" \
        "$REPO_ROOT/scripts/deploy/jachammer/smoke_coordinator.sh" \
        "$URL" 2>&1
)"
HTTP_STATUS=$?
set -e
[ "$HTTP_STATUS" -ne 0 ]
printf '%s' "$HTTP_OUTPUT" \
    | grep -Fq "public JacHammer URL must use https://"

"$REPO_ROOT/scripts/deploy/jachammer/connect_worker.sh" --help \
    | grep -Fq "connect_worker.sh"

echo "[jachammer tools test] OK"
```

The production changes this catches are accepting insecure hosted URLs,
ignoring an invalid key, failing to parse the Jac response envelope, or
shipping a worker command without a usable CLI contract.

- [ ] **Step 2: Run the tooling test and verify RED**

Run:

```bash
bash tests/deploy/test_jachammer_tools.sh
```

Expected: exit non-zero because
`scripts/deploy/jachammer/smoke_coordinator.sh` does not exist.

- [ ] **Step 3: Implement the hosted smoke command**

`smoke_coordinator.sh` must:

- require `JACGRID_KEY` to be set and reject `jacgrid-dev-key`;
- accept one URL and optional `--allow-http`;
- strip one trailing slash;
- require `https://` unless `--allow-http` is present;
- call `network_status` with `curl --noproxy '*'`, a 5-second connect timeout,
  and a 20-second total timeout;
- parse `(.data.reports // .reports // [])[0]`;
- fail with `coordinator rejected JACGRID_KEY` on `unauthorized`;
- require `server_time`, `workers`, and `jobs`; and
- print only the URL, worker count, and job count, never the key.

Success output:

```text
JacGrid coordinator ready: <URL>
workers=<number> jobs=<number>
```

- [ ] **Step 4: Implement the worker connection command**

`connect_worker.sh` parses `--url`, `--name`, `--allow-http`, and `--help`.
It requires a non-development `JACGRID_KEY`, runs the smoke command first,
exports `JACGRID_COORDINATOR`, and then uses:

```bash
exec "$REPO_ROOT/scripts/demo/start_worker.sh" \
    --coordinator "$URL" --name "$WORKER_NAME"
```

For local tests, `--allow-http` is forwarded to the smoke command only.
The public demo command never uses it.

- [ ] **Step 5: Correct cloud-facing diagnostics**

Update error guidance in `scripts/demo/start_worker.sh` and
`scripts/demo/submit_demo_job.sh` so an unreachable public URL mentions:

```text
Check the deployment URL, JacHammer sandbox status, internet access, and shared key.
```

Do not change the request or response contracts.

- [ ] **Step 6: Run GREEN and shell checks**

Run:

```bash
bash -n scripts/deploy/jachammer/smoke_coordinator.sh
bash -n scripts/deploy/jachammer/connect_worker.sh
bash -n tests/deploy/test_jachammer_tools.sh
bash tests/deploy/test_jachammer_tools.sh
```

Expected: exit 0 and `[jachammer tools test] OK`.

- [ ] **Step 7: Run worker regression tests**

Run:

```bash
bash platform/worker/tests/selftest_modes.sh
bash tests/integration/e2e_noop.sh
```

Expected: both commands exit 0 and print their `OK` markers.

- [ ] **Step 8: Commit Task 2**

```bash
git add scripts/deploy/jachammer/smoke_coordinator.sh \
  scripts/deploy/jachammer/connect_worker.sh \
  scripts/demo/start_worker.sh scripts/demo/submit_demo_job.sh \
  tests/deploy/test_jachammer_tools.sh
git commit -m "Add JacHammer connection and smoke tooling"
```

---

### Task 3: JacHammer Runbook and Full Local Acceptance

**Files:**
- Create: `docs/deployment/jachammer-sandbox-runbook.md`
- Modify: `scripts/README.md`
- Modify: `platform/coordinator/README.md`

**Interfaces:**
- Documents the exact environment variables from Global Constraints.
- Documents the scripts created in Task 2 without duplicating their internal
  logic.
- Produces the user handoff for JacHammer Preview, Sandbox deploy, two-worker
  connection, job submission, verification, and teardown.

- [ ] **Step 1: Write the runbook**

The runbook must contain these ordered phases and exact commands:

1. Push the implementation branch to GitHub.
2. In JacHammer: create project, import repository, choose the implementation
   branch, open project settings, and add:

   ```text
   JACGRID_HOSTED=1
   JACGRID_KEY=<a newly generated secret>
   JACGRID_SUSPECT_AFTER=15
   JACGRID_DEAD_AFTER=30
   JACGRID_MAX_ATTEMPTS=3
   JACGRID_SWEEP_INTERVAL=5
   ```

3. Generate the key locally without printing it into repository files:

   ```bash
   export JACGRID_KEY="$(openssl rand -hex 24)"
   ```

4. Run JacHammer Preview and confirm `/healthz`.
5. Open Deploy, select Sandbox, deploy, and copy the public HTTPS URL.
6. On each Mac:

   ```bash
   cd /path/to/jac_ddp
   git pull
   source .venv/bin/activate
   export JACGRID_KEY='<same key configured in JacHammer>'
   export JACGRID_COORDINATOR='https://<jachammer-sandbox-host>'
   ./scripts/deploy/jachammer/smoke_coordinator.sh \
       "$JACGRID_COORDINATOR"
   ./scripts/deploy/jachammer/connect_worker.sh \
       --url "$JACGRID_COORDINATOR" \
       --name "mac-1-worker"
   ```

   Mac 2 uses `--name "mac-2-worker"`.

7. From a third terminal:

   ```bash
   ./scripts/demo/submit_demo_job.sh \
       --coordinator "$JACGRID_COORDINATOR"
   ```

8. Inspect `network_status`, `get_job`, and `audit_job` with copy-paste curl
   commands that parse `.data.reports[0]`.
9. State that the sandbox expires after seven days and may lose SQLite state
   after redeployment/restart.
10. Troubleshoot build failure, `unauthorized`, expired sandbox URL, worker
    timeout, and a job handled by only one worker.

- [ ] **Step 2: Update index documentation**

Add links to the runbook from `scripts/README.md` and
`platform/coordinator/README.md`. Add root and nested local commands to the
coordinator README:

```bash
# JacHammer-equivalent root project
JACGRID_KEY=test-key JACGRID_HOSTED=1 \
  .venv/bin/jac run main.sv.jac

# Existing nested local project
cd platform/coordinator
JACGRID_KEY=test-key JACGRID_HOSTED=1 \
  ../../.venv/bin/jac run main.sv.jac
```

- [ ] **Step 3: Self-review the runbook**

Read every command in sequence and verify:

- every terminal re-exports the public URL and key;
- Mac 1 and Mac 2 have distinct worker names;
- no real key value appears;
- every API response uses `.data.reports[0]`;
- the first job is `noop`;
- no permanent-storage or hosted-embedding claim appears; and
- no placeholder other than angle-bracket values the user must replace
  remains.

Human-facing prose does not receive a source-text test.

- [ ] **Step 4: Run the complete local acceptance suite**

Run from repository root:

```bash
bash tests/deploy/test_jachammer_root.sh
bash tests/deploy/test_jachammer_tools.sh
bash platform/worker/tests/selftest_modes.sh
bash sandbox/tests/run_tests.sh
bash tests/integration/e2e_noop.sh
bash tests/integration/e2e_contract_b.sh
bash tests/integration/e2e_reassign.sh
bash tests/integration/e2e_sweeper.sh
git diff --check
```

Expected: all commands exit 0. Record every command and terminal `OK` marker in
the task report.

- [ ] **Step 5: Commit Task 3**

```bash
git add docs/deployment/jachammer-sandbox-runbook.md \
  scripts/README.md platform/coordinator/README.md
git commit -m "Document JacHammer sandbox deployment demo"
```

- [ ] **Step 6: Hosted acceptance handoff**

Do not claim JacHammer deployment success from local tests. Report that the
repository is locally deployment-ready and give the user only these remaining
external actions:

1. push/import the implementation branch;
2. set the JacHammer environment variables;
3. deploy the sandbox;
4. return or export the generated HTTPS URL; and
5. run the hosted smoke and two-Mac commands from the runbook.
