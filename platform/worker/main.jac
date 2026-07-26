"""JacGrid worker runtime.

This is its own Jac project (`platform/worker/jac.toml`). From that dir:

    jac run main.jac                                 # join the grid
    JACGRID_WORKER_SELFTEST=1 jac run main.jac       # offline runner self-test

Registers with the coordinator, then loops: heartbeat every 5s, pull work when
idle, execute it, post the Contract B result envelope back.

Configuration (environment variables):

    JACGRID_COORDINATOR   default http://127.0.0.1:8000
    JACGRID_KEY           default jacgrid-dev-key   (shared secret)
    WORKER_NAME           default <hostname>        (worker identity)
    WORKER_JOB_TYPES      default noop,embedding    (comma separated)
    JACGRID_HEARTBEAT     default 5                 (seconds)
    JACGRID_POLL          default 1                 (seconds between pulls)
    JACGRID_MAX_LOOPS     default 0 = forever       (used by tests)
    JACGRID_EXIT_WHEN_IDLE default 0                (1 = stop after N idle polls)
    JACGRID_IDLE_LIMIT    default 30                (idle polls before exit)
    JACGRID_SANDBOX       default 0                 (set 1 for the demo)
    JACGRID_TASK_DELAY    default 0                 (fake work seconds, demo only)

The execution of a task is isolated behind ONE call — `run_task(envelope)`.
With JACGRID_SANDBOX=1 (the documented demo setting), it hands the envelope to
the sandbox (`sandbox/`) and returns that result envelope unchanged. When the
flag is unset or 0, it keeps using the local stub runner.
"""

import os;
import sys;
import time;
import json;
import socket;
import hashlib;
import requests;
import from datetime { datetime, timezone }

def coordinator_http_session() -> any {
    session = requests.Session();
    session.trust_env = False;
    return session;
}

::py::
def sandbox_run_bridge(task_envelope):
    """Import the repo-root sandbox from the worker's nested Jac project."""
    import sys
    from importlib import import_module
    from pathlib import Path

    repo_root = str(Path(__file__).resolve().parents[2])
    if repo_root not in sys.path:
        sys.path.insert(0, repo_root)
    harness = import_module("sandbox.runner.harness")
    return harness.sandbox_run(task_envelope)


def sandbox_workload_identity_bridge(job_type):
    """Resolve the immutable workload identity used by coordinator envelopes."""
    import sys
    from importlib import import_module
    from pathlib import Path

    repo_root = str(Path(__file__).resolve().parents[2])
    if repo_root not in sys.path:
        sys.path.insert(0, repo_root)
    workload = import_module("sandbox.runner.registry").resolve_workload(job_type)
    if workload is None:
        return None
    return {
        "id": workload.workload_id,
        "version": workload.version,
        "manifest_sha256": workload.manifest_sha256,
        "package_sha256": workload.package_sha256,
        "runtime_tags": list(workload.runtime_tags),
        "verification": dict(workload.verification),
    }
::py::

glob COORDINATOR: str = os.environ.get("JACGRID_COORDINATOR", "http://127.0.0.1:8000");
glob SECRET: str = os.environ.get("JACGRID_KEY", "jacgrid-dev-key");
glob WORKER_NAME: str = os.environ.get("WORKER_NAME", socket.gethostname());
glob HEARTBEAT_SECONDS: float = float(os.environ.get("JACGRID_HEARTBEAT", "5"));
glob POLL_SECONDS: float = float(os.environ.get("JACGRID_POLL", "1"));
glob MAX_LOOPS: int = int(os.environ.get("JACGRID_MAX_LOOPS", "0"));
glob EXIT_WHEN_IDLE: bool = os.environ.get("JACGRID_EXIT_WHEN_IDLE", "0") == "1";
glob IDLE_LIMIT: int = int(os.environ.get("JACGRID_IDLE_LIMIT", "30"));
glob HTTP_TIMEOUT: float = float(os.environ.get("JACGRID_HTTP_TIMEOUT", "30"));
glob COORDINATOR_HTTP: any = coordinator_http_session();
glob STUB_RUNTIME: str = "stub-runner:v0";
glob SANDBOX_ENABLED: bool = os.environ.get("JACGRID_SANDBOX", "0") == "1";
# Demo/test knob: pretend the workload takes this many seconds. Used by
# tests/e2e_reassign.sh to kill a worker while it is holding a task.
glob TASK_DELAY: float = float(os.environ.get("JACGRID_TASK_DELAY", "0"));
glob EMBEDDING_DIM: int = int(os.environ.get("JACGRID_EMBEDDING_DIM", "384"));
# "worker" (default) runs tasks; "sweeper" only drives detect_failures.
glob MODE: str = os.environ.get("JACGRID_MODE", "worker");
glob SWEEP_INTERVAL: float = float(os.environ.get("JACGRID_SWEEP_INTERVAL", "5"));

