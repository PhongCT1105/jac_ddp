"""JacGrid coordinator — walkers (the HTTP surface).

This is its own Jac project (`platform/coordinator/jac.toml`). From that dir:

Self-test:  JACGRID_SELFTEST=1 jac run main.sv.jac
Serve REST: jac start main.sv.jac --no_client --port 8000
Check:      jac check .

HOW THE GRAPH IS SHARED WHEN SERVED (jaclang 0.16 / jac-scale)
--------------------------------------------------------------
jac-scale turns auth ON by default and hands every *authenticated* user their
own isolated root graph — which would fragment coordinator state across users.
Two things keep JacGrid on ONE graph:

  1. Every walker is declared `walker:pub`, so `POST /walker/{name}` needs no
     JWT. Anonymous callers all run as the same guest identity.
  2. Every walker ability anchors on `root.shared` (bound to the local name
     `grid`) instead of on `here`/`root`. `root.shared` is jac-scale's single
     public commons graph and resolves to the same graph from every request
     context, so workers, apps and dashboards all read and write the same jobs.
     Outside a server (`jac run`, tests) `jid(root.shared) == jid(root)`, so the
     self-test below exercises exactly the same code path.

Real authorization is the shared secret in the `secret` body field (checked
against JACGRID_KEY, default "jacgrid-dev-key") — see `auth_ok` below.

THE SHARING GUARANTEE COMES FROM `root.shared`, NOT FROM `walker:pub`
--------------------------------------------------------------------
Be precise about this, because the general rule cuts the other way. The
jac-sv-multi-user guide is explicit: "Anonymous callers land on the guest
graph, token-holders on their own root — so a `:pub` 'global graph' isn't even
one graph." That is true of `here` / `root`. It is NOT true of `root.shared`,
which the same guide describes as the deployment's one public commons that
"resolves to it from any request context".

Verified live on jaclang 0.16.7 / jac-scale 0.2.31 (see report-A2 §Fix 3):
registered and logged in a real user (`role=user`, its own `root_id`), then

  * called `network_status` WITH `Authorization: Bearer <jwt>` — it saw the job
    an anonymous caller had created (same `job_id`);
  * called `register_worker` WITH the bearer token, then read `network_status`
    back ANONYMOUSLY — the token-written worker was there.

So token-bearing and anonymous callers do share this graph. The guarantee is
load-bearing on one invariant: **every ability here must anchor on
`root.shared`.** Any ability that touches `here` or `root` instead would land
on the caller's own root and silently fragment the grid — an authenticated
client must never assume shared state without `root.shared` or an explicit
`grant(...)`. The recommended client posture stays token-free: nothing in
JacGrid needs a jac-scale identity.

Contracts: docs/architecture.md §4 (Contract A: create_job/get_job/
get_job_result) and §5 (Contract B: next_task/submit_result envelopes).
"""

include src.model;

def auth_ok(secret: str) -> bool {
    return secret == API_KEY;
}

def unauthorized() -> dict {
    return {"error": "unauthorized", "detail": "missing or invalid `secret` field"};
}

# ---------------------------------------------------------------------------
# Worker lifecycle
# ---------------------------------------------------------------------------

walker:pub register_worker {
    """Create or update the Device + Worker pair for a worker runtime."""

    has secret: str = "";
    has hostname: str = "";
    has capabilities: dict = {};
    has worker_name: str = "";

    can register with Root entry {
        grid = root.shared;
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        if self.hostname == "" {
            report {"error": "invalid_request", "detail": "hostname is required"};
            disengage;
        }
        name = self.worker_name if self.worker_name != "" else self.hostname;
        now = now_ts();

        device = find_device(grid, self.hostname);
        if device is None {
            device = Device(
                device_id=new_id("dev"),
                hostname=self.hostname,
                hardware=self.capabilities,
                created_at=now
            );
            grid ++> device;
        } else {
            device.hardware = self.capabilities;
        }

        worker = find_worker(grid, name);
        created = False;
        if worker is None {
            worker = Worker(
                worker_id=new_id("w"),
                name=name,
                capabilities=self.capabilities,
                status="idle",
                last_seen=now,
                registered_at=now
            );
            grid ++> worker;
            worker +>:HostedOn:+> device;
            created = True;
        } else {
            worker.capabilities = self.capabilities;
            worker.last_seen = now;
            if worker.status == "dead" {
                worker.status = "idle";
                worker.current_task_id = "";
            }
        }
        wallet = get_or_create_wallet(grid, worker.worker_id, worker.name, 0.0);
        coordinator_wallet(grid);
        rep = worker_reputation(worker);

        report {
            "worker_id": worker.worker_id,
            "name": worker.name,
            "device_id": device.device_id,
            "hostname": device.hostname,
            "created": created,
            "status": worker.status,
            "wallet": {"wallet_id": wallet.wallet_id, "balance": wallet.balance,
                       "currency": wallet.currency},
            "reputation": {"success": rep.success, "failure": rep.failure, "score": rep.score},
            "server_time": now,
            "heartbeat_interval_seconds": 5,
            "dead_after_seconds": DEAD_AFTER
        };
    }
}

