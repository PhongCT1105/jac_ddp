"""JacGrid coordinator — graph model, globals and helper logic.

The Jac graph IS the system of record: every job, task, attempt, result,
verification and payment is a node. Walkers (see main.jac) are the only
mutators; everything here is either a node/edge declaration or a plain
helper `def` that walkers call.

Architecture reference: docs/architecture.md §3 (graph model), §4 (Contract A),
§5 (Contract B), §7 (verification), §8 (payment).
"""

import os;
import time;
import json;
import math;
import random;
import hashlib;
import from uuid { uuid4 }
import from datetime { datetime, timezone }

::py::
def coordinator_sandbox_run_bridge(task_envelope):
    """Reuse the repo's generic allowlist + sandbox harness from this nested project."""
    import sys
    from importlib import import_module
    from pathlib import Path

    repo_root = str(Path(__file__).resolve().parents[3])
    if repo_root not in sys.path:
        sys.path.insert(0, repo_root)
    harness = import_module("sandbox.runner.harness")
    return harness.sandbox_run(task_envelope)


def coordinator_workload_policy_bridge(job_type):
    """Read immutable verification/runtime policy through the sandbox registry."""
    import sys
    from importlib import import_module
    from pathlib import Path

    repo_root = str(Path(__file__).resolve().parents[3])
    if repo_root not in sys.path:
        sys.path.insert(0, repo_root)
    registry = import_module("sandbox.runner.registry")
    workload = registry.resolve_workload(job_type)
    if workload is None:
        return {
            "ok": False,
            "error": f"no allowlisted workload for job_type={job_type}",
            "runtime_tags": [],
            "verification": {},
        }
    return {
        "ok": True,
        "error": None,
        "workload_id": workload.workload_id,
        "version": workload.version,
        "manifest_sha256": workload.manifest_sha256,
        "package_sha256": workload.package_sha256,
        "runtime_tags": list(workload.runtime_tags),
        "verification": dict(workload.verification),
    }
::py::

# ---------------------------------------------------------------------------
# Globals / configuration
# ---------------------------------------------------------------------------

glob PY_ROUND: any = round;

glob API_KEY: str = os.environ.get("JACGRID_KEY", "jacgrid-dev-key");

# Liveness thresholds are computed from COORDINATOR receive time only
# (docs/phong-distributed/spec.md §5 — never trust worker clocks).
glob SUSPECT_AFTER: float = float(os.environ.get("JACGRID_SUSPECT_AFTER", "15"));
glob DEAD_AFTER: float = float(os.environ.get("JACGRID_DEAD_AFTER", "30"));

glob MAX_ATTEMPTS: int = int(os.environ.get("JACGRID_MAX_ATTEMPTS", "3"));

# How often the background scheduler runs the failure sweep (spec §2.4: 5s).
glob SWEEP_INTERVAL: float = float(os.environ.get("JACGRID_SWEEP_INTERVAL", "5"));

glob DEFAULT_LIMITS: dict = {
    "cpu_seconds": 120,
    "memory_mb": 2048,
    "wall_seconds": 180,
    "network": "none"
};

glob ALLOWED_JOB_TYPES: list = ["embedding", "training_shard", "noop"];
glob EMBEDDING_DIM: int = 384;
glob COORDINATOR_WALLET_SEED: float = 10000.0;
glob DEFAULT_CURRENCY: str = "TESTUSD";

# ---------------------------------------------------------------------------
# Nodes (architecture §3)
# ---------------------------------------------------------------------------

node Device {
    has device_id: str;
    has hostname: str;
    has hardware: dict = {};
    has owner: str = "hackathon";
    has created_at: float = 0.0;
}

node Worker {
    has worker_id: str;
    has name: str;
    has capabilities: dict = {};
    has status: str = "idle";          # idle | busy | dead
    has last_seen: float = 0.0;        # coordinator receive time
    has registered_at: float = 0.0;
    has current_task_id: str = "";
}

node Application {
    has app_id: str;
    has registered_at: float = 0.0;
}

node Job {
    has job_id: str;
    has app_id: str;
    has job_type: str;
    has workload_id: str = "";
    has workload_version: str = "";
    has manifest_sha256: str = "";
    has package_sha256: str = "";
    has workload_runtime_tags: list = [];
    has workload_verification: dict = {};
    has payload: dict = {};
    has partitioning: dict = {};
    has verification: dict = {};
    has budget: dict = {};
    has limits: dict = {};
    has status: str = "queued";        # queued | running | verifying | complete | failed
    has reason: str = "";
    has created_at: float = 0.0;
    has task_count: int = 0;
}

node Task {
    has task_id: str;
    has job_id: str;
    has job_type: str;
    has workload_id: str = "";
    has workload_version: str = "";
    has manifest_sha256: str = "";
    has package_sha256: str = "";
    has workload_runtime_tags: list = [];
    has workload_verification: dict = {};
    has idx: int = 0;
    has payload: dict = {};
    has limits: dict = {};
    has price_per_task: float = 0.0;   # frozen at creation (architecture §8)
    has currency: str = "TESTUSD";
    has status: str = "queued";        # queued | running | complete | failed
    has excluded_workers: list = [];
    has attempt_count: int = 0;
    has reason: str = "";
    has created_at: float = 0.0;
}

node Attempt {
    has attempt_id: str;
    has task_id: str;
    has worker_id: str;
    has worker_name: str = "";
    has status: str = "running";       # running | complete | failed
    has started_at: float = 0.0;
    has finished_at: float = 0.0;
    has reason: str = "";
}

