"""JacGrid job client — Contract A (docs/architecture.md §4).

One interface (`JacGridClient`), two implementations, selected by the
`JACGRID_MODE` env var ("mock" default, "live"):

  - MockJacGrid: computes deterministic pseudo-embeddings locally and
    simulates task progress (4 fake tasks across mac1/mac2/mac3) so the
    app's progress UI is fully buildable/demoable with no coordinator
    running.
  - LiveJacGrid: talks to the real coordinator over HTTP —
    /walker/create_job, /walker/get_job, /walker/get_job_result — with
    `secret: JACGRID_KEY` in the body (default `jacgrid-dev-key`), matching
    the walkers Phong's platform/coordinator actually exposes. The 0.16
    response envelope is `{"ok": ..., "data": {"result": ...,
    "reports": [...]}, ...}` — unwrap `data.reports[0]`.

Dict shapes below are exactly Contract A §4 (job status / job result) --
no field renames.
"""

import os;
import math;
import hashlib;
import requests;

def coordinator_http_session() -> any {
    session = requests.Session();
    session.trust_env = False;
    return session;
}

glob JACGRID_COORDINATOR: str = os.environ.get("JACGRID_COORDINATOR", "http://127.0.0.1:8000");
glob JACGRID_SECRET: str = os.environ.get("JACGRID_KEY", "jacgrid-dev-key");
glob COORDINATOR_HTTP: any = coordinator_http_session();

glob EMBED_DIM: int = 384;
glob MOCK_WORKERS: list[str] = ["mac1", "mac2", "mac3"];
glob MOCK_PRICE_PER_TASK: float = 0.10;
glob MOCK_CURRENCY: str = "TESTUSD";

# Python's two-arg `round` through an `any` alias — the 0.16 checker cannot
# resolve the two-argument `round` overload (E1054). Same workaround used
# in platform/coordinator/src/model.jac and workloads/connection-embedding.
glob PY_ROUND: any = round;

# In-process store of mock job state, keyed by job_id. Persists for the
# life of the `jac start` server process.
glob MOCK_JOBS: dict[str, dict[str, any]] = {};

glob ST_MODEL: dict[str, any] = {"loaded": False, "model": None, "available": None};


def _round_to(value: float, digits: int) -> float {
    return PY_ROUND(value, digits) as float;
}


"""Deterministic pseudo-embedding: a hashed bag-of-words scheme. Each word
contributes a fixed pseudo-random 384-d vector (derived from a seeded hash
of the word), so texts that share vocabulary end up with higher cosine
similarity than unrelated texts -- believable clustering for a demo without
needing a real model. Purely seeded off the text: 100% deterministic and
offline-safe."""
def _hash_embed(text: str) -> list[float] {
    vec = [0.0] * EMBED_DIM;
    words = text.lower().replace(",", " ").replace(".", " ").split();
    if len(words) == 0 {
        words = ["empty"];
    }
    for word in words {
        digest = hashlib.sha256(word.encode("utf-8")).digest();
        for i in range(EMBED_DIM) {
            byte_val = digest[i % len(digest)];
            shifted = (byte_val + i * 7) % 256;
            vec[i] += (shifted / 127.5) - 1.0;
        }
    }
    norm = math.sqrt(sum([v * v for v in vec]));
    if norm == 0.0 {
        norm = 1.0;
    }
    return [v / norm for v in vec];
}


"""Cheap one-time check: does sentence-transformers import cleanly?"""
def _st_available() -> bool {
    cached = ST_MODEL["available"];
    if cached is not None {
        return cached as bool;
    }
    try {
        import sentence_transformers;
        ST_MODEL["available"] = True;
    } except Exception {
        ST_MODEL["available"] = False;
    }
    return ST_MODEL["available"] as bool;
}


"""Compute a 384-d embedding for one text.

Default: the deterministic hash scheme (fast, offline-safe, and what every
mock "worker" reproduces without a model download). If JACGRID_USE_ST=1 is
set AND sentence-transformers imports cleanly, use the real
all-MiniLM-L6-v2 model instead (still deterministic given the same text)."""
def embed_text(text: str) -> list[float] {
    use_st = os.environ.get("JACGRID_USE_ST", "0") == "1";
    if use_st and _st_available() {
        try {
            if not ST_MODEL["loaded"] {
                import from sentence_transformers { SentenceTransformer }
                ST_MODEL["model"] = SentenceTransformer("all-MiniLM-L6-v2");
                ST_MODEL["loaded"] = True;
            }
            model = ST_MODEL["model"];
            vec = model.encode([text])[0] as list;
            return [float(x as float) for x in vec];
        } except Exception {
            return _hash_embed(text);
        }
    }
    return _hash_embed(text);
}


obj JacGridClient {
    """Interface. Both implementations provide these three methods with
    exactly these signatures and exactly Contract A §4 dict shapes."""

    def submit_embedding_job(_items: list[dict[str, any]]) -> str {
        return "";
    }

    def poll(_job_id: str) -> dict[str, any] {
        return {};
    }

    def fetch_results(_job_id: str) -> dict[str, any] {
        return {};
    }
}