walker:pub heartbeat {
    """Liveness ping. last_seen is the COORDINATOR receive time — worker clocks
    are never trusted (spec §5)."""

    has secret: str = "";
    has worker_id: str = "";
    has current_task_status: dict = {};

    can beat with Root entry {
        grid = root.shared;
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        worker = find_worker(grid, self.worker_id);
        if worker is None {
            report {"error": "unknown_worker", "worker_id": self.worker_id,
                    "detail": "re-register with register_worker"};
            disengage;
        }
        now = now_ts();
        worker.last_seen = now;
        state = str(self.current_task_status.get("state", ""));
        task_id = str(self.current_task_status.get("task_id", ""));
        if state == "busy" {
            worker.status = "busy";
            worker.current_task_id = task_id;
        } elif state == "idle" {
            worker.status = "idle";
            worker.current_task_id = "";
        } elif worker.status == "dead" {
            worker.status = "idle";
        }
        # Self-healing: every heartbeat is also a failure-detection sweep, so no
        # cron process is required for the network to recover.
        sweep = sweep_failures(grid, DEAD_AFTER);
        report {
            "ok": True,
            "worker_id": worker.worker_id,
            "status": worker.status,
            "server_time": now,
            "sweep": sweep
        };
    }
}

# ---------------------------------------------------------------------------
# Contract A — job submission / status / result
# ---------------------------------------------------------------------------

walker:pub create_job {
    """Contract A `POST /api/jobs`: validate, create the Job, split into Tasks."""

    has secret: str = "";
    has app_id: str = "";
    has job_type: str = "noop";
    has payload: dict = {};
    has partitioning: dict = {};
    has verification: dict = {};
    has budget: dict = {};
    has limits: dict = {};

    can submit with Root entry {
        grid = root.shared;
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        if self.app_id == "" {
            report {"error": "invalid_request", "detail": "app_id is required"};
            disengage;
        }
        if self.job_type not in ALLOWED_JOB_TYPES {
            report {"error": "invalid_request",
                    "detail": "job_type must be one of " + canonical(ALLOWED_JOB_TYPES)};
            disengage;
        }
        if not isinstance(self.payload, dict) or len(self.payload) == 0 {
            report {"error": "invalid_request", "detail": "payload must be a non-empty object"};
            disengage;
        }

        partitioning = self.partitioning if len(self.partitioning) > 0 else {"strategy": "chunk", "chunk_size": 25};
        verification = self.verification if len(self.verification) > 0 else {"method": "recompute_sample", "sample_rate": 0.1};
        budget = self.budget if len(self.budget) > 0 else {"max_total": 0.0, "price_per_task": 0.0, "currency": DEFAULT_CURRENCY};

        verification_check = validate_verification_spec(self.job_type, verification);
        if not verification_check["ok"] {
            report {"error": "invalid_request",
                    "detail": verification_check["detail"]};
            disengage;
        }
        workload = workload_snapshot(self.job_type);
        if not workload.get("ok", False) {
            report {"error": "invalid_request",
                    "detail": "job_type has no resolvable immutable workload: "
                              + str(workload.get("error", "unknown workload error"))};
            disengage;
        }

        price = as_float(budget.get("price_per_task", 0.0), 0.0);
        max_total = as_float(budget.get("max_total", 0.0), 0.0);
        currency = str(budget.get("currency", DEFAULT_CURRENCY));

        slices = chunk_payload(self.payload, partitioning);
        if len(slices) == 0 {
            report {"error": "invalid_request", "detail": "payload produced zero tasks"};
            disengage;
        }
        required = round_to(price * float(len(slices)), 6);
        if required > max_total {
            report {"error": "budget_exceeded",
                    "detail": "price_per_task * task_count exceeds budget.max_total",
                    "task_count": len(slices), "required": required, "max_total": max_total};
            disengage;
        }

        limits = self.limits if len(self.limits) > 0 else DEFAULT_LIMITS;
        now = now_ts();

        app = find_app(grid, self.app_id);
        if app is None {
            app = Application(app_id=self.app_id, registered_at=now);
            grid ++> app;
        }

        job = Job(
            job_id=new_id("job"),
            app_id=self.app_id,
            job_type=self.job_type,
            workload_id=str(workload["workload_id"]),
            workload_version=str(workload["version"]),
            manifest_sha256=str(workload["manifest_sha256"]),
            package_sha256=str(workload["package_sha256"]),
            workload_runtime_tags=workload["runtime_tags"] as list,
            workload_verification=workload["verification"] as dict,
            payload=self.payload,
            partitioning=partitioning,
            verification=verification,
            budget=budget,
            limits=limits,
            status="queued",
            created_at=now,
            task_count=len(slices)
        );
        grid ++> job;
        app +>:Submits:+> job;

        # split_job
        i = 0;
        for slice_payload in slices {
            task = Task(
                task_id=new_id("t"),
                job_id=job.job_id,
                job_type=self.job_type,
                workload_id=job.workload_id,
                workload_version=job.workload_version,
                manifest_sha256=job.manifest_sha256,
                package_sha256=job.package_sha256,
                workload_runtime_tags=job.workload_runtime_tags,
                workload_verification=job.workload_verification,
                idx=i,
                payload=slice_payload as dict,
                limits=limits,
                price_per_task=price,
                currency=currency,
                status="queued",
                created_at=now
            );
            job +>:Contains:+> task;
            i += 1;
        }
        coordinator_wallet(grid);

        report {
            "job_id": job.job_id,
            "status": job.status,
            "task_count": job.task_count
        };
    }
}