# `any` aliases for Python builtins/objects the 0.16 checker cannot resolve:
# two-arg round() trips E1054, and sys.stdout is typed "TextIO | Any".
glob PY_ROUND: any = round;
glob STDOUT: any = sys.stdout;

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

"""Python's two-arg `round`, reached through an `any` alias (see PY_ROUND)."""
def round_to(value: float, digits: int) -> float {
    return PY_ROUND(value, digits) as float;
}

def log(message: str) -> None {
    print("[worker " + WORKER_NAME + "] " + message);
    STDOUT.flush();
}

def iso_now() -> str {
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ");
}

def job_types() -> list {
    raw = os.environ.get("WORKER_JOB_TYPES", "noop,embedding");
    out = [];
    for piece in raw.split(",") {
        cleaned = piece.strip();
        if cleaned != "" {
            out.append(cleaned);
        }
    }
    return out;
}

def capabilities() -> dict {
    return {
        "cpu_cores": os.cpu_count(),
        "memory_mb": 0,
        "job_types": job_types(),
        "runtime": "sandbox-harness:v1" if SANDBOX_ENABLED else STUB_RUNTIME,
        "platform": sys.platform
    };
}

def call(walker_name: str, body: dict) -> dict {
    """POST to a coordinator walker; returns the first report or an error dict.""";
    payload = dict(body);
    payload["secret"] = SECRET;
    url = COORDINATOR + "/walker/" + walker_name;
    try {
        response = COORDINATOR_HTTP.post(url, json=payload, timeout=HTTP_TIMEOUT);
    } except Exception as exc {
        return {"error": "transport", "detail": str(exc)};
    }
    if response.status_code >= 400 {
        return {"error": "http_" + str(response.status_code), "detail": response.text[0:400]};
    }
    try {
        body_json = response.json();
    } except Exception as exc {
        return {"error": "bad_json", "detail": response.text[0:400]};
    }
    # jac-scale wraps walker output: reports live at data.reports (observed
    # live: {"ok":true,"data":{"reports":[...],...},...}). Fall back to a
    # top-level "reports" for bare `jac run`-style envelopes.
    reports = body_json.get("reports", []);
    data = body_json.get("data", {});
    if (not isinstance(reports, list) or len(reports) == 0) and isinstance(data, dict) {
        reports = data.get("reports", []);
    }
    if isinstance(reports, list) and len(reports) > 0 {
        return reports[0] as dict;
    }
    return {"error": "empty_report", "detail": json.dumps(body_json)[0:400]};
}

# ---------------------------------------------------------------------------
# Stub runner — fallback path when JACGRID_SANDBOX is unset/0 (Contract B §5)
# ---------------------------------------------------------------------------

