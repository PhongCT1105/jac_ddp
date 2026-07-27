# JacHammer coordinator sandbox runbook

This deploys only the coordinator to JacHammer. Workers stay local and connect
to the sandbox over its public HTTPS URL. Sandbox state is temporary: it expires
after seven days and SQLite state can be lost after a redeploy or restart.

## 1. Push the implementation branch

```bash
git push -u origin <implementation-branch>
```

## 2. Create the JacHammer project and configure it

In JacHammer, choose **Create project**, import this repository, choose
`<implementation-branch>`, then open **Project settings** and add these
environment variables. Generate the secret locally first; do not put it in a
repository file or share it in logs.

```bash
export JACGRID_KEY="$(openssl rand -hex 24)"
```

Add the resulting value as `JACGRID_KEY` in JacHammer, along with:

```text
JACGRID_HOSTED=1
JACGRID_KEY=<a newly generated secret>
JACGRID_SUSPECT_AFTER=15
JACGRID_DEAD_AFTER=30
JACGRID_MAX_ATTEMPTS=3
JACGRID_SWEEP_INTERVAL=5
```

Keep the generated value available only in the terminals that will run workers
or API commands. Hosted mode rejects an empty key and `jacgrid-dev-key`.

## 3. Preview, then deploy the sandbox

In JacHammer, run **Preview** for the imported branch. Open
`<preview-https-url>/healthz` and confirm it is healthy. Then open **Deploy**,
select **Sandbox**, deploy, and copy the public HTTPS URL. Use that deployed
URL—not a local IP address—for the commands below.

## 4. Connect Mac 1 and Mac 2

On Mac 1, in a terminal, run:

```bash
cd <path-to-jac_ddp>
git pull
source .venv/bin/activate
export JACGRID_KEY='<same key configured in JacHammer>'
export JACGRID_COORDINATOR='https://<jachammer-sandbox-host>'
./scripts/deploy/jachammer/smoke_coordinator.sh "$JACGRID_COORDINATOR"
./scripts/deploy/jachammer/connect_worker.sh \
    --url "$JACGRID_COORDINATOR" \
    --name "mac-1-worker"
```

Leave the worker process running. On Mac 2, repeat in a separate terminal with
the same key and URL, but a different name:

```bash
cd <path-to-jac_ddp>
git pull
source .venv/bin/activate
export JACGRID_KEY='<same key configured in JacHammer>'
export JACGRID_COORDINATOR='https://<jachammer-sandbox-host>'
./scripts/deploy/jachammer/smoke_coordinator.sh "$JACGRID_COORDINATOR"
./scripts/deploy/jachammer/connect_worker.sh \
    --url "$JACGRID_COORDINATOR" \
    --name "mac-2-worker"
```

## 5. Submit the first job

From a third terminal, export the same two values and submit the `noop` demo
job:

```bash
cd <path-to-jac_ddp>
source .venv/bin/activate
export JACGRID_KEY='<same key configured in JacHammer>'
export JACGRID_COORDINATOR='https://<jachammer-sandbox-host>'
./scripts/demo/submit_demo_job.sh --coordinator "$JACGRID_COORDINATOR"
```

Copy the printed `job_id` into the inspection commands below.

## 6. Inspect the hosted job

With the same `JACGRID_KEY` and `JACGRID_COORDINATOR` exports, each command
extracts the Jac response payload from `.data.reports[0]`:

```bash
curl -sS -X POST "$JACGRID_COORDINATOR/walker/network_status" \
  -H 'Content-Type: application/json' \
  -d "{\"secret\":\"$JACGRID_KEY\"}" | jq -c '.data.reports[0]'

curl -sS -X POST "$JACGRID_COORDINATOR/walker/get_job" \
  -H 'Content-Type: application/json' \
  -d "{\"secret\":\"$JACGRID_KEY\",\"job_id\":\"<job-id>\"}" \
  | jq -c '.data.reports[0]'

curl -sS -X POST "$JACGRID_COORDINATOR/walker/audit_job" \
  -H 'Content-Type: application/json' \
  -d "{\"secret\":\"$JACGRID_KEY\",\"job_id\":\"<job-id>\"}" \
  | jq -c '.data.reports[0]'
```

The coordinator returns authorization and application errors inside the report,
so inspect the parsed payload even when curl receives HTTP 200.

## Troubleshooting

- **Preview/build failure:** confirm the imported branch includes root
  `jac.toml`, `main.sv.jac`, and `src`; review the JacHammer build output, then
  push the correction and rerun Preview.
- **`unauthorized`:** every JacHammer setting, Mac terminal, and curl command
  must use the same newly generated `JACGRID_KEY`; do not use the development
  default in hosted mode.
- **Expired sandbox URL:** deploy a new Sandbox, copy its new public HTTPS URL,
  and re-export `JACGRID_COORDINATOR` in every terminal before restarting both
  workers. Assume prior SQLite state is unavailable.
- **Worker timeout:** verify the worker process is still running, its name is
  unique, and its coordinator URL/key match the sandbox; restart it and inspect
  `network_status`.
- **Only one worker handles the job:** ensure both worker terminals remain
  running before submission. Tasks are pull-dispatched, so scheduling can be
  uneven; submit another `noop` job or add task delay when demonstrating both
  workers.

Do not treat this sandbox as permanent storage or as hosted embedding
verification; the first hosted acceptance target is the `noop` workload.