obj MockJacGrid(JacGridClient) {

    override def submit_embedding_job(items: list[dict[str, any]]) -> str {
        job_id = "job-" + hashlib.sha256(
            (str(len(MOCK_JOBS)) + str(len(items)) + str(id(items))).encode("utf-8")
        ).hexdigest()[:10];

        # 4 fake tasks spread round-robin across mac1/mac2/mac3, matching
        # the spec's mock scheme regardless of actual item count.
        task_ids = ["t-1", "t-2", "t-3", "t-4"];
        tasks: list[dict[str, str]] = [];
        for i in range(len(task_ids)) {
            tasks.append({
                "task_id": task_ids[i],
                "worker": MOCK_WORKERS[i % len(MOCK_WORKERS)],
            });
        }

        # Mock "runs" synchronously; progress simulation only affects what
        # poll()/fetch_results() reveal and when.
        results: list[dict[str, any]] = [];
        for item in items {
            results.append({"id": item["id"], "embedding": embed_text(item["text"] as str)});
        }

        payments: list[dict[str, any]] = [];
        total_paid = 0.0;
        for t in tasks {
            amount = MOCK_PRICE_PER_TASK;
            total_paid += amount;
            payments.append({
                "task_id": t["task_id"],
                "worker": t["worker"],
                "amount": amount,
                "tx": "0xmock" + hashlib.sha256((job_id + t["task_id"]).encode("utf-8")).hexdigest()[:12],
            });
        }

        MOCK_JOBS[job_id] = {
            "job_id": job_id,
            "poll_count": 0,
            "tasks": tasks,
            "results": results,
            "receipt": {
                "tasks": len(tasks),
                "verified": len(tasks),
                "total_paid": _round_to(total_paid, 2),
                "payments": payments,
            },
        };
        return job_id;
    }

    override def poll(job_id: str) -> dict[str, any] {
        if job_id not in MOCK_JOBS {
            return {"job_id": job_id, "status": "failed", "tasks": [], "progress": 0.0};
        }
        job = MOCK_JOBS[job_id];
        job["poll_count"] = (job["poll_count"] as int) + 1;
        n = job["poll_count"] as int;
        tasks = job["tasks"] as list[dict[str, any]];

        statuses: list[str] = [];
        progress: float = 0.0;
        status: str = "queued";
        if n == 1 {
            # first poll: task 0 running, rest queued
            statuses = ["running", "queued", "queued", "queued"];
            progress = 0.1;
            status = "running";
        } elif n == 2 {
            # second poll: half done, half running
            statuses = ["complete", "complete", "running", "running"];
            progress = 0.5;
            status = "running";
        } else {
            # third+ poll: all complete
            statuses = ["complete", "complete", "complete", "complete"];
            progress = 1.0;
            status = "complete";
        }

        out_tasks: list[dict[str, any]] = [];
        for i in range(len(tasks)) {
            t = tasks[i];
            st = statuses[i % len(statuses)];
            out_tasks.append({
                "task_id": t["task_id"],
                "status": st,
                "worker": t["worker"],
                "paid": st == "complete",
            });
        }

        return {
            "job_id": job_id,
            "status": status,
            "tasks": out_tasks,
            "progress": progress,
        };
    }

    override def fetch_results(job_id: str) -> dict[str, any] {
        if job_id not in MOCK_JOBS {
            return {"job_id": job_id, "results": [], "receipt": {}};
        }
        job = MOCK_JOBS[job_id];
        return {
            "job_id": job_id,
            "results": job["results"],
            "receipt": job["receipt"],
        };
    }
}


obj LiveJacGrid(JacGridClient) {
    """Real HTTP calls against the coordinator (Phong's platform/coordinator),
    built to Contract A. Integration-tested against the real coordinator."""

    override def submit_embedding_job(items: list[dict[str, any]]) -> str {
        body = {
            "secret": JACGRID_SECRET,
            "app_id": "matching-app",
            "job_type": "embedding",
            "payload": {
                "model": "all-MiniLM-L6-v2",
                "items": items,
            },
            "partitioning": {"strategy": "chunk", "chunk_size": 25},
            "verification": {"method": "recompute_sample", "sample_rate": 0.1},
            "budget": {"max_total": 3.0, "price_per_task": 0.10, "currency": "TESTUSD"},
        };
        resp = COORDINATOR_HTTP.post(JACGRID_COORDINATOR + "/walker/create_job", json=body, timeout=30);
        data = resp.json() as dict[str, any];
        rep = _unwrap(data);
        return str(rep.get("job_id", ""));
    }

    override def poll(job_id: str) -> dict[str, any] {
        body = {"secret": JACGRID_SECRET, "job_id": job_id};
        resp = COORDINATOR_HTTP.post(JACGRID_COORDINATOR + "/walker/get_job", json=body, timeout=30);
        data = resp.json() as dict[str, any];
        return _unwrap(data);
    }

    override def fetch_results(job_id: str) -> dict[str, any] {
        body = {"secret": JACGRID_SECRET, "job_id": job_id};
        resp = COORDINATOR_HTTP.post(JACGRID_COORDINATOR + "/walker/get_job_result", json=body, timeout=30);
        data = resp.json() as dict[str, any];
        return _unwrap(data);
    }
}


"""Unwraps the 0.16 response envelope: {"ok":..., "data": {"reports": [...]}}.
Falls back to a bare {"reports":[...]} shape too, in case a future jac-scale
version flattens the envelope."""
def _unwrap(data: dict[str, any]) -> dict[str, any] {
    if "data" in data {
        inner = data["data"] as dict[str, any];
        reports = inner.get("reports", []) as list;
        if len(reports) > 0 {
            return reports[0] as dict[str, any];
        }
        return {};
    }
    reports = data.get("reports", []) as list;
    if len(reports) > 0 {
        return reports[0] as dict[str, any];
    }
    return {};
}


"""Selects the implementation per JACGRID_MODE ('mock' default)."""
def get_client() -> JacGridClient {
    mode = os.environ.get("JACGRID_MODE", "mock");
    if mode == "live" {
        return LiveJacGrid();
    }
    return MockJacGrid();
}