walker:pub get_job {
    """Contract A `GET /api/jobs/{job_id}`."""

    has secret: str = "";
    has job_id: str = "";

    can status with Root entry {
        grid = root.shared;
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        job = find_job(grid, self.job_id);
        if job is None {
            report {"error": "unknown_job", "job_id": self.job_id};
            disengage;
        }
        report job_status_view(job);
    }
}

walker:pub get_job_result {
    """Contract A `GET /api/jobs/{job_id}/result`: merged items + payment receipt."""

    has secret: str = "";
    has job_id: str = "";

    can fetch with Root entry {
        grid = root.shared;
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        job = find_job(grid, self.job_id);
        if job is None {
            report {"error": "unknown_job", "job_id": self.job_id};
            disengage;
        }
        recompute_job_status(job);
        if job.status != "complete" {
            report {"error": "not_ready", "job_id": job.job_id, "status": job.status,
                    "progress": job_progress(job), "reason": job.reason};
            disengage;
        }
        report {
            "job_id": job.job_id,
            "results": merged_results(job),
            "receipt": job_receipt(job)
        };
    }
}

# ---------------------------------------------------------------------------
# Scheduling — pull dispatch (spec §2.3)
# ---------------------------------------------------------------------------

walker:pub next_task {
    """select_worker + assign_task: FIFO pull dispatch.

    Returns the Contract B task envelope under `task`, or `task: null` when
    there is nothing this worker may run."""

    has secret: str = "";
    has worker_id: str = "";

    can pull with Root entry {
        grid = root.shared;
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        worker = find_worker(grid, self.worker_id);
        if worker is None {
            report {"error": "unknown_worker", "worker_id": self.worker_id,
                    "detail": "re-register with register_worker"};
            disengage;
        }
        now = now_ts();
        worker.last_seen = now;
        if worker.status == "dead" {
            worker.status = "idle";
        }
        # Worker of last resort: sweep before dispatching so tasks stranded on a
        # dead worker become schedulable again in this very call.
        sweep = sweep_failures(grid, DEAD_AFTER);
        worker.last_seen = now_ts();
        if worker.status == "dead" {
            worker.status = "idle";
            worker.current_task_id = "";
        }

        supported: list = [];
        declared = worker.capabilities.get("job_types", []);
        if isinstance(declared, list) {
            supported = declared;
        }

        best_task: Task | None = None;
        best_job: Job | None = None;
        best_key: tuple[float, int] | None = None;
        for job in all_jobs(grid) {
            if job.status == "complete" or job.status == "failed" {
                continue;
            }
            for task in job_tasks(job) {
                if task.status != "queued" {
                    continue;
                }
                if len(supported) > 0 and task.job_type not in supported {
                    continue;
                }
                if worker.worker_id in task.excluded_workers or worker.name in task.excluded_workers {
                    continue;
                }
                key = (job.created_at, task.idx);
                if best_key is None or key < best_key {
                    best_key = key;
                    best_task = task;
                    best_job = job;
                }
            }
        }

        if best_task is None or best_job is None {
            worker.status = "idle";
            worker.current_task_id = "";
            report {"task": None, "attempt_id": None, "sweep": sweep};
            disengage;
        }
        # The 0.16 checker drops None-narrowing for names assigned inside a loop,
        # so re-land them concretely (`as` is a type-erased, runtime no-op cast).
        sel_task = best_task as Task;
        sel_job = best_job as Job;

        attempt = Attempt(
            attempt_id=new_id("a"),
            task_id=sel_task.task_id,
            worker_id=worker.worker_id,
            worker_name=worker.name,
            status="running",
            started_at=now_ts()
        );
        sel_task +>:AttemptedBy:+> attempt;
        attempt +>:ExecutedBy:+> worker;

        sel_task.status = "running";
        sel_task.attempt_count += 1;
        worker.status = "busy";
        worker.current_task_id = sel_task.task_id;
        recompute_job_status(sel_job);

        report {
            "task": task_envelope(sel_task),
            "attempt_id": attempt.attempt_id,
            "job_id": sel_job.job_id,
            "price_per_task": sel_task.price_per_task,
            "currency": sel_task.currency,
            "sweep": sweep
        };
    }
}