node Sandbox {
    has sandbox_id: str;
    has runtime: str = "unknown";
    has limits: dict = {};
    has execution: dict = {};
}

node Result {
    has result_id: str;
    has task_id: str;
    has status: str = "ok";            # ok | error | timeout | limit_exceeded
    has output: dict = {};
    has execution: dict = {};
    has error: str = "";
    has received_at: float = 0.0;
    has output_hash: str = "";
}

node Verification {
    has verification_id: str;
    has method: str = "none";
    has outcome: str = "passed";       # passed | failed
    has detail: dict = {};
    has checked_at: float = 0.0;
}

node Wallet {
    has wallet_id: str;
    has owner: str;                    # "coordinator" or a worker_id
    has owner_name: str = "";
    has balance: float = 0.0;
    has currency: str = "TESTUSD";
}

node Payment {
    has payment_id: str;
    has task_id: str;
    has job_id: str;
    has worker_id: str;
    has worker_name: str = "";
    has amount: float = 0.0;
    has currency: str = "TESTUSD";
    has tx: str = "";
    has backend: str = "SimulatedLedger";
    has created_at: float = 0.0;
}

node Reputation {
    has worker_id: str;
    has success: int = 0;
    has failure: int = 0;
    has score: float = 1.0;
}

# ---------------------------------------------------------------------------
# Edges (architecture §3)
# ---------------------------------------------------------------------------

edge Submits: Application --> Job {}
edge Contains: Job --> Task {}
edge AttemptedBy: Task --> Attempt {}
edge ExecutedBy: Attempt --> Worker {}
edge HostedOn: Worker --> Device {}
edge RanInside: Attempt --> Sandbox {}
edge Produced: Attempt --> Result {}
edge CheckedBy: Result --> Verification {}
edge SettledBy: Task --> Payment {}
edge PaidTo: Payment --> Wallet {}
edge RatedBy: Worker --> Reputation {}

# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------

"""Coordinator wall-clock. The ONLY time source used for liveness."""
def now_ts() -> float {
    return time.time();
}

def iso(ts: float) -> str {
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ");
}

def new_id(prefix: str) -> str {
    return prefix + "-" + str(uuid4())[0:8];
}

"""Stable JSON serialisation used for hashing and equality checks."""
def canonical(data: any) -> str {
    try {
        return json.dumps(data, sort_keys=True, separators=(",", ":"), default=lambda o: any : str(o));
    } except Exception {
        return str(data);
    }
}

"""Python's two-arg `round`, reached through an `any` alias: the 0.16
checker cannot resolve the two-argument `round` overload (E1054)."""
def round_to(value: float, digits: int) -> float {
    return PY_ROUND(value, digits) as float;
}

def sha256_hex(text: str) -> str {
    return hashlib.sha256(text.encode("utf-8")).hexdigest();
}

def hash_output(output: any) -> str {
    return sha256_hex(canonical(output));
}

def cosine(a: list, b: list) -> float {
    if len(a) != len(b) or len(a) == 0 {
        return 0.0;
    }
    dot = 0.0;
    na = 0.0;
    nb = 0.0;
    for i in range(len(a)) {
        av = float(a[i] as float);
        bv = float(b[i] as float);
        dot += av * bv;
        na += av * av;
        nb += bv * bv;
    }
    if na == 0.0 or nb == 0.0 {
        return 0.0;
    }
    return dot / (math.sqrt(na) * math.sqrt(nb));
}

def as_float(value: any, fallback: float) -> float {
    try {
        return float(value as float);
    } except Exception {
        return fallback;
    }
}

def as_int(value: any, fallback: int) -> int {
    try {
        return int(value as int);
    } except Exception {
        return fallback;
    }
}

# ---------------------------------------------------------------------------
# Graph lookups
# ---------------------------------------------------------------------------

def all_devices(rt: Root) -> list[Device] {
    return [rt -->[?:Device]];
}

def all_workers(rt: Root) -> list[Worker] {
    return [rt -->[?:Worker]];
}

def all_jobs(rt: Root) -> list[Job] {
    return [rt -->[?:Job]];
}

def all_wallets(rt: Root) -> list[Wallet] {
    return [rt -->[?:Wallet]];
}

def job_tasks(job: Job) -> list[Task] {
    tasks = [job ->:Contains:->[?:Task]];
    ordered = [];
    for t in tasks {
        ordered.append(t);
    }
    n = len(ordered);
    i = 0;
    while i < n {
        j = 0;
        while j < n - 1 - i {
            if ordered[j].idx > ordered[j + 1].idx {
                tmp = ordered[j];
                ordered[j] = ordered[j + 1];
                ordered[j + 1] = tmp;
            }
            j += 1;
        }
        i += 1;
    }
    return ordered;
}

def task_attempts(task: Task) -> list[Attempt] {
    attempts = [task ->:AttemptedBy:->[?:Attempt]];
    ordered = [];
    for a in attempts {
        ordered.append(a);
    }
    n = len(ordered);
    i = 0;
    while i < n {
        j = 0;
        while j < n - 1 - i {
            if ordered[j].started_at > ordered[j + 1].started_at {
                tmp = ordered[j];
                ordered[j] = ordered[j + 1];
                ordered[j + 1] = tmp;
            }
            j += 1;
        }
        i += 1;
    }
    return ordered;
}

def find_device(rt: Root, hostname: str) -> Device | None {
    for d in all_devices(rt) {
        if d.hostname == hostname {
            return d;
        }
    }
    return None;
}