def pseudo_embedding(text: str, dim: int) -> list {
    """Deterministic pseudo-embedding: seeded SHA-256 stream -> `dim` floats.

    Same text always gives the same vector, so coordinator-side recompute
    verification will work against the stub as well as against a real model.
    """;
    vector: list[float] = [];
    counter = 0;
    seed = text.encode("utf-8");
    while len(vector) < dim {
        block = hashlib.sha256(seed + str(counter).encode("utf-8")).digest();
        for byte in block {
            if len(vector) >= dim {
                break;
            }
            vector.append(round_to((float(byte as int) - 127.5) / 127.5, 6));
        }
        counter += 1;
    }
    norm = 0.0;
    for value in vector {
        norm += value * value;
    }
    norm = norm ** 0.5;
    if norm == 0.0 {
        return vector;
    }
    normed: list[float] = [];
    for value in vector {
        normed.append(round_to(value / norm, 6));
    }
    return normed;
}

def stub_run(envelope: dict) -> dict {
    """Execute a task envelope locally, with no isolation.""";
    job_type = str(envelope.get("job_type", ""));
    payload = envelope.get("payload", {});
    items = payload.get("items", []);
    if not isinstance(items, list) {
        items = [];
    }
    if job_type == "noop" {
        results = [];
        for item in items {
            results.append(item);
        }
        return {"status": "ok", "output": {"results": results}, "error": None};
    }
    if job_type == "embedding" {
        dim = int(payload.get("dim", EMBEDDING_DIM));
        model = str(payload.get("model", "all-MiniLM-L6-v2"));
        results = [];
        for item in items {
            results.append({
                "id": item.get("id", ""),
                "embedding": pseudo_embedding(str(item.get("text", "")), dim)
            });
        }
        return {"status": "ok",
                "output": {"results": results, "model": model, "dim": dim},
                "error": None};
    }
    return {"status": "error", "output": {},
            "error": "unsupported job_type: " + job_type};
}

def run_task(envelope: dict) -> dict {
    """THE swap point. Sandbox when enabled; local stub otherwise.

    Returns a complete Contract B result envelope (architecture §5) including
    the mandatory `execution` block.
    """;
    if TASK_DELAY > 0.0 {
        time.sleep(TASK_DELAY);
    }
    if SANDBOX_ENABLED {
        # The sandbox owns the complete Contract B envelope. Return it as-is so
        # the coordinator records the sandbox's execution metadata unchanged.
        return sandbox_run_bridge(envelope) as dict;  # jac:ignore[W2001, W1051] -- inline Python bridge
    }

    started_wall = time.time();
    started_cpu = time.process_time();
    started_at = iso_now();
    exit_code = 0;
    try {
        outcome = stub_run(envelope);
    } except Exception as exc {
        outcome = {"status": "error", "output": {}, "error": str(exc)};
        exit_code = 1;
    }
    if outcome["status"] != "ok" {
        exit_code = 1;
    }
    cpu_seconds = round_to(time.process_time() - started_cpu, 4);
    return {
        "task_id": envelope.get("task_id", ""),
        "status": outcome["status"],
        "output": outcome["output"],
        "execution": {
            "runtime": STUB_RUNTIME,
            "started_at": started_at,
            "finished_at": iso_now(),
            "peak_memory_mb": 0,
            "cpu_seconds": cpu_seconds,
            "wall_seconds": round_to(time.time() - started_wall, 4),
            "exit_code": exit_code
        },
        "error": outcome["error"]
    };
}

# ---------------------------------------------------------------------------
# Worker loop
# ---------------------------------------------------------------------------

def register() -> str {
    hostname = os.environ.get("WORKER_HOSTNAME", socket.gethostname());
    while True {
        reply = call("register_worker", {
            "hostname": hostname,
            "worker_name": WORKER_NAME,
            "capabilities": capabilities()
        });
        if "worker_id" in reply {
            log("registered as " + str(reply["worker_id"]) + " on device " + str(reply.get("hostname", "")));
            return str(reply["worker_id"]);
        }
        log("registration failed: " + json.dumps(reply)[0:200] + " — retrying in 2s");
        time.sleep(2.0);
    }
    return "";
}

def send_heartbeat(worker_id: str, state: str, task_id: str) -> None {
    reply = call("heartbeat", {
        "worker_id": worker_id,
        "current_task_status": {"state": state, "task_id": task_id}
    });
    if "error" in reply {
        log("heartbeat error: " + json.dumps(reply)[0:200]);
    }
}