walker:pub submit_result {
    """verify_result -> release_payment -> update_reputation.

    `result_envelope` is the Contract B result envelope produced by the sandbox
    (architecture §5)."""

    has secret: str = "";
    has task_id: str = "";
    has result_envelope: dict = {};

    can submit with Root entry {
        grid = root.shared;
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        found = find_task(grid, self.task_id);
        if len(found) == 0 {
            report {"error": "unknown_task", "task_id": self.task_id};
            disengage;
        }
        task = found[0] as Task;
        job = found[1] as Job;
        attempt = running_attempt(task);
        if attempt is None {
            report {"error": "no_running_attempt", "task_id": task.task_id,
                    "task_status": task.status,
                    "detail": "the attempt was already failed or reassigned; result discarded"};
            disengage;
        }
        worker = attempt_worker(attempt);

        # Contract B is enforced at the door. A result envelope without a
        # well-formed mandatory `execution` block is a PROTOCOL VIOLATION, not
        # a failed task: it is rejected outright, nothing enters the graph, and
        # the Attempt is left untouched so the task stays `running` and the
        # normal timeout / dead-worker sweep can reassign it.
        check = validate_result_envelope(self.result_envelope);
        if not check["ok"] {
            report {"error": "protocol_violation",
                    "task_id": task.task_id,
                    "task_status": task.status,
                    "attempt_id": attempt.attempt_id,
                    "contract": "B (architecture.md §5 result envelope)",
                    "detail": check["detail"],
                    "note": "result discarded; the attempt is still running and will be reassigned on timeout"};
            disengage;
        }
        envelope = self.result_envelope as dict;
        status = str(envelope["status"]);
        output_raw = envelope["output"];
        output: dict = {};
        if isinstance(output_raw, dict) {
            output = output_raw as dict;
        }
        execution = envelope["execution"] as dict;
        error_text = envelope.get("error", None);
        now = now_ts();

        result = Result(
            result_id=new_id("res"),
            task_id=task.task_id,
            status=status,
            output=output,
            execution=execution,
            error="" if error_text is None else str(error_text),
            received_at=now,
            output_hash=hash_output(output)
        );
        attempt +>:Produced:+> result;

        sandbox = Sandbox(
            sandbox_id=new_id("sbx"),
            runtime=str(execution.get("runtime", "unknown")),
            limits=task.limits,
            execution=execution
        );
        attempt +>:RanInside:+> sandbox;

        if worker is not None {
            worker.last_seen = now;
            worker.current_task_id = "";
            worker.status = "idle";
        }

        ver = run_verification(job, task, result);

        payment_view: dict | None = None;
        reputation_view: dict | None = None;
        outcome: dict = {};

        if ver.outcome == "passed" {
            attempt.status = "complete";
            attempt.finished_at = now;
            task.status = "complete";
            task.reason = "";
            if worker is not None {
                pay = ledger_pay(grid, task, job, worker);
                payment_view = {
                    "payment_id": pay.payment_id,
                    "task_id": pay.task_id,
                    "worker": pay.worker_name,
                    "amount": pay.amount,
                    "currency": pay.currency,
                    "tx": pay.tx,
                    "backend": pay.backend
                };
                reputation_view = bump_reputation(worker, True);
            }
            outcome = {"action": "accepted"};
        } else {
            reason = "verification failed: " + canonical(ver.detail)[0:400];
            outcome = fail_attempt(job, task, attempt, reason);
            if worker is not None {
                reputation_view = {"worker_id": worker.worker_id,
                                   "success": worker_reputation(worker).success,
                                   "failure": worker_reputation(worker).failure,
                                   "score": worker_reputation(worker).score};
            }
        }
        recompute_job_status(job);

        report {
            "task_id": task.task_id,
            "task_status": task.status,
            "job_id": job.job_id,
            "job_status": job.status,
            "verification": {"verification_id": ver.verification_id, "method": ver.method,
                             "outcome": ver.outcome, "detail": ver.detail},
            "payment": payment_view,
            "reputation": reputation_view,
            "outcome": outcome
        };
    }
}

