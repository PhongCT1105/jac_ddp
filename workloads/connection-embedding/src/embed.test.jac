"""Tests for connection-embedding:1.0.0 (src/embed.jac).

Run with `jac test src/embed.jac` (or a bare `jac test` from this project's
root — see jac.toml [test]). Exercises the pure `run_task()` function
directly against the fixtures in tests/fixtures/ — no coordinator, no
sandbox, no file-I/O side effects — per the workload-ownership-decision.md
requirement that this package "run locally without the coordinator".
"""

import json;
import math;


def _load_fixture(name: str) -> dict[str, any] {
    f = open("tests/fixtures/" + name, "r");
    data = json.load(f) as dict[str, any];
    f.close();
    return data;
}


def _cosine(a: list[float], b: list[float]) -> float {
    dot = 0.0;
    na = 0.0;
    nb = 0.0;
    for i in range(len(a)) {
        dot += a[i] * b[i];
        na += a[i] * a[i];
        nb += b[i] * b[i];
    }
    if na == 0.0 or nb == 0.0 {
        return 0.0;
    }
    return dot / (math.sqrt(na) * math.sqrt(nb));
}


test "fallback hash embedding matches the independently-computed golden fixture" {
    task = _load_fixture("task-embedding.json");
    items = task["payload"]["items"] as list[dict[str, any]];
    expected = _load_fixture("expected-fallback.json");
    expected_results = expected["results"] as list[dict[str, any]];
    expected_by_id = {r["id"]: r["embedding"] for r in expected_results};

    for it in items {
        text = it["text"] as str;
        actual = _hash_embed(text);
        golden = expected_by_id[it["id"]] as list[float];
        assert len(actual) == 384;
        sim = _cosine(actual, golden);
        assert sim > 0.999999 , f"fallback embedding for {it[
            'id'
        ]} drifted from golden fixture (cosine={sim})";
    }
}


test "run_task rejects a job_type outside the allowlist without raising" {
    task = _load_fixture("task-bad-job-type.json");
    result = run_task(task);
    assert result["status"] == "error";
    assert result["error"]["code"] == "unsupported_job_type";
    assert result["execution"]["exit_code"] == 1;
}


test "run_task rejects an empty items list" {
    task = {"task_id": "t-empty", "job_type": "embedding", "payload": {"items": []}};
    result = run_task(task);
    assert result["status"] == "error";
    assert result["error"]["code"] == "empty_items";
}


test "run_task rejects an item missing required fields" {
    task = {
        "task_id": "t-bad-item",
        "job_type": "embedding",
        "payload": {"items": [{"id": "only-id"}]}
    };
    result = run_task(task);
    assert result["status"] == "error";
    assert result["error"]["code"] == "invalid_item";
}


test "run_task produces a contract-shaped result envelope with 384-d embeddings" {
    task = _load_fixture("task-embedding.json");
    result = run_task(task);

    assert result["status"] == "ok";
    assert result["error"] is None;
    assert result["task_id"] == task["task_id"];

    results = result["output"]["results"] as list[dict[str, any]];
    items = task["payload"]["items"] as list[dict[str, any]];
    assert len(results) == len(items);
    for r in results {
        assert len(r["embedding"] as list) == 384;
    }

    execution = result["execution"] as dict[str, any];
    for key in [
        "runtime",
        "started_at",
        "finished_at",
        "peak_memory_mb",
        "cpu_seconds",
        "exit_code"
    ] {
        assert key in execution , f"execution block missing required key '{key}'";
    }
    assert execution["runtime"] in [
        "connection-embedding:1.0.0",
        "connection-embedding-fallback:1.0.0"
    ];
    assert execution["exit_code"] == 0;
}


test "file output carries only application results plus reserved runtime provenance" {
    task = _load_fixture("task-embedding.json");
    result = run_task(task);
    file_output = _file_output(result);

    assert "results" in file_output;
    assert "task_id" not in file_output;
    assert "status" not in file_output;
    assert "execution" not in file_output;
    assert "__jacgrid_execution" in file_output;
    assert file_output["__jacgrid_execution"]["runtime"] == result["execution"][
        "runtime"
    ];
}


test "primary model path matches the golden fixture within verification tolerance" {
    task = _load_fixture("task-embedding.json");
    result = run_task(task);
    execution = result["execution"] as dict[str, any];

    if execution["runtime"] != "connection-embedding:1.0.0" {
        # sentence-transformers unavailable in this environment — the
        # fallback-scheme test above already covers determinism.
        assert True;
    } else {
        expected = _load_fixture("expected-model.json");
        expected_results = expected["results"] as list[dict[str, any]];
        expected_by_id = {r["id"]: r["embedding"] for r in expected_results};
        results = result["output"]["results"] as list[dict[str, any]];
        for r in results {
            golden = expected_by_id[r["id"]] as list[float];
            sim = _cosine(r["embedding"] as list[float], golden);
            assert sim >= 0.999 , f"embedding for {r[
                'id'
            ]} outside verification tolerance (cosine={sim})";
        }
    }
}
