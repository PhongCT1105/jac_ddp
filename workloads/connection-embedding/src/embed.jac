"""connection-embedding:1.0.0 — Contract C workload entrypoint.

Owner: connection-agent app team (docs/workload-ownership-decision.md). This
is the ONLY place the embedding algorithm lives — the coordinator schedules
it, the sandbox invokes it, neither reimplements it.

Invocation contract (matches the convention already established by
sandbox/runners/noop.jac, so the generic sandbox can invoke this workload
exactly like any other approved job_type — and per docs/luke-sandbox/spec.md
§3): the caller sets JACGRID_WORKDIR to a work directory containing
`task.json` (a Contract B task envelope, docs/architecture.md §5). On
success this entrypoint writes ONLY the `output` object —
`{"results": [{"id": ..., "embedding": [...]}]}` — to `result.json` and
exits 0; the sandbox harness is what wraps that with execution metadata
into the full Contract B result envelope. On failure, nothing is written
to result.json, an error is printed, and the process exits non-zero — the
sandbox's own "runner exits non-zero" path builds the `error` envelope
from that (see the spec's Failure mapping table).

Runs standalone, with no coordinator or sandbox involved:

    JACGRID_WORKDIR=/tmp/work jac run src/embed.jac

Model: sentence-transformers/all-MiniLM-L6-v2 pinned to revision
1110a243fdf4706b3f48f1d95db1a4f5529b4d41 (the revision already cached
locally per jac-baseline.md — this entrypoint never downloads weights at
task time; `limits.network` should always be "none"). If the model import
or load fails for ANY reason, embeddings fall back to a deterministic
hashed bag-of-words scheme so the workload still produces contract-shaped,
reproducible output — reported under a DISTINCT runtime version
(`connection-embedding-fallback:1.0.0`) so the coordinator/verifier can see
which path actually ran.
"""

import json;
import os;
import sys;
import time;
import hashlib;
import math;
import resource;
import from datetime { datetime, timezone }

glob MODEL_NAME: str = "all-MiniLM-L6-v2";
glob MODEL_REVISION: str = "1110a243fdf4706b3f48f1d95db1a4f5529b4d41";
glob EMBED_DIM: int = 384;
glob RUNTIME_PRIMARY: str = "connection-embedding:1.0.0";
glob RUNTIME_FALLBACK: str = "connection-embedding-fallback:1.0.0";

# Task limits declare `network: "none"` (Contract B) — force huggingface_hub
# to serve the pinned revision straight from the local cache and skip its
# usual "check for updates" HEAD/GET calls. Runs on every import (this is a
# plain `with entry`, not `:__main__`), so it applies under `jac test` too.
with entry {
    os.environ.setdefault("HF_HUB_OFFLINE", "1");
    os.environ.setdefault("TRANSFORMERS_OFFLINE", "1");
}

glob _MODEL_CACHE: dict[str, any] = {"model": None, "loaded": False, "available": None};

# Python's two-arg `round` through an `any` alias: the 0.16 checker cannot
# resolve the two-argument `round` overload (E1054) — same workaround as
# platform/coordinator/src/model.jac's round_to.
glob PY_ROUND: any = round;


def _now_iso() -> str {
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ");
}


def _round_to(value: float, digits: int) -> float {
    return PY_ROUND(value, digits) as float;
}


"""Deterministic fallback embedding: seeded hash bag-of-words, normalized to
unit length. Same scheme every time for the same text — reproducible across
every worker Mac with zero model dependency."""
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


"""One-time check: does sentence-transformers import cleanly in this
environment?"""
def _model_available() -> bool {
    cached = _MODEL_CACHE["available"];
    if cached is not None {
        return cached as bool;
    }
    try {
        import sentence_transformers;
        _MODEL_CACHE["available"] = True;
    } except Exception {
        _MODEL_CACHE["available"] = False;
    }
    return _MODEL_CACHE["available"] as bool;
}


def _load_model() -> any {
    if not _MODEL_CACHE["loaded"] {
        import from sentence_transformers { SentenceTransformer }
        _MODEL_CACHE["model"] = SentenceTransformer(MODEL_NAME, revision=MODEL_REVISION);
        _MODEL_CACHE["loaded"] = True;
    }
    return _MODEL_CACHE["model"];
}


"""items: [{"id": ..., "text": ...}, ...].
Returns {"results": [{"id", "embedding"}...], "runtime": <tag>}. Tries the
pinned real model first; ANY failure (import, load, encode) falls back to
the deterministic hash scheme under a distinct runtime tag — the workload
always produces contract-shaped output."""
def embed_items(items: list[dict[str, any]]) -> dict[str, any] {
    if _model_available() {
        try {
            model = _load_model();
            texts = [it["text"] as str for it in items];
            vectors = model.encode(texts, normalize_embeddings=True) as list;
            results = [];
            for i in range(len(items)) {
                row = vectors[i] as list;
                embedding = [float(v as float) for v in row];
                results.append({"id": items[i]["id"], "embedding": embedding});
            }
            return {"results": results, "runtime": RUNTIME_PRIMARY};
        } except Exception as e {
            print(f"connection-embedding: model path failed, using deterministic fallback: {e}");
        }
    }
    results = [{"id": it["id"], "embedding": _hash_embed(it["text"] as str)} for it in items];
    return {"results": results, "runtime": RUNTIME_FALLBACK};
}