def find_worker(rt: Root, worker_id: str) -> Worker | None {
    for w in all_workers(rt) {
        if w.worker_id == worker_id or w.name == worker_id {
            return w;
        }
    }
    return None;
}

def find_app(rt: Root, app_id: str) -> Application | None {
    for a in [rt -->[?:Application]] {
        if a.app_id == app_id {
            return a;
        }
    }
    return None;
}

def find_job(rt: Root, job_id: str) -> Job | None {
    for j in all_jobs(rt) {
        if j.job_id == job_id {
            return j;
        }
    }
    return None;
}

"""Returns [task, job] or [] when unknown."""
def find_task(rt: Root, task_id: str) -> list {
    for j in all_jobs(rt) {
        for t in job_tasks(j) {
            if t.task_id == task_id {
                return [t, j];
            }
        }
    }
    return [];
}

def running_attempt(task: Task) -> Attempt | None {
    latest = None;
    for a in task_attempts(task) {
        if a.status == "running" {
            latest = a;
        }
    }
    return latest;
}

def attempt_worker(attempt: Attempt) -> Worker | None {
    workers = [attempt ->:ExecutedBy:->[?:Worker]];
    if len(workers) > 0 {
        return workers[0];
    }
    return None;
}

def attempt_result(attempt: Attempt) -> Result | None {
    results = [attempt ->:Produced:->[?:Result]];
    if len(results) > 0 {
        return results[0];
    }
    return None;
}

def result_verification(result: Result) -> Verification | None {
    checks = [result ->:CheckedBy:->[?:Verification]];
    if len(checks) > 0 {
        return checks[0];
    }
    return None;
}

def task_payment(task: Task) -> Payment | None {
    payments = [task ->:SettledBy:->[?:Payment]];
    if len(payments) > 0 {
        return payments[0];
    }
    return None;
}

def worker_device(worker: Worker) -> Device | None {
    devices = [worker ->:HostedOn:->[?:Device]];
    if len(devices) > 0 {
        return devices[0];
    }
    return None;
}

def worker_reputation(worker: Worker) -> Reputation {
    reps = [worker ->:RatedBy:->[?:Reputation]];
    if len(reps) > 0 {
        return reps[0];
    }
    rep = Reputation(worker_id=worker.worker_id);
    worker +>:RatedBy:+> rep;
    return rep;
}

def liveness(worker: Worker, now: float) -> str {
    delta = now - worker.last_seen;
    if delta > DEAD_AFTER {
        return "dead";
    }
    if delta > SUSPECT_AFTER {
        return "suspect";
    }
    return "alive";
}

# ---------------------------------------------------------------------------
# Wallet / payment backend — v1 SimulatedLedger (spec §2.6)
# ---------------------------------------------------------------------------

def get_or_create_wallet(rt: Root, owner: str, owner_name: str, seed: float) -> Wallet {
    for w in all_wallets(rt) {
        if w.owner == owner {
            return w;
        }
    }
    wallet = Wallet(
        wallet_id=new_id("wallet"),
        owner=owner,
        owner_name=owner_name,
        balance=seed,
        currency=DEFAULT_CURRENCY
    );
    rt ++> wallet;
    return wallet;
}

def coordinator_wallet(rt: Root) -> Wallet {
    return get_or_create_wallet(rt, "coordinator", "coordinator", COORDINATOR_WALLET_SEED);
}

"""PaymentBackend.pay(from_wallet, to_wallet, amount) -> Payment node.

v1 backend is the SimulatedLedger: balances live in the graph, tx id is a
uuid. Swapping in a testnet backend only changes the body of this def.
"""
def ledger_pay(rt: Root, task: Task, job: Job, worker: Worker) -> Payment {
    src = coordinator_wallet(rt);
    dst = get_or_create_wallet(rt, worker.worker_id, worker.name, 0.0);
    amount = task.price_per_task;
    src.balance = round_to(src.balance - amount, 6);
    dst.balance = round_to(dst.balance + amount, 6);
    payment = Payment(
        payment_id=new_id("pay"),
        task_id=task.task_id,
        job_id=job.job_id,
        worker_id=worker.worker_id,
        worker_name=worker.name,
        amount=amount,
        currency=task.currency,
        tx="0x" + str(uuid4()).replace("-", ""),
        backend="SimulatedLedger",
        created_at=now_ts()
    );
    rt ++> payment;
    task +>:SettledBy:+> payment;
    payment +>:PaidTo:+> dst;
    return payment;
}

def bump_reputation(worker: Worker, ok: bool) -> dict {
    rep = worker_reputation(worker);
    if ok {
        rep.success += 1;
    } else {
        rep.failure += 1;
    }
    total = rep.success + rep.failure;
    if total > 0 {
        rep.score = round_to(float(rep.success) / float(total), 4);
    }
    return {"worker_id": rep.worker_id, "success": rep.success, "failure": rep.failure, "score": rep.score};
}

# ---------------------------------------------------------------------------
# Verification (architecture §7, spec §2.5)
# ---------------------------------------------------------------------------

"""Deterministic sample of at least one item."""
def sample_items(items: list, sample_rate: float, seed: str) -> list {
    if len(items) == 0 {
        return [];
    }
    count = int(math.ceil(sample_rate * float(len(items))));
    if count < 1 {
        count = 1;
    }
    if count > len(items) {
        count = len(items);
    }
    rng = random.Random(seed);
    idxs = list(range(len(items)));
    rng.shuffle(idxs);
    picked = [];
    for i in idxs[0:count] {
        picked.append(items[i]);
    }
    return picked;
}

