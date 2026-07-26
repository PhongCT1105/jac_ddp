"""JacGrid coordinator — walkers (the HTTP surface).

Run locally:      .venv/bin/jac run   coordinator/main.jac      (self-test with JACGRID_SELFTEST=1)
Serve REST:       .venv/bin/jac serve coordinator/main.jac -p 8000

Every walker is exposed by jac-cloud as `POST /walker/{name}`. Auth is handled
by the shared secret in the `secret` body field (checked against JACGRID_KEY,
default "jacgrid-dev-key"); jac-cloud's own auth is disabled per walker.

Contracts: docs/architecture.md §4 (Contract A: create_job/get_job/
get_job_result) and §5 (Contract B: next_task/submit_result envelopes).
"""

include model;

def auth_ok(secret: str) -> bool {
    return secret == API_KEY;
}

def unauthorized() -> dict {
    return {"error": "unauthorized", "detail": "missing or invalid `secret` field"};
}

# ---------------------------------------------------------------------------
# Worker lifecycle
# ---------------------------------------------------------------------------

walker register_worker {
    """Create or update the Device + Worker pair for a worker runtime."""

    has secret: str = "";
    has hostname: str = "";
    has capabilities: dict = {};
    has worker_name: str = "";

    class __specs__ {
        static has auth: bool = False;
    }

    can register with `root entry {
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

        device = find_device(here, self.hostname);
        if device is None {
            device = Device(
                device_id=new_id("dev"),
                hostname=self.hostname,
                hardware=self.capabilities,
                created_at=now
            );
            here ++> device;
        } else {
            device.hardware = self.capabilities;
        }

        worker = find_worker(here, name);
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
            here ++> worker;
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
        wallet = get_or_create_wallet(here, worker.worker_id, worker.name, 0.0);
        coordinator_wallet(here);
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

walker heartbeat {
    """Liveness ping. last_seen is the COORDINATOR receive time — worker clocks
    are never trusted (spec §5)."""

    has secret: str = "";
    has worker_id: str = "";
    has current_task_status: dict = {};

    class __specs__ {
        static has auth: bool = False;
    }

    can beat with `root entry {
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        worker = find_worker(here, self.worker_id);
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
        sweep = sweep_failures(here, DEAD_AFTER);
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

walker create_job {
    """Contract A `POST /api/jobs`: validate, create the Job, split into Tasks."""

    has secret: str = "";
    has app_id: str = "";
    has job_type: str = "noop";
    has payload: dict = {};
    has partitioning: dict = {};
    has verification: dict = {};
    has budget: dict = {};
    has limits: dict = {};

    class __specs__ {
        static has auth: bool = False;
    }

    can submit with `root entry {
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

        price = as_float(budget.get("price_per_task", 0.0), 0.0);
        max_total = as_float(budget.get("max_total", 0.0), 0.0);
        currency = str(budget.get("currency", DEFAULT_CURRENCY));

        slices = chunk_payload(self.payload, partitioning);
        if len(slices) == 0 {
            report {"error": "invalid_request", "detail": "payload produced zero tasks"};
            disengage;
        }
        required = round(price * float(len(slices)), 6);
        if required > max_total {
            report {"error": "budget_exceeded",
                    "detail": "price_per_task * task_count exceeds budget.max_total",
                    "task_count": len(slices), "required": required, "max_total": max_total};
            disengage;
        }

        limits = self.limits if len(self.limits) > 0 else DEFAULT_LIMITS;
        now = now_ts();

        app = find_app(here, self.app_id);
        if app is None {
            app = Application(app_id=self.app_id, registered_at=now);
            here ++> app;
        }

        job = Job(
            job_id=new_id("job"),
            app_id=self.app_id,
            job_type=self.job_type,
            payload=self.payload,
            partitioning=partitioning,
            verification=verification,
            budget=budget,
            limits=limits,
            status="queued",
            created_at=now,
            task_count=len(slices)
        );
        here ++> job;
        app +>:Submits:+> job;

        # split_job
        i = 0;
        for slice_payload in slices {
            task = Task(
                task_id=new_id("t"),
                job_id=job.job_id,
                job_type=self.job_type,
                idx=i,
                payload=slice_payload,
                limits=limits,
                price_per_task=price,
                currency=currency,
                status="queued",
                created_at=now
            );
            job +>:Contains:+> task;
            i += 1;
        }
        coordinator_wallet(here);

        report {
            "job_id": job.job_id,
            "status": job.status,
            "task_count": job.task_count
        };
    }
}

walker get_job {
    """Contract A `GET /api/jobs/{job_id}`."""

    has secret: str = "";
    has job_id: str = "";

    class __specs__ {
        static has auth: bool = False;
    }

    can status with `root entry {
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        job = find_job(here, self.job_id);
        if job is None {
            report {"error": "unknown_job", "job_id": self.job_id};
            disengage;
        }
        report job_status_view(job);
    }
}

walker get_job_result {
    """Contract A `GET /api/jobs/{job_id}/result`: merged items + payment receipt."""

    has secret: str = "";
    has job_id: str = "";

    class __specs__ {
        static has auth: bool = False;
    }

    can fetch with `root entry {
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        job = find_job(here, self.job_id);
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

walker next_task {
    """select_worker + assign_task: FIFO pull dispatch.

    Returns the Contract B task envelope under `task`, or `task: null` when
    there is nothing this worker may run."""

    has secret: str = "";
    has worker_id: str = "";

    class __specs__ {
        static has auth: bool = False;
    }

    can pull with `root entry {
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        worker = find_worker(here, self.worker_id);
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
        sweep = sweep_failures(here, DEAD_AFTER);
        worker.last_seen = now_ts();
        if worker.status == "dead" {
            worker.status = "idle";
            worker.current_task_id = "";
        }

        supported = worker.capabilities.get("job_types", []);
        if not isinstance(supported, list) {
            supported = [];
        }

        best_task = None;
        best_job = None;
        best_key = None;
        for job in all_jobs(here) {
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

        if best_task is None {
            worker.status = "idle";
            worker.current_task_id = "";
            report {"task": None, "attempt_id": None, "sweep": sweep};
            disengage;
        }

        attempt = Attempt(
            attempt_id=new_id("a"),
            task_id=best_task.task_id,
            worker_id=worker.worker_id,
            worker_name=worker.name,
            status="running",
            started_at=now_ts()
        );
        best_task +>:AttemptedBy:+> attempt;
        attempt +>:ExecutedBy:+> worker;

        best_task.status = "running";
        best_task.attempt_count += 1;
        worker.status = "busy";
        worker.current_task_id = best_task.task_id;
        recompute_job_status(best_job);

        report {
            "task": task_envelope(best_task),
            "attempt_id": attempt.attempt_id,
            "job_id": best_job.job_id,
            "price_per_task": best_task.price_per_task,
            "currency": best_task.currency,
            "sweep": sweep
        };
    }
}

walker submit_result {
    """verify_result -> release_payment -> update_reputation.

    `result_envelope` is the Contract B result envelope produced by the sandbox
    (architecture §5)."""

    has secret: str = "";
    has task_id: str = "";
    has result_envelope: dict = {};

    class __specs__ {
        static has auth: bool = False;
    }

    can submit with `root entry {
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        found = find_task(here, self.task_id);
        if len(found) == 0 {
            report {"error": "unknown_task", "task_id": self.task_id};
            disengage;
        }
        task = found[0];
        job = found[1];
        attempt = running_attempt(task);
        if attempt is None {
            report {"error": "no_running_attempt", "task_id": task.task_id,
                    "task_status": task.status,
                    "detail": "the attempt was already failed or reassigned; result discarded"};
            disengage;
        }
        worker = attempt_worker(attempt);
        envelope = self.result_envelope;
        if not isinstance(envelope, dict) {
            envelope = {};
        }
        status = str(envelope.get("status", "error"));
        output = envelope.get("output", {});
        if not isinstance(output, dict) {
            output = {"value": output};
        }
        execution = envelope.get("execution", {});
        if not isinstance(execution, dict) {
            execution = {};
        }
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

        payment_view = None;
        reputation_view = None;
        outcome = {};

        if ver.outcome == "passed" {
            attempt.status = "complete";
            attempt.finished_at = now;
            task.status = "complete";
            task.reason = "";
            if worker is not None {
                pay = ledger_pay(here, task, job, worker);
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

walker detect_failures {
    """detect_failure + reassign_task sweep. Call periodically, or rely on the
    implicit sweeps inside next_task/heartbeat.

    `dead_after` overrides the 30s default (used by the reassignment demo)."""

    has secret: str = "";
    has dead_after: float = 0.0;

    class __specs__ {
        static has auth: bool = False;
    }

    can sweep with `root entry {
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        threshold = self.dead_after if self.dead_after > 0.0 else DEAD_AFTER;
        report sweep_failures(here, threshold);
    }
}

walker audit_job {
    """Full execution tree: job -> tasks -> attempts -> worker/sandbox/result/
    verification/payment."""

    has secret: str = "";
    has job_id: str = "";

    class __specs__ {
        static has auth: bool = False;
    }

    can walk with `root entry {
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        job = find_job(here, self.job_id);
        if job is None {
            report {"error": "unknown_job", "job_id": self.job_id};
            disengage;
        }
        report audit_tree(job);
    }
}

walker network_status {
    """Dashboard feed: devices, workers, liveness, wallets, jobs."""

    has secret: str = "";

    class __specs__ {
        static has auth: bool = False;
    }

    can survey with `root entry {
        if not auth_ok(self.secret) {
            report unauthorized();
            disengage;
        }
        now = now_ts();
        devices = [];
        for d in all_devices(here) {
            devices.append({
                "device_id": d.device_id,
                "hostname": d.hostname,
                "hardware": d.hardware,
                "owner": d.owner,
                "created_at": iso(d.created_at)
            });
        }
        workers = [];
        for w in all_workers(here) {
            dev = worker_device(w);
            rep = worker_reputation(w);
            wallet = get_or_create_wallet(here, w.worker_id, w.name, 0.0);
            workers.append({
                "worker_id": w.worker_id,
                "name": w.name,
                "device": dev.hostname if dev is not None else "",
                "capabilities": w.capabilities,
                "status": w.status,
                "liveness": liveness(w, now),
                "seconds_since_heartbeat": round(now - w.last_seen, 2),
                "current_task_id": w.current_task_id,
                "wallet": {"wallet_id": wallet.wallet_id, "balance": wallet.balance,
                           "currency": wallet.currency},
                "reputation": {"success": rep.success, "failure": rep.failure, "score": rep.score}
            });
        }
        wallets = [];
        for wl in all_wallets(here) {
            wallets.append({"wallet_id": wl.wallet_id, "owner": wl.owner,
                            "owner_name": wl.owner_name, "balance": wl.balance,
                            "currency": wl.currency});
        }
        jobs = [];
        for j in all_jobs(here) {
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
    if os.environ.get("JACGRID_SELFTEST", "0") == "1" {
        print("[selftest] JacGrid coordinator");
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
        jobs = [root --> (`?Job)];
        job = jobs[len(jobs) - 1];
        workers = [root --> (`?Worker)];
        worker = None;
        for w in workers {
            if w.name == "selftest-worker" {
                worker = w;
            }
        }
        for task in job_tasks(job) {
            root spawn next_task(secret=API_KEY, worker_id=worker.worker_id);
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
        print("[selftest] status=" + status["status"] + " progress=" + str(status["progress"]));
        print("[selftest] receipt=" + canonical(receipt));
        assert status["status"] == "complete", "job did not complete";
        assert receipt["verified"] == 2, "expected 2 verified tasks";
        assert receipt["total_paid"] == 0.2, "expected 0.2 paid";
        audit = audit_tree(job);
        assert len(audit["tasks"]) == 2, "expected 2 tasks in audit";
        print("[selftest] OK");
    }
}