def handle_task(worker_id: str, envelope: dict) -> None {
    task_id = str(envelope.get("task_id", ""));
    item_count = len((envelope.get("payload", {}) as dict).get("items", []) as list);
    log("running task " + task_id + " (" + str(envelope.get("job_type", "")) + ", "
        + str(item_count) + " items)");
    send_heartbeat(worker_id, "busy", task_id);
    result_envelope = run_task(envelope);
    reply = call("submit_result", {"task_id": task_id, "result_envelope": result_envelope});
    if "error" in reply {
        log("submit_result rejected: " + json.dumps(reply)[0:300]);
    } else {
        verification = reply.get("verification", {});
        payment = reply.get("payment", None);
        paid = "no payment";
        if payment is not None {
            paid = str(payment.get("amount", 0)) + " " + str(payment.get("currency", ""))
                   + " tx=" + str(payment.get("tx", ""))[0:12];
        }
        log("task " + task_id + " -> " + str(reply.get("task_status", "?"))
            + " | verification=" + str(verification.get("outcome", "?")) + " | " + paid);
    }
}

def loop(worker_id: str) -> None {
    last_beat = 0.0;
    loops = 0;
    idle_polls = 0;
    while True {
        loops += 1;
        if MAX_LOOPS > 0 and loops > MAX_LOOPS {
            log("max loops reached, exiting");
            return;
        }
        now = time.time();
        if now - last_beat >= HEARTBEAT_SECONDS {
            send_heartbeat(worker_id, "idle", "");
            last_beat = now;
        }
        reply = call("next_task", {"worker_id": worker_id});
        if "error" in reply {
            log("next_task error: " + json.dumps(reply)[0:200]);
            time.sleep(POLL_SECONDS);
            continue;
        }
        envelope = reply.get("task", None);
        if envelope is None {
            idle_polls += 1;
            if EXIT_WHEN_IDLE and idle_polls >= IDLE_LIMIT {
                log("idle for " + str(idle_polls) + " polls, exiting");
                return;
            }
            time.sleep(POLL_SECONDS);
            continue;
        }
        idle_polls = 0;
        handle_task(worker_id, envelope as dict);
        send_heartbeat(worker_id, "idle", "");
        last_beat = time.time();
    }
}

# ---------------------------------------------------------------------------
# Sweeper mode — the out-of-process failure detector (spec §2.4)
# ---------------------------------------------------------------------------

"""Drive `detect_failures` on a timer from outside the coordinator process.

spec §2.4 wants the failure sweep to run every 5s regardless of traffic. The
coordinator cannot schedule that internally: jaclang's `@schedule` builtin does
register background tasks on this stack, but a scheduled *walker* dies with
"Invalid walker object" and a scheduled *function* runs in an isolated context
whose graph writes are never committed (both verified live — see the long note
in platform/coordinator/main.sv.jac).

So the sweep is driven by an ordinary HTTP client instead, which commits through
the normal request path. This mode is that client — one process per grid:

    JACGRID_MODE=sweeper jac run main.jac

It carries no worker identity and never executes tasks. Without it the grid
still self-heals via the implicit sweeps inside next_task/heartbeat, but only
while at least one worker is alive and polling; the sweeper covers the case
where EVERY worker has died.
"""
def sweep_loop() -> None {
    log("sweeper mode: calling detect_failures every " + str(SWEEP_INTERVAL) + "s at " + COORDINATOR);
    loops = 0;
    while True {
        loops += 1;
        if MAX_LOOPS > 0 and loops > MAX_LOOPS {
            log("sweeper: max loops reached, exiting");
            return;
        }
        reply = call("detect_failures", {});
        if "error" in reply {
            log("sweeper: detect_failures error: " + json.dumps(reply)[0:200]);
        } else {
            dead = reply.get("dead_workers", []) as list;
            moved = reply.get("reassigned", []) as list;
            if len(dead) > 0 or len(moved) > 0 {
                log("sweeper: " + str(len(dead)) + " dead worker(s), "
                    + str(len(moved)) + " task(s) requeued " + json.dumps(moved)[0:300]);
            }
        }
        time.sleep(SWEEP_INTERVAL);
    }
}