def index_results(output: dict) -> dict {
    by_id = {};
    for row in output.get("results", []) as list {
        if isinstance(row, dict) and "id" in row {
            by_id[str(row["id"])] = row;
        }
    }
    return by_id;
}

"""Recompute sampled items through the exact same allowlist + sandbox path.

Returns the full Contract B result envelope so verification can enforce both
numeric agreement and the actual primary-vs-fallback runtime provenance.
"""
def pinned_workload_view(task: Task) -> dict {
    return {
        "id": task.workload_id,
        "version": task.workload_version,
        "manifest_sha256": task.manifest_sha256,
        "package_sha256": task.package_sha256,
        "runtime_tags": task.workload_runtime_tags,
        "verification": task.workload_verification,
    };
}


def recompute_embedding_items(task: Task, items: list) -> dict {
    envelope: dict[str, any] = {
        "task_id": "verify-" + uuid4().hex,
        "job_type": "embedding",
        "payload": {"model": str(task.payload.get("model", "")), "items": items},
        "workload": pinned_workload_view(task),
    };
    return coordinator_sandbox_run_bridge(envelope) as dict;  # jac:ignore[W2001, W1051] -- narrow inline-Python bridge
}


"""Immutable manifest policy selected through the generic allowlist registry."""
def workload_snapshot(job_type: str) -> dict {
    return coordinator_workload_policy_bridge(job_type) as dict;  # jac:ignore[W2001, W1051] -- narrow inline-Python bridge
}


"""Fail-closed validation for the implemented verification methods."""
def validate_verification_spec(job_type: str, spec: dict) -> dict {
    method = str(spec.get("method", ""));
    if job_type == "embedding" {
        if method == "recompute_sample" {
            return {"ok": True, "detail": ""};
        }
        return {"ok": False,
                "detail": "embedding jobs require verification.method=recompute_sample"};
    }
    if job_type == "noop" and method == "recompute_sample" {
        return {"ok": True, "detail": ""};
    }
    if method == "output_hash" {
        expected = spec.get("expected_hash", None);
        expected_many = spec.get("expected_hashes", None);
        has_one = isinstance(expected, str) and str(expected) != "";
        has_many = isinstance(expected_many, dict) and len(expected_many as dict) > 0;
        if has_one or has_many {
            return {"ok": True, "detail": ""};
        }
        return {"ok": False,
                "detail": "output_hash requires expected_hash or non-empty expected_hashes"};
    }
    return {"ok": False,
            "detail": "verification method is unknown or not implemented: " + method};
}

"""recompute_sample for `noop`: recomputing an echo IS the echo."""
def verify_noop(task: Task, result: Result, spec: dict) -> dict {
    items = task.payload.get("items", []) as list;
    by_id = index_results(result.output);
    rate = as_float(spec.get("sample_rate", 0.1), 0.1);
    picked = sample_items(items, rate, task.task_id);
    mismatches = [];
    for item in picked {
        key = str(item.get("id", ""));
        actual = by_id.get(key, None);
        if actual is None {
            mismatches.append({"id": key, "reason": "missing_from_output"});
        } elif canonical(actual) != canonical(item) {
            mismatches.append({"id": key, "reason": "echo_mismatch",
                               "expected": item, "actual": actual});
        }
    }
    missing = [];
    for item in items {
        if str(item.get("id", "")) not in by_id {
            missing.append(str(item.get("id", "")));
        }
    }
    ok = len(mismatches) == 0 and len(missing) == 0;
    return {
        "ok": ok,
        "detail": {
            "method": "recompute_sample",
            "job_type": "noop",
            "items": len(items),
            "sampled": len(picked),
            "recompute": True,
            "mismatches": mismatches,
            "missing_ids": missing
        }
    };
}

