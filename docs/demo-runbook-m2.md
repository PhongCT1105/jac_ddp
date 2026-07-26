# JacGrid M2: three-Mac demo runbook

This runbook brings up one JacGrid coordinator and three workers over raw LAN
IPv4. Each Mac needs this repository and its existing `.venv`. The scripts
activate that virtualenv themselves.

## Before the audience arrives

1. Put all three Macs on the same Wi-Fi or phone hotspot.
2. On each Mac, update the checkout and confirm `.venv/bin/jac` exists.
3. Decide on one shared secret. The default is `jacgrid-dev-key`; if you set
   `JACGRID_KEY`, set the same value in every terminal on all three Macs.
4. Know which Mac is Mac 1 (coordinator), Mac 2, and Mac 3.
5. Run the automated rehearsal once on Mac 1:

   ```bash
   ./tests/integration/e2e_lan_sandbox_embedding.sh
   ```

   It uses Mac 1's real non-loopback IPv4, temporary unused ports, two
   sandbox workers, and the live connection-agent. It restores existing
   coordinator/app graph state when it exits.

The examples assume every terminal starts at the repository root.

## Beat 1: start the coordinator on Mac 1

In Mac 1 Terminal 1:

```bash
export JACGRID_PORT=8000
export JACGRID_KEY=jacgrid-dev-key
./scripts/demo/start_coordinator.sh --fresh
```

`--fresh` removes only `platform/coordinator/.jac/data`. Omit it when you want
to keep earlier jobs and worker history.

The launcher chooses the IPv4 on the active physical default-route interface.
It does not select a VPN `utun` address. With multiple interfaces, or when a
VPN owns the default route, explicitly pin the address shown by
`ipconfig getifaddr en0` (Wi-Fi on most Macs):

```bash
export JACGRID_LAN_IP=192.168.1.42
./scripts/demo/start_coordinator.sh --fresh
```

The override must be a non-loopback IPv4 currently assigned to this Mac; a
typo or stale hotspot address is rejected before startup.

Cold startup normally takes 15–25 seconds. Wait for the large banner:

```bash
================================================================================
  export JACGRID_COORDINATOR=http://<MAC-1-LAN-IP>:8000
================================================================================
```

Copy that exact export to every other terminal. Keep Terminal 1 running. The
launcher stays attached to the coordinator; Ctrl-C stops it.

### Network binding finding

This Jac release has no host/bind option. We checked:

```text
$ source .venv/bin/activate
$ jac start --help
usage: jac start ... [-p PORT] ... [filename]
  -p PORT, --port PORT  Server port
```

There is no `--host` or `--bind` entry. `jac start` natively targets all IPv4
interfaces: its startup path calls `s.bind(('0.0.0.0', current_port))`. The
launcher then verifies the effective listener with a walker request through
the Mac's real LAN address. A successful launch has this shape:

```text
$ lsof -nP -iTCP:<PORT> -sTCP:LISTEN
# listener showed *:<PORT>
$ curl --noproxy '*' -sS -X POST \
    http://<MAC-1-LAN-IP>:<PORT>/walker/network_status \
    -H 'Content-Type: application/json' \
    -d '{"secret":"jacgrid-dev-key"}' | jq -c '.data.reports[0]'
{"server_time":...,"thresholds":...,"devices":[],"workers":[],"wallets":[],"jobs":[]}
```

The launcher performs that same LAN-IP walker request before it prints the
export. If the banner appears, local readiness and non-loopback reachability
both passed.

## Beat 2: join all three Macs

On Mac 1, open Terminal 2, paste the printed export, and start its worker:

```bash
export JACGRID_COORDINATOR=http://<MAC-1-LAN-IP>:8000
export JACGRID_KEY=jacgrid-dev-key
JACGRID_TASK_DELAY=2 ./scripts/demo/start_worker.sh --name mac-1-worker
```

Run Mac 1's worker for Beat 3; the distribution assertion requires all three
named workers to participate.

On Mac 2:

```bash
export JACGRID_COORDINATOR=http://<MAC-1-LAN-IP>:8000
export JACGRID_KEY=jacgrid-dev-key
JACGRID_TASK_DELAY=2 ./scripts/demo/start_worker.sh --name mac-2-worker
```

On Mac 3:

```bash
export JACGRID_COORDINATOR=http://<MAC-1-LAN-IP>:8000
export JACGRID_KEY=jacgrid-dev-key
JACGRID_TASK_DELAY=2 ./scripts/demo/start_worker.sh --name mac-3-worker
```

Each launcher first calls `network_status`. It will not start Jac unless the
coordinator is reachable and the key is accepted.

`scripts/demo/start_worker.sh` enables the allowlisted sandbox by default for
the demo (`JACGRID_SANDBOX=1`). Its startup line must say:

```text
Execution: allowlisted sandbox (JACGRID_SANDBOX=1, JACGRID_SEATBELT=0)
```

Set `JACGRID_SANDBOX=0` only as an explicit unisolated fallback while
diagnosing the worker. On macOS, `JACGRID_SEATBELT=1` adds the separately
verified network and write-scope restrictions to each task subprocess:

```bash
JACGRID_SEATBELT=1 ./scripts/demo/start_worker.sh --name mac-2-worker
```

The LAN integration test deliberately leaves Seatbelt at `0`: task subprocess
network denial is independently covered by `sandbox/tests/run_tests.sh`, while
the worker still uses resource limits, process-group containment, the workload
allowlist, and per-task scratch directories.

From any Mac with the coordinator export, verify three live workers:

```bash
curl --noproxy '*' -sS -X POST \
  "$JACGRID_COORDINATOR/walker/network_status" \
  -H 'Content-Type: application/json' \
  -d "{\"secret\":\"${JACGRID_KEY:-jacgrid-dev-key}\"}" \
| jq '.data.reports[0].workers
      | map({name, device, status, liveness, seconds_since_heartbeat})'
```

Expected names are `mac-1-worker`, `mac-2-worker`, and `mac-3-worker`, with
`liveness: "alive"`. The two-second task delay gives every already-registered
worker time to claim work before another worker completes and pulls again.

## Beat 3: submit the demo job

From any Mac with `JACGRID_COORDINATOR` exported:

```bash
reply="$(./scripts/demo/submit_demo_job.sh)"
echo "$reply"
export JACGRID_JOB_ID="$(printf '%s\n' "$reply" | awk -F= '/^job_id=/{print $2}')"
```

The job contains twelve noop items, chunk size 1 (twelve tasks), price 0.1,
and budget 2.0. Watch it finish:

```bash
while true; do
  status="$(
    curl --noproxy '*' -sS -X POST \
      "$JACGRID_COORDINATOR/walker/get_job" \
      -H 'Content-Type: application/json' \
      -d "{\"secret\":\"${JACGRID_KEY:-jacgrid-dev-key}\",\"job_id\":\"$JACGRID_JOB_ID\"}" \
    | jq -r '.data.reports[0].status'
  )"
  echo "status=$status"
  [ "$status" = complete ] && break
  [ "$status" = failed ] && break
  sleep 1
done
```

Do not claim three-Mac distribution from worker registration alone. Assert it
from the paid task receipt:

```bash
result="$(
  curl --noproxy '*' -sS -X POST \
    "$JACGRID_COORDINATOR/walker/get_job_result" \
    -H 'Content-Type: application/json' \
    -d "{\"secret\":\"${JACGRID_KEY:-jacgrid-dev-key}\",\"job_id\":\"$JACGRID_JOB_ID\"}"
)"
paid_workers="$(
  printf '%s' "$result" \
    | jq -r '[.data.reports[0].receipt.payments[].worker] | unique | sort | .[]'
)"
printf 'paid worker: %s\n' $paid_workers
paid_worker_count="$(printf '%s\n' "$paid_workers" | sed '/^$/d' | wc -l | tr -d ' ')"
[ "$paid_worker_count" -ge 3 ] || {
  echo "ERROR: expected >=3 unique paid workers, got $paid_worker_count" >&2
  exit 1
}
```

## Beat 4: run the connection frontend against the live grid

Keep the coordinator and workers running. On Mac 1 Terminal 3:

```bash
cd apps/connection-agent
export JACGRID_MODE=live
export JACGRID_COORDINATOR=http://<MAC-1-LAN-IP>:8000
export JACGRID_KEY=jacgrid-dev-key
../../.venv/bin/jac start main.sv.jac --no_client --port 8080
```

From another terminal, prove the app API through Mac 1's LAN address:

```bash
curl --noproxy '*' -sS http://<MAC-1-LAN-IP>:8080/healthz
```