def _error_result(task_id: str, started: str, code: str, message: str) -> dict[str, any] {
    return {
        "task_id": task_id,
        "status": "error",
        "output": {},
        "execution": {
            "runtime": RUNTIME_PRIMARY,
            "started_at": started,
            "finished_at": _now_iso(),
            "peak_memory_mb": 0,
            "cpu_seconds": 0.0,
            "exit_code": 1,
        },
        "error": {"code": code, "message": message},
    };
}


"""Pure function: Contract B task envelope in, Contract B result envelope
out. No file I/O — used directly by tests, and by the `with entry:__main__`
block below for the real sandbox-invoked path."""
def run_task(task: dict[str, any]) -> dict[str, any] {
    task_id = str(task.get("task_id", ""));
    job_type = str(task.get("job_type", ""));
    started = _now_iso();
    start_cpu = time.process_time() as float;

    if job_type != "embedding" {
        return _error_result(task_id, started, "unsupported_job_type",
            f"connection-embedding only handles job_type=embedding, got '{job_type}'");
    }

    payload = task.get("payload", {});
    items = payload.get("items", []) if isinstance(payload, dict) else [];
    if not isinstance(items, list) or len(items) == 0 {
        return _error_result(task_id, started, "empty_items", "payload.items must be a non-empty list");
    }
    for it in items {
        if not isinstance(it, dict) or "id" not in it or "text" not in it {
            return _error_result(task_id, started, "invalid_item", "every item needs an 'id' and a 'text' field");
        }
    }

    try {
        embedded = embed_items(items as list[dict[str, any]]);
        end_cpu = time.process_time() as float;
        cpu_seconds = _round_to(end_cpu - start_cpu, 4);
        # macOS reports ru_maxrss in BYTES (Linux reports KB) — this workload
        # only ever runs on the hackathon's Mac fleet per jac-baseline.md.
        raw_rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss as float;
        peak_mb = _round_to(raw_rss / (1024.0 * 1024.0), 2);
        return {
            "task_id": task_id,
            "status": "ok",
            "output": {"results": embedded["results"]},
            "execution": {
                "runtime": embedded["runtime"],
                "started_at": started,
                "finished_at": _now_iso(),
                "peak_memory_mb": peak_mb,
                "cpu_seconds": cpu_seconds,
                "exit_code": 0,
            },
            "error": None,
        };
    } except Exception as e {
        return _error_result(task_id, started, "exception", str(e));
    }
}


"""File-I/O entrypoint invoked by the sandbox. Per docs/luke-sandbox/spec.md
§3, the RUNNER writes only the `output` part to result.json — the sandbox
wraps it with execution metadata (runtime, timings, peak memory, exit
code) into the full Contract B result envelope itself, and derives
`status` from the exit code / presence of a valid result.json (see that
doc's Failure mapping table). So: on success, write ONLY
`{"results": [...]}` and exit 0; on any failure, write NOTHING to
result.json, print the error to stderr, and exit non-zero — the sandbox's
own "Runner exits non-zero / bad output -> error" path takes it from
there. `run_task()` above still returns the full internal envelope shape
(useful for tests and any in-process caller that wants the metadata
directly); this block is the only place that has to narrow it down for
the on-disk contract."""
with entry:__main__ {
    workdir = os.environ.get("JACGRID_WORKDIR", "");
    if workdir == "" {
        print("connection-embedding: JACGRID_WORKDIR not set");
        sys.exit(1);
    }

    task_path = os.path.join(workdir, "task.json");
    result_path = os.path.join(workdir, "result.json");

    try {
        f = open(task_path, "r");
        task = json.load(f) as dict[str, any];
        f.close();

        result = run_task(task);

        if result["status"] != "ok" {
            err = result.get("error", {}) as dict[str, any];
            print(f"connection-embedding: task failed ({err.get('code', 'unknown')}): {err.get('message', '')}");
            sys.exit(1);
        }

        execution = result["execution"] as dict[str, any];
        print(f"connection-embedding: ok, runtime={execution['runtime']}, cpu_seconds={execution['cpu_seconds']}");

        rf = open(result_path, "w");
        json.dump(result["output"], rf);
        rf.close();
    } except Exception as e {
        print(f"connection-embedding failed: {e}");
        sys.exit(1);
    }
}