def verify_embedding(task: Task, result: Result, spec: dict) -> dict {
    items = task.payload.get("items", []) as list;
    by_id = index_results(result.output);
    rate = as_float(spec.get("sample_rate", 0.1), 0.1);
    dim = as_int(task.payload.get("dim", EMBEDDING_DIM), EMBEDDING_DIM);
    picked = sample_items(items, rate, task.task_id);
    tolerance = as_float(task.workload_verification.get("tolerance", 0.001), 0.001);
    cosine_threshold = 1.0 - tolerance;
    allowed_runtime_tags = task.workload_runtime_tags;
    structure_problems = [];
    missing = [];
    for item in items {
        key = str(item.get("id", ""));
        row = by_id.get(key, None);
        if row is None {
            structure_problems.append({"id": key, "reason": "missing_from_output"});
            missing.append(key);
            continue;
        }
        vec = row.get("embedding", None);
        if not isinstance(vec, list) {
            structure_problems.append({"id": key, "reason": "embedding_not_a_list"});
            continue;
        }
        if len(vec) != dim {
            structure_problems.append({"id": key, "reason": "bad_dimension",
                                       "expected": dim, "actual": len(vec)});
            continue;
        }
        for value in vec {
            if isinstance(value, bool) or (
                not isinstance(value, int) and not isinstance(value, float)
            ) {
                structure_problems.append({"id": key,
                                           "reason": "embedding_non_numeric"});
                break;
            }
        }
    }

    problems = list(structure_problems);

    recomputed = recompute_embedding_items(task, picked);
    recompute_status = str(recomputed.get("status", "error"));
    recompute_error = recomputed.get("error", None);
    recompute_execution_raw = recomputed.get("execution", None);
    recompute_execution: dict = {};
    if isinstance(recompute_execution_raw, dict) {
        recompute_execution = recompute_execution_raw as dict;
    } else {
        problems.append({"reason": "recompute_missing_execution"});
    }
    original_runtime = str(result.execution.get("runtime", ""));
    recompute_runtime = str(recompute_execution.get("runtime", ""));

    if recompute_status != "ok" {
        problems.append({"reason": "recompute_error",
                         "status": recompute_status,
                         "error": recompute_error});
    }
    if original_runtime not in allowed_runtime_tags {
        problems.append({"reason": "original_runtime_unapproved",
                         "runtime": original_runtime,
                         "allowed": allowed_runtime_tags});
    }
    if original_runtime != recompute_runtime {
        problems.append({"reason": "runtime_mismatch",
                         "original_runtime": original_runtime,
                         "recompute_runtime": recompute_runtime});
    }

    recompute_output_raw = recomputed.get("output", None);
    recompute_output: dict = {};
    if recompute_status == "ok" and isinstance(recompute_output_raw, dict) {
        recompute_output = recompute_output_raw as dict;
    } elif recompute_status == "ok" {
        problems.append({"reason": "recompute_output_not_an_object"});
    }
    expected_by_id = index_results(recompute_output);
    compared = 0;
    for item in picked {
        key = str(item.get("id", ""));
        expected_row = expected_by_id.get(key, None);
        if expected_row is None {
            problems.append({"id": key, "reason": "missing_from_recompute"});
            continue;
        }
        want_raw = expected_row.get("embedding", None);
        if not isinstance(want_raw, list) {
            problems.append({"id": key, "reason": "recomputed_embedding_not_a_list"});
            continue;
        }
        want = want_raw as list;
        if len(want) != dim {
            problems.append({"id": key, "reason": "recomputed_bad_dimension",
                             "expected": dim, "actual": len(want)});
            continue;
        }
        recomputed_numeric = True;
        for value in want {
            if isinstance(value, bool) or (
                not isinstance(value, int) and not isinstance(value, float)
            ) {
                recomputed_numeric = False;
                break;
            }
        }
        if not recomputed_numeric {
            problems.append({"id": key, "reason": "recomputed_embedding_non_numeric"});
            continue;
        }
        got_row = by_id.get(key, None);
        if got_row is None {
            continue;
        }
        got_raw = got_row.get("embedding", None);
        if not isinstance(got_raw, list) or len(got_raw as list) != dim {
            continue;
        }
        numeric = True;
        for value in got_raw as list {
            if isinstance(value, bool) or (
                not isinstance(value, int) and not isinstance(value, float)
            ) {
                numeric = False;
                break;
            }
        }
        if not numeric {
            continue;
        }
        sim = cosine(got_raw as list, want);
        compared += 1;
        if sim < cosine_threshold {
            problems.append({"id": key, "reason": "cosine_below_tolerance",
                             "cosine": sim, "threshold": cosine_threshold});
        }
    }
    ok = (len(picked) > 0 and compared == len(picked)
          and len(problems) == 0 and len(missing) == 0);
    return {
        "ok": ok,
        "detail": {
            "method": "recompute_sample",
            "job_type": "embedding",
            "items": len(items),
            "sampled": len(picked),
            "dim": dim,
            "recompute": True,
            "recomputed_compared": compared,
            "structure_valid": len(structure_problems) == 0 and len(missing) == 0,
            "original_runtime": original_runtime,
            "recompute_runtime": recompute_runtime,
            "recompute_status": recompute_status,
            "recompute_error": recompute_error,
            "tolerance": tolerance,
            "cosine_threshold": cosine_threshold,
            "problems": problems,
            "missing_ids": missing
        }
    };
}

def verify_output_hash(task: Task, result: Result, spec: dict) -> dict {
    computed = result.output_hash;
    expected = spec.get("expected_hash", "");
    per_task = spec.get("expected_hashes", {});
    if isinstance(per_task, dict) {
        if task.task_id in per_task {
            expected = per_task[task.task_id];
        } elif str(task.idx) in per_task {
            expected = per_task[str(task.idx)];
        }
    }
    if expected == "" or expected is None {
        return {
            "ok": False,
            "detail": {"method": "output_hash", "computed_hash": computed,
                       "expected_hash": None,
                       "reason": "missing expected hash"}
        };
    }
    ok = str(expected) == computed;
    return {
        "ok": ok,
        "detail": {"method": "output_hash", "computed_hash": computed,
                   "expected_hash": str(expected), "match": ok}
    };
}

def verify_structure(task: Task, result: Result, spec: dict) -> dict {
    items = task.payload.get("items", []) as list;
    by_id = index_results(result.output);
    missing = [];
    for item in items {
        if str(item.get("id", "")) not in by_id {
            missing.append(str(item.get("id", "")));
        }
    }
    return {
        "ok": False,
        "detail": {"method": str(spec.get("method", "none")),
                   "reason": "verification method is unknown or not implemented",
                   "items": len(items), "missing_ids": missing,
                   "fail_closed": True}
    };
}