Open the already-built frontend; do not start a separate frontend toolchain:

```bash
open apps/connection-agent/web/index.html
```

In the page's **API base** field enter
`http://<MAC-1-LAN-IP>:8080` (the connection-agent API, not port 8000).
Click **Seed profiles**, select or create a profile, and click **Find my
matches**. The app calls LiveJacGrid with the same `JACGRID_KEY`, submits a
real embedding job to port 8000, polls its distributed task progress, and
renders three matches plus the verified payment receipt.

For a curl-driven proof of the same live flow, run:

```bash
./tests/integration/e2e_lan_sandbox_embedding.sh
```

The final three `PASS` lines include the exact LAN IP/ports, the two worker
names that earned payments, and the live connection-agent job ID.

## Recovery beat: kill a worker and watch reassignment

Stage this beat separately so the victim reliably claims the task:

1. Stop the Mac 1 and Mac 2 workers with Ctrl-C. Keep the coordinator running.
2. Restart Mac 3's worker with a visible delay:

   ```bash
   JACGRID_TASK_DELAY=20 ./scripts/demo/start_worker.sh --name recovery-victim
   ```

3. Submit another demo job. Wait until Mac 3 prints `running task ...`.
4. In a second Mac 3 terminal, identify the worker process and kill that exact
   PID:

   ```bash
   pgrep -fl 'jac run main.jac'
   kill -9 <RECOVERY-VICTIM-PID>
   ```

5. Wait at least 7 seconds, then force the six-second failure threshold from
   any Mac:

   ```bash
   curl --noproxy '*' -sS -X POST \
     "$JACGRID_COORDINATOR/walker/detect_failures" \
     -H 'Content-Type: application/json' \
     -d "{\"secret\":\"${JACGRID_KEY:-jacgrid-dev-key}\",\"dead_after\":6}" \
   | jq '.data.reports[0]'
   ```

   The response should list `recovery-victim`'s worker ID in `dead_workers`
   and show its running task with `"action": "requeued"`.

6. Restart Mac 2's healthy worker:

   ```bash
   ./scripts/demo/start_worker.sh --name recovery-rescuer
   ```

7. Poll `get_job` as above. The requeued task is excluded from the dead worker,
   the rescuer claims it, and the job completes.

## Shutdown

Use Ctrl-C in the connection-agent terminal, then each worker terminal, then
Mac 1's coordinator terminal. A worker started by `start_worker.sh` is the Jac
process itself, so there is no hidden wrapper daemon to stop.

## Troubleshooting

### Port already in use

`jac start` silently falls back to a different port when its requested port is
busy. The coordinator script prevents that ambiguity with `lsof` and exits
loudly. Stop the listed listener or choose one unused port, then use that same
port in the printed coordinator URL:

```bash
JACGRID_PORT=8010 ./scripts/demo/start_coordinator.sh --fresh
```

### macOS firewall prompt

On first launch, macOS may ask whether Python or Jac may accept incoming
connections. Choose **Allow**. If the prompt was dismissed, open **System
Settings → Network → Firewall → Options** and allow incoming connections for
the Python/Jac executable used by this repo's `.venv`.

### Coordinator works locally but workers cannot connect

Check the raw IP, port, and shared key first. Ensure all Macs are on the same
SSID. Some venue Wi-Fi enables client isolation, which prevents guests from
talking directly even though internet access works. The reliable fallback is
to put all three Macs on the same phone hotspot, restart the coordinator, and
redistribute its newly printed IP export.

VPNs can also change the default route. The launcher ignores `utun` interfaces,
but if several physical interfaces are active, set `JACGRID_LAN_IP` to the
Wi-Fi/Ethernet address you want the other Macs to use. If reachability still
fails, disconnect the VPN and restart so the printed export is regenerated.

### Wrong shared secret

Every caller includes `JACGRID_KEY` in the walker body. An HTTP 200 does not
guarantee success because Jac walker errors are returned in-band. The scripts
unwrap `.data.reports[0]` and fail explicitly on `unauthorized`. Export the
same key on all Macs and restart their processes.

### Clock skew

Clock skew between Macs is harmless for worker liveness. Heartbeats carry
identity and task state, but `last_seen` is recorded from coordinator receive
time only. Suspect/dead thresholds therefore use one clock: Mac 1's.