# ---------------------------------------------------------------------------
# Monitoring / audit
# ---------------------------------------------------------------------------

walker:pub detect_failures {
    """detect_failure + reassign_task sweep. Call periodically, or rely on the
    implicit sweeps inside next_task/heartbeat.

    `dead_after` overrides the 30s default (used by the reassignment demo)."""

    has secret: str = "";
    has dead_after: float = 0.0;

    can sweep with Root entry {
        grid = root.shared;
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        threshold = self.dead_after if self.dead_after > 0.0 else DEAD_AFTER;
        report sweep_failures(grid, threshold);
    }
}

# ---------------------------------------------------------------------------
# WHY THERE IS NO @schedule'd SWEEP HERE (spec §2.4 wants one every 5s)
# ---------------------------------------------------------------------------
# `@schedule` IS real on this stack: it is a jaclang builtin that stamps a
# `schedule_spec` on its target, and at startup jac-scale scans loaded walkers
# and functions for it ("Base Scheduler started with 1 static task(s)").
# Both forms were tried live on jaclang 0.16.7 / jac-scale 0.2.31 and BOTH are
# unusable for mutating the graph:
#
#   @schedule(interval=N) walker:pub ...  -> registers, then fails on EVERY
#       tick with "Error executing task 'x': Invalid walker object".
#       jac_scale/scheduler/impl/scheduler.impl.jac passes the walker *class*
#       from `introspector._walkers` to spawn_walker, but `spawn` requires a
#       walker *instance* (jaclang/jac0core/impl/runtime.impl.jac raises).
#
#   @schedule(interval=N) def:pub ...     -> registers AND executes (its print
#       output appears, and it correctly READS the shared graph — it found the
#       dead worker and the stranded task). But its WRITES never land: the
#       scheduler runs each job in a deliberately isolated context
#       (JScaleExecutionContext + ctx.mem.close(), "so concurrent jobs cannot
#       ... interfere with in-flight HTTP requests"). Proof: it reported
#       "1 dead worker(s), 1 task(s) requeued" on every single tick — the
#       scheduler's own next tick, reading fresh, still saw the task as
#       `running` — and `get_job` over HTTP never observed the requeue.
#
# So failure detection is driven from OUTSIDE the process instead, by a client
# that hits the ordinary `detect_failures` endpoint on a timer and therefore
# commits through the normal request path. Ship one with:
#
#     cd platform/worker && JACGRID_MODE=sweeper jac run main.jac
#
# (or any `while true; do curl .../walker/detect_failures; sleep 5; done`).
# The implicit sweeps inside next_task/heartbeat remain as the in-band
# fallback. See both READMEs.

walker:pub audit_job {
    """Full execution tree: job -> tasks -> attempts -> worker/sandbox/result/
    verification/payment."""

    has secret: str = "";
    has job_id: str = "";

    can walk with Root entry {
        grid = root.shared;
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        job = find_job(grid, self.job_id);
        if job is None {
            report {"error": "unknown_job", "job_id": self.job_id};
            disengage;
        }
        report audit_tree(job);
    }
}