"""Creates and links a Verification node for a Result."""
def run_verification(job: Job, task: Task, result: Result) -> Verification {
    spec = job.verification;
    if not isinstance(spec, dict) {
        spec = {};
    }
    method = str(spec.get("method", "recompute_sample"));
    outcome = {"ok": False, "detail": {}};
    if result.status != "ok" {
        outcome = {"ok": False,
                   "detail": {"method": method, "reason": "worker reported status=" + result.status,
                              "error": result.error}};
    } elif task.job_type == "embedding" and method != "recompute_sample" {
        outcome = {"ok": False,
                   "detail": {"method": method,
                              "reason": "embedding jobs require recompute_sample",
                              "fail_closed": True}};
    } elif method == "output_hash" {
        outcome = verify_output_hash(task, result, spec);
    } elif method == "recompute_sample" {
        if task.job_type == "noop" {
            outcome = verify_noop(task, result, spec);
        } elif task.job_type == "embedding" {
            outcome = verify_embedding(task, result, spec);
        } else {
            outcome = verify_structure(task, result, spec);
        }
    } else {
        outcome = verify_structure(task, result, spec);
    }
    ver = Verification(
        verification_id=new_id("ver"),
        method=method,
        outcome="passed" if outcome["ok"] else "failed",
        detail=outcome["detail"] as dict,
        checked_at=now_ts()
    );
    result +>:CheckedBy:+> ver;
    return ver;
}

# ---------------------------------------------------------------------------
# Job / task state machine
# ---------------------------------------------------------------------------

def recompute_job_status(job: Job) -> str {
    tasks = job_tasks(job);
    if len(tasks) == 0 {
        return job.status;
    }
    complete = 0;
    failed = 0;
    started = 0;
    for t in tasks {
        if t.status == "complete" {
            complete += 1;
        } elif t.status == "failed" {
            failed += 1;
        }
        if t.attempt_count > 0 {
            started += 1;
        }
    }
    if failed > 0 {
        job.status = "failed";
        if job.reason == "" {
            job.reason = "at least one task exhausted its attempts";
        }
    } elif complete == len(tasks) {
        job.status = "complete";
    } elif started > 0 {
        job.status = "running";
    } else {
        job.status = "queued";
    }
    return job.status;
}

def job_progress(job: Job) -> float {
    tasks = job_tasks(job);
    if len(tasks) == 0 {
        return 0.0;
    }
    done = 0;
    for t in tasks {
        if t.status == "complete" {
            done += 1;
        }
    }
    return round_to(float(done) / float(len(tasks)), 4);
}

"""reassign_task: re-enter the task into scheduling, excluding the worker.

Max MAX_ATTEMPTS attempts; after that the task — and the job — fail.
"""
def requeue_task(job: Job, task: Task, worker_id: str, reason: str) -> dict {
    if worker_id != "" and worker_id not in task.excluded_workers {
        task.excluded_workers.append(worker_id);
    }
    task.reason = reason;
    if task.attempt_count >= MAX_ATTEMPTS {
        task.status = "failed";
        job.status = "failed";
        job.reason = "task " + task.task_id + " failed after " + str(task.attempt_count) + " attempts: " + reason;
        recompute_job_status(job);
        return {"task_id": task.task_id, "action": "failed", "reason": job.reason,
                "attempts": task.attempt_count};
    }
    task.status = "queued";
    recompute_job_status(job);
    return {"task_id": task.task_id, "action": "requeued", "reason": reason,
            "attempts": task.attempt_count, "excluded_workers": task.excluded_workers};
}

def fail_attempt(job: Job, task: Task, attempt: Attempt, reason: str) -> dict {
    attempt.status = "failed";
    attempt.reason = reason;
    attempt.finished_at = now_ts();
    worker = attempt_worker(attempt);
    wid = attempt.worker_id;
    if worker is not None {
        if worker.current_task_id == task.task_id {
            worker.current_task_id = "";
            if worker.status == "busy" {
                worker.status = "idle";
            }
        }
        bump_reputation(worker, False);
    }
    return requeue_task(job, task, wid, reason);
}

"""detect_failure + reassign_task, spec §2.4.

Marks silent workers dead, fails their running attempts, fails attempts that
blew past wall_seconds + 60s, and re-queues the affected tasks. Safe and
cheap to call on every request — that is exactly what next_task/heartbeat do
so the network self-heals without a cron job.
"""
def sweep_failures(rt: Root, dead_after: float) -> dict {
    now = now_ts();
    dead_workers = [];
    suspect_workers = [];
    for w in all_workers(rt) {
        state = "alive";
        delta = now - w.last_seen;
        if delta > dead_after {
            state = "dead";
        } elif delta > SUSPECT_AFTER {
            state = "suspect";
        }
        if state == "dead" {
            if w.status != "dead" {
                w.status = "dead";
            }
            dead_workers.append(w.worker_id);
        } else {
            if state == "suspect" {
                suspect_workers.append(w.worker_id);
            }
            if w.status == "dead" {
                w.status = "idle" if w.current_task_id == "" else "busy";
            }
        }
    }
    reassigned = [];
    for job in all_jobs(rt) {
        if job.status == "complete" or job.status == "failed" {
            continue;
        }
        for task in job_tasks(job) {
            if task.status != "running" {
                continue;
            }
            attempt = running_attempt(task);
            if attempt is None {
                # running task with no live attempt — recover it
                reassigned.append(requeue_task(job, task, "", "orphaned task (no running attempt)"));
                continue;
            }
            wall = as_float(task.limits.get("wall_seconds", DEFAULT_LIMITS["wall_seconds"]), 180.0);
            if attempt.worker_id in dead_workers {
                reassigned.append(fail_attempt(job, task, attempt,
                    "worker " + attempt.worker_name + " silent for more than " + str(int(dead_after)) + "s"));
            } elif now - attempt.started_at > wall + 60.0 {
                reassigned.append(fail_attempt(job, task, attempt,
                    "attempt exceeded wall_seconds+60 (" + str(int(wall + 60.0)) + "s)"));
            }
        }
        recompute_job_status(job);
    }
    return {
        "checked_at": now,
        "dead_workers": dead_workers,
        "suspect_workers": suspect_workers,
        "reassigned": reassigned
    };
}