with entry {
    if MODE == "sweeper" {
        sweep_loop();
        log("sweeper stopped");
    } elif os.environ.get("JACGRID_WORKER_SELFTEST", "0") == "1" {
        # Offline check of the selected runner + Contract B shape (no
        # coordinator needed). The sandbox owns its runtime tag; do not let
        # this test accidentally keep asserting the fallback stub contract.
        env = {"task_id": "t-selftest", "job_type": "noop",
               "payload": {"items": [{"id": "a", "text": "x"}]},
               "limits": {"cpu_seconds": 120, "memory_mb": 2048, "wall_seconds": 180, "network": "none"}};
        if SANDBOX_ENABLED {
            env["workload"] = sandbox_workload_identity_bridge("noop");  # jac:ignore[W2001, W1051] -- inline Python bridge
        }
        out = run_task(env);
        assert out["task_id"] == env["task_id"], "noop task_id changed";
        assert out["status"] == "ok", "noop runner failed";
        assert out["error"] is None, "noop result unexpectedly has an error";
        assert out["output"]["results"] == env["payload"]["items"], "noop echo mismatch";
        for key in ["runtime", "started_at", "finished_at", "peak_memory_mb", "cpu_seconds", "exit_code"] {
            assert key in out["execution"], "execution block missing " + key;
        }
        expected_noop_runtime = "noop-runner:1.0.0" if SANDBOX_ENABLED else STUB_RUNTIME;
        assert out["execution"]["runtime"] == expected_noop_runtime, "noop runtime does not match selected runner";
        expected_capability_runtime = "sandbox-harness:v1" if SANDBOX_ENABLED else STUB_RUNTIME;
        assert capabilities()["runtime"] == expected_capability_runtime, "worker capability runtime does not match selected runner";
        env2 = {"task_id": "t-selftest-2", "job_type": "embedding",
                "payload": {"model": "all-MiniLM-L6-v2", "items": [{"id": "a", "text": "hello"}]},
                "limits": {}};
        if SANDBOX_ENABLED {
            env2["workload"] = sandbox_workload_identity_bridge("embedding");  # jac:ignore[W2001, W1051] -- inline Python bridge
        }
        out2 = run_task(env2);
        assert out2["task_id"] == env2["task_id"], "embedding task_id changed";
        assert out2["status"] == "ok", "embedding runner failed";
        assert out2["error"] is None, "embedding result unexpectedly has an error";
        vec = out2["output"]["results"][0]["embedding"] as list;
        assert len(vec) == EMBEDDING_DIM, "embedding dim mismatch";
        expected_embedding_runtime = "connection-embedding:1.0.0" if SANDBOX_ENABLED else STUB_RUNTIME;
        assert out2["execution"]["runtime"] == expected_embedding_runtime, "embedding runtime does not match selected runner";
        if not SANDBOX_ENABLED {
            assert vec == run_task(env2)["output"]["results"][0]["embedding"], "embedding not deterministic";
        }
        env3 = {"task_id": "t-selftest-3", "job_type": "mystery", "payload": {}, "limits": {}};
        out3 = run_task(env3);
        assert out3["status"] == "error", "unknown job_type should error";
        assert out3["task_id"] == env3["task_id"], "error task_id changed";
        assert out3["execution"] is not None, "error envelope missing execution block";
        print("[worker selftest] OK dim=" + str(len(vec)) + " runtime=" + str(out2["execution"]["runtime"])
            + " capability_runtime=" + expected_capability_runtime);
    } else {
        log("coordinator=" + COORDINATOR + " job_types=" + json.dumps(job_types()));
        wid = register();
        loop(wid);
        log("stopped");
    }
}