walker:pub network_status {
    """Dashboard feed: devices, workers, liveness, wallets, jobs."""

    has secret: str = "";

    can survey with Root entry {
        grid = root.shared;
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        now = now_ts();
        devices = [];
        for d in all_devices(grid) {
            devices.append({
                "device_id": d.device_id,
                "hostname": d.hostname,
                "hardware": d.hardware,
                "owner": d.owner,
                "created_at": iso(d.created_at)
            });
        }
        workers = [];
        for w in all_workers(grid) {
            dev = worker_device(w);
            rep = worker_reputation(w);
            wallet = get_or_create_wallet(grid, w.worker_id, w.name, 0.0);
            workers.append({
                "worker_id": w.worker_id,
                "name": w.name,
                "device": dev.hostname if dev is not None else "",
                "capabilities": w.capabilities,
                "status": w.status,
                "liveness": liveness(w, now),
                "seconds_since_heartbeat": round_to(now - w.last_seen, 2),
                "current_task_id": w.current_task_id,
                "wallet": {"wallet_id": wallet.wallet_id, "balance": wallet.balance,
                           "currency": wallet.currency},
                "reputation": {"success": rep.success, "failure": rep.failure, "score": rep.score}
            });
        }
        wallets = [];
        for wl in all_wallets(grid) {
            wallets.append({"wallet_id": wl.wallet_id, "owner": wl.owner,
                            "owner_name": wl.owner_name, "balance": wl.balance,
                            "currency": wl.currency});
        }
        jobs = [];
        for j in all_jobs(grid) {
            recompute_job_status(j);
            jobs.append({"job_id": j.job_id, "app_id": j.app_id, "job_type": j.job_type,
                         "status": j.status, "task_count": j.task_count,
                         "progress": job_progress(j)});
        }
        report {
            "server_time": now,
            "thresholds": {"suspect_after": SUSPECT_AFTER, "dead_after": DEAD_AFTER,
                           "max_attempts": MAX_ATTEMPTS},
            "devices": devices,
            "workers": workers,
            "wallets": wallets,
            "jobs": jobs
        };
    }
}

# ---------------------------------------------------------------------------
# In-process self-test (JACGRID_SELFTEST=1 jac run coordinator/main.jac)
# ---------------------------------------------------------------------------

with entry {
    if os.environ.get("JACGRID_HOSTED", "0") == "1" {
        assert API_KEY != "" and API_KEY != "jacgrid-dev-key",
            "JACGRID_HOSTED=1 requires a non-development JACGRID_KEY";
    }
    if os.environ.get("JACGRID_SELFTEST", "0") == "1" {
        print("[selftest] JacGrid coordinator");
        # same anchor the walkers use; under `jac run` this IS `root`
        grid = root.shared;
        root spawn register_worker(
            secret=API_KEY, hostname="selftest-host", worker_name="selftest-worker",
            capabilities={"cpu_cores": 8, "memory_mb": 16384, "job_types": ["noop", "embedding"]}
        );
        root spawn create_job(
            secret=API_KEY, app_id="selftest-app", job_type="noop",
            payload={"items": [{"id": "i1", "text": "a"}, {"id": "i2", "text": "b"}]},
            partitioning={"strategy": "chunk", "chunk_size": 1},
            verification={"method": "recompute_sample", "sample_rate": 1.0},
            budget={"max_total": 1.0, "price_per_task": 0.1, "currency": "TESTUSD"}
        );
        jobs = [grid -->[?:Job]];
        job = jobs[len(jobs) - 1];
        workers = [grid -->[?:Worker]];
        selftest_worker_id = "";
        for w in workers {
            if w.name == "selftest-worker" {
                selftest_worker_id = w.worker_id;
            }
        }
        assert selftest_worker_id != "", "selftest worker was not registered";
        for task in job_tasks(job) {
            root spawn next_task(secret=API_KEY, worker_id=selftest_worker_id);
            root spawn submit_result(
                secret=API_KEY, task_id=task.task_id,
                result_envelope={
                    "task_id": task.task_id,
                    "status": "ok",
                    "output": {"results": task.payload["items"]},
                    "execution": {"runtime": "selftest:v0", "started_at": iso(now_ts()),
                                  "finished_at": iso(now_ts()), "peak_memory_mb": 1,
                                  "cpu_seconds": 0.0, "exit_code": 0},
                    "error": None
                }
            );
        }
        status = job_status_view(job);
        receipt = job_receipt(job);
        print("[selftest] status=" + str(status["status"]) + " progress=" + str(status["progress"]));
        print("[selftest] receipt=" + canonical(receipt));
        assert status["status"] == "complete", "job did not complete";
        assert receipt["verified"] == 2, "expected 2 verified tasks";
        assert receipt["total_paid"] == 0.2, "expected 0.2 paid";
        audit = audit_tree(job);
        assert len(audit["tasks"] as list) == 2, "expected 2 tasks in audit";
        print("[selftest] OK");
    }
}