# ---------------------------------------------------------------------------
# Contract B envelopes (architecture §5)
# ---------------------------------------------------------------------------

"""Task envelope handed to the worker, and by the worker to the sandbox."""
def task_envelope(task: Task) -> dict {
    return {
        "task_id": task.task_id,
        "job_type": task.job_type,
        "payload": task.payload,
        "limits": task.limits,
        "workload": pinned_workload_view(task)
    };
}

"""Fields architecture.md §5 declares mandatory inside `execution`."""
glob REQUIRED_EXECUTION_FIELDS: list = [
    "runtime", "started_at", "finished_at", "peak_memory_mb", "cpu_seconds", "exit_code"
];

glob REQUIRED_ENVELOPE_FIELDS: list = ["status", "output", "execution"];

glob ALLOWED_RESULT_STATUS: list = ["ok", "error", "timeout", "limit_exceeded"];

"""Validate a Contract B result envelope before it is allowed into the graph.

architecture.md §5: "The `execution` block is mandatory — it feeds the Sandbox
and Attempt nodes in the Jac graph and the audit timeline." A submission that
omits it, or ships it malformed, is a PROTOCOL VIOLATION, not a failed task:
we cannot audit or bill an execution we have no metadata for. The caller
rejects such a submission without touching the Attempt, so the task stays
`running` and the normal timeout/dead-worker path can reassign it.

Returns {"ok": bool, "detail": {...}}.
"""
def validate_result_envelope(envelope: any) -> dict {
    if not isinstance(envelope, dict) {
        return {"ok": False, "detail": {"reason": "result_envelope must be an object",
                                        "actual_type": type(envelope).__name__}};
    }
    env = envelope as dict;
    missing_top = [];
    for key in REQUIRED_ENVELOPE_FIELDS {
        if key not in env {
            missing_top.append(key);
        }
    }
    if len(missing_top) > 0 {
        return {"ok": False,
                "detail": {"reason": "result envelope is missing mandatory fields",
                           "missing": missing_top,
                           "required": REQUIRED_ENVELOPE_FIELDS}};
    }
    status = env["status"];
    if not isinstance(status, str) or str(status) not in ALLOWED_RESULT_STATUS {
        return {"ok": False,
                "detail": {"reason": "status must be one of the Contract B values",
                           "actual": status, "allowed": ALLOWED_RESULT_STATUS}};
    }
    output = env["output"];
    if str(status) == "ok" and not isinstance(output, dict) {
        return {"ok": False,
                "detail": {"reason": "output must be an object when status=ok",
                           "actual_type": type(output).__name__}};
    }
    if str(status) != "ok" and output is not None and not isinstance(output, dict) {
        return {"ok": False,
                "detail": {"reason": "output must be null or an object for failure statuses",
                           "actual_type": type(output).__name__}};
    }
    execution = env["execution"];
    if not isinstance(execution, dict) {
        return {"ok": False,
                "detail": {"reason": "the execution block is mandatory and must be an object",
                           "actual_type": type(execution).__name__,
                           "required_fields": REQUIRED_EXECUTION_FIELDS}};
    }
    exec_dict = execution as dict;
    missing_exec = [];
    for key in REQUIRED_EXECUTION_FIELDS {
        if key not in exec_dict {
            missing_exec.append(key);
        }
    }
    if len(missing_exec) > 0 {
        return {"ok": False,
                "detail": {"reason": "the execution block is missing mandatory fields",
                           "missing": missing_exec,
                           "required_fields": REQUIRED_EXECUTION_FIELDS}};
    }
    if not isinstance(exec_dict["runtime"], str) or str(exec_dict["runtime"]) == "" {
        return {"ok": False,
                "detail": {"reason": "execution.runtime must be a non-empty string",
                           "actual": exec_dict["runtime"]}};
    }
    for key in ["started_at", "finished_at"] {
        value = exec_dict[key];
        if not isinstance(value, str) or str(value) == "" {
            return {"ok": False,
                    "detail": {"reason": "execution." + key + " must be a non-empty string",
                               "actual": value}};
        }
    }
    for key in ["peak_memory_mb", "cpu_seconds"] {
        value = exec_dict[key];
        numeric = (not isinstance(value, bool)
                   and (isinstance(value, int) or isinstance(value, float)));
        if not numeric or (value as float) < 0.0 {
            return {"ok": False,
                    "detail": {"reason": "execution." + key
                                         + " must be a nonnegative number (bool is invalid)",
                               "actual": value}};
        }
    }
    exit_code = exec_dict["exit_code"];
    if isinstance(exit_code, bool) or not isinstance(exit_code, int) {
        return {"ok": False,
                "detail": {"reason": "execution.exit_code must be an integer (bool is invalid)",
                           "actual": exit_code}};
    }
    return {"ok": True, "detail": {"execution_fields": REQUIRED_EXECUTION_FIELDS}};
}

# ---------------------------------------------------------------------------
# Contract A views (architecture §4)
# ---------------------------------------------------------------------------

def task_status_view(task: Task) -> dict {
    worker_name = "";
    attempts = task_attempts(task);
    if len(attempts) > 0 {
        worker_name = attempts[len(attempts) - 1].worker_name;
    }
    payment = task_payment(task);
    return {
        "task_id": task.task_id,
        "status": task.status,
        "worker": worker_name,
        "paid": payment is not None
    };
}

def job_status_view(job: Job) -> dict {
    recompute_job_status(job);
    tasks = [];
    for t in job_tasks(job) {
        tasks.append(task_status_view(t));
    }
    view = {
        "job_id": job.job_id,
        "status": job.status,
        "tasks": tasks,
        "progress": job_progress(job)
    };
    if job.reason != "" {
        view["reason"] = job.reason;
    }
    return view;
}

def merged_results(job: Job) -> list {
    out = [];
    for task in job_tasks(job) {
        for attempt in task_attempts(task) {
            if attempt.status != "complete" {
                continue;
            }
            res = attempt_result(attempt);
            if res is None {
                continue;
            }
            rows = res.output.get("results", None);
            if isinstance(rows, list) {
                for row in rows {
                    out.append(row);
                }
            } else {
                out.append({"task_id": task.task_id, "output": res.output});
            }
        }
    }
    return out;
}

def job_receipt(job: Job) -> dict {
    tasks = job_tasks(job);
    verified = 0;
    total_paid = 0.0;
    payments = [];
    for task in tasks {
        for attempt in task_attempts(task) {
            res = attempt_result(attempt);
            if res is None {
                continue;
            }
            ver = result_verification(res);
            if ver is not None and ver.outcome == "passed" {
                verified += 1;
            }
        }
        pay = task_payment(task);
        if pay is not None {
            total_paid += pay.amount;
            payments.append({
                "task_id": pay.task_id,
                "worker": pay.worker_name,
                "amount": pay.amount,
                "tx": pay.tx
            });
        }
    }
    return {
        "tasks": len(tasks),
        "verified": verified,
        "total_paid": round_to(total_paid, 6),
        "currency": DEFAULT_CURRENCY,
        "payments": payments
    };
}

def audit_tree(job: Job) -> dict {
    tasks = [];
    for task in job_tasks(job) {
        attempts = [];
        for attempt in task_attempts(task) {
            res = attempt_result(attempt);
            sandboxes = [attempt ->:RanInside:->[?:Sandbox]];
            sandbox_view = None;
            if len(sandboxes) > 0 {
                sandbox_view = {
                    "sandbox_id": sandboxes[0].sandbox_id,
                    "runtime": sandboxes[0].runtime,
                    "limits": sandboxes[0].limits,
                    "execution": sandboxes[0].execution
                };
            }
            result_view = None;
            verification_view = None;
            if res is not None {
                result_view = {
                    "result_id": res.result_id,
                    "status": res.status,
                    "output_hash": res.output_hash,
                    "error": res.error,
                    "received_at": iso(res.received_at),
                    "execution": res.execution
                };
                ver = result_verification(res);
                if ver is not None {
                    verification_view = {
                        "verification_id": ver.verification_id,
                        "method": ver.method,
                        "outcome": ver.outcome,
                        "checked_at": iso(ver.checked_at),
                        "detail": ver.detail
                    };
                }
            }
            attempts.append({
                "attempt_id": attempt.attempt_id,
                "status": attempt.status,
                "reason": attempt.reason,
                "started_at": iso(attempt.started_at),
                "finished_at": iso(attempt.finished_at) if attempt.finished_at > 0.0 else None,
                "worker": {"worker_id": attempt.worker_id, "name": attempt.worker_name},
                "sandbox": sandbox_view,
                "result": result_view,
                "verification": verification_view
            });
        }
        pay = task_payment(task);
        payment_view = None;
        if pay is not None {
            payment_view = {
                "payment_id": pay.payment_id,
                "worker": pay.worker_name,
                "amount": pay.amount,
                "currency": pay.currency,
                "tx": pay.tx,
                "backend": pay.backend,
                "created_at": iso(pay.created_at)
            };
        }
        tasks.append({
            "task_id": task.task_id,
            "idx": task.idx,
            "status": task.status,
            "job_type": task.job_type,
            "price_per_task": task.price_per_task,
            "attempt_count": task.attempt_count,
            "excluded_workers": task.excluded_workers,
            "reason": task.reason,
            "items": len(task.payload.get("items", []) as list),
            "attempts": attempts,
            "payment": payment_view
        });
    }
    recompute_job_status(job);
    return {
        "job_id": job.job_id,
        "app_id": job.app_id,
        "job_type": job.job_type,
        "status": job.status,
        "reason": job.reason,
        "created_at": iso(job.created_at),
        "partitioning": job.partitioning,
        "verification": job.verification,
        "budget": job.budget,
        "limits": job.limits,
        "progress": job_progress(job),
        "tasks": tasks,
        "receipt": job_receipt(job)
    };
}

# ---------------------------------------------------------------------------
# Partitioning (split_job)
# ---------------------------------------------------------------------------

"""Split a job payload into per-task payload slices."""
def chunk_payload(payload: dict, partitioning: dict) -> list {
    items = payload.get("items", None);
    strategy = str(partitioning.get("strategy", "chunk"));
    if not isinstance(items, list) or len(items) == 0 or strategy != "chunk" {
        return [payload];
    }
    size = as_int(partitioning.get("chunk_size", 25), 25);
    if size < 1 {
        size = 1;
    }
    slices = [];
    i = 0;
    while i < len(items) {
        slice_payload = {};
        for key in payload.keys() {
            if key != "items" {
                slice_payload[key] = payload[key];
            }
        }
        slice_payload["items"] = items[i:i + size];
        slices.append(slice_payload);
        i += size;
    }
    return slices;
}
