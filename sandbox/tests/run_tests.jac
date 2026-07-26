"""Sandbox harness proof — hand-written task envelopes, no coordinator needed.

Run with:  .venv/bin/jac test sandbox/tests/run_tests.jac -v

Covers docs/luke-sandbox/spec.md §3's failure-mapping table end to end,
driven entirely through the generic invocation path (registry + noop
fixture workload) — nothing here is workload-specific.
"""

import json;
import math;
import os;
import shutil;
import tempfile;

import from sandbox.runner.harness { sandbox_run }
import from sandbox.runner.registry { compute_package_sha256, resolve_workload }

glob HERE = os.path.dirname(os.path.abspath(__file__));
glob ENVELOPES_DIR = os.path.join(HERE, "envelopes");
glob REPO_ROOT = os.path.dirname(os.path.dirname(HERE));


def pin_workload(envelope: dict[str, any]) -> dict[str, any] {
    job_type = str(envelope.get("job_type", ""));
    workload = resolve_workload(job_type);
    if workload is not None {
        envelope["workload"] = {
            "id": workload.workload_id,
            "version": workload.version,
            "manifest_sha256": workload.manifest_sha256,
            "package_sha256": workload.package_sha256,
            "runtime_tags": workload.runtime_tags,
            "verification": workload.verification,
        };
    }
    return envelope;
}


def load_envelope(name: str) -> dict[str, any] {
    path = os.path.join(ENVELOPES_DIR, name);
    f = open(path, "r");
    data = json.load(f) as dict[str, any];
    f.close();
    return pin_workload(data);
}


"""Load the application-owned embedding fixture through the same generic
registry/harness path a worker uses. This deliberately does not mock the
workload: the assertion proves the sandbox can launch a real Contract C
package and preserve its Contract B wrapper."""
def load_embedding_fixture() -> dict[str, any] {
    path = os.path.join(
        REPO_ROOT, "workloads", "connection-embedding", "tests", "fixtures", "task-embedding.json"
    );
    f = open(path, "r");
    data = json.load(f) as dict[str, any];
    f.close();
    return pin_workload(data);
}


def load_embedding_golden(name: str) -> dict[str, any] {
    path = os.path.join(
        REPO_ROOT, "workloads", "connection-embedding", "tests", "fixtures", name
    );
    f = open(path, "r");
    data = json.load(f) as dict[str, any];
    f.close();
    return data;
}


"""Cosine is the contract's verification metric. With unit-normalized
embeddings, 0.999 permits normal BLAS/platform rounding for the real model;
0.999999 identifies the deterministic fallback without claiming bit identity
across JSON/float serialization."""
def cosine_similarity(a: list[float], b: list[float]) -> float {
    dot = 0.0;
    a_norm = 0.0;
    b_norm = 0.0;
    for i in range(len(a)) {
        dot += a[i] * b[i];
        a_norm += a[i] * a[i];
        b_norm += b[i] * b[i];
    }
    if a_norm == 0.0 or b_norm == 0.0 {
        return 0.0;
    }
    return dot / (math.sqrt(a_norm) * math.sqrt(b_norm));
}


test "happy path: noop echo returns ok with matching output" {
    envelope = load_envelope("happy_path.json");
    result = sandbox_run(pin_workload(envelope));
    output = result["output"] as dict[str, any];

    assert result["task_id"] == "t-happy-1";
    assert result["status"] == "ok";
    assert result["error"] is None;
    assert output["echo"]["value"] == 42;
    assert "__jacgrid_execution" not in output;

    execution = result["execution"];
    assert execution["runtime"] == "noop-runner:1.0.0";
    assert execution["exit_code"] == 0;
    assert execution["started_at"] is not None;
    assert execution["finished_at"] is not None;
    assert (execution["peak_memory_mb"] as float) >= 0.0;
    assert (execution["cpu_seconds"] as float) >= 0.0;
}


test "approved embedding workload runs through the generic sandbox and returns Contract B" {
    envelope = load_embedding_fixture();
    result = sandbox_run(pin_workload(envelope));
    output = result["output"] as dict[str, any];

    assert result["task_id"] == envelope["task_id"];
    assert result["status"] == "ok";
    assert result["error"] is None;
    assert result["execution"]["exit_code"] == 0;
    assert "__jacgrid_execution" not in output, "reserved workload metadata leaked into application output";

    results = output["results"] as list[dict[str, any]];
    items = envelope["payload"]["items"] as list[dict[str, any]];
    assert len(results) == len(items);
    result_by_id = {r["id"]: r["embedding"] for r in results};
    assert list(result_by_id.keys()) == [item["id"] for item in items], "result IDs do not match task items";

    primary = load_embedding_golden("expected-model.json");
    fallback = load_embedding_golden("expected-fallback.json");
    primary_results = primary["results"] as list[dict[str, any]];
    fallback_results = fallback["results"] as list[dict[str, any]];
    primary_by_id = {r["id"]: r["embedding"] for r in primary_results};
    fallback_by_id = {r["id"]: r["embedding"] for r in fallback_results};
    matches_primary = True;
    matches_fallback = True;

    for item in items {
        item_id = item["id"] as str;
        actual = result_by_id[item_id] as list[float];
        assert len(actual) == 384;
        assert item_id in primary_by_id and item_id in fallback_by_id, "golden fixture missing " + item_id;
        if cosine_similarity(actual, primary_by_id[item_id] as list[float]) < 0.999 {
            matches_primary = False;
        }
        if cosine_similarity(actual, fallback_by_id[item_id] as list[float]) < 0.999999 {
            matches_fallback = False;
        }
    }

    assert matches_primary or matches_fallback, "embedding output matches neither pinned-model nor fallback golden";
    assert not (matches_primary and matches_fallback), "embedding output ambiguously matches both goldens";
    matched_fixture = "expected-model.json (primary model)" if matches_primary else "expected-fallback.json (deterministic fallback)";
    expected_runtime = "connection-embedding:1.0.0" if matches_primary else "connection-embedding-fallback:1.0.0";
    assert result["execution"]["runtime"] == expected_runtime,
        "Contract B runtime did not preserve the workload path that produced the matched golden";
    print("[sandbox test] embedding fixture matched: " + matched_fixture);
}


test "unapproved workload runtime metadata is rejected and never leaks" {
    envelope = {
        "task_id": "t-runtime-spoof-1",
        "job_type": "noop",
        "payload": {
            "mode": "runtime_metadata",
            "claimed_runtime": "connection-embedding:999.0.0",
        },
        "limits": {"cpu_seconds": 5, "memory_mb": 128, "wall_seconds": 5, "network": "none"},
    };
    result = sandbox_run(pin_workload(envelope));

    assert result["status"] == "error";
    assert result["output"] is None;
    assert result["execution"]["runtime"] == "noop-runner:1.0.0";
    assert "unapproved runtime" in str(result["error"]);
}


test "entrypoint source drift with identical manifest is rejected before execution" {
    envelope = load_envelope("happy_path.json");
    workload = resolve_workload("noop");
    assert workload is not None;
    tempdir = tempfile.mkdtemp(prefix="jacgrid-package-drift-");
    try {
        manifest_copy = os.path.join(tempdir, "workload.json");
        entrypoint_copy = os.path.join(tempdir, "runner.jac");
        shutil.copyfile(workload.manifest_path, manifest_copy);
        shutil.copyfile(workload.entrypoint_path, entrypoint_copy);
        changed = open(entrypoint_copy, "a");
        changed.write("\n# controlled entrypoint drift\n");
        changed.close();
        drifted_package = compute_package_sha256(
            manifest_copy, entrypoint_copy, []
        );
        pinned = envelope["workload"] as dict[str, any];
        pinned["package_sha256"] = drifted_package;
        result = sandbox_run(envelope);

        assert result["status"] == "error";
        assert result["output"] is None;
        assert "pinned workload package" in str(result["error"]);
    } finally {
        shutil.rmtree(tempdir, ignore_errors=True);
    }
}


test "hang mode exceeds wall_seconds -> timeout" {
    envelope = load_envelope("hang_timeout.json");
    result = sandbox_run(envelope);

    assert result["task_id"] == "t-hang-1";
    assert result["status"] == "timeout";
    assert result["output"] is None;
    assert result["error"] is not None;
    assert result["execution"]["runtime"] == "noop-runner:1.0.0";
}


test "memory_hog mode exceeds memory_mb -> limit_exceeded" {
    envelope = load_envelope("memory_limit.json");
    result = sandbox_run(envelope);

    assert result["task_id"] == "t-mem-1";
    assert result["status"] == "limit_exceeded";
    assert result["output"] is None;
    assert result["error"] is not None;
}


test "crash mode (non-zero exit) -> error" {
    envelope = load_envelope("nonzero_exit.json");
    result = sandbox_run(envelope);

    assert result["task_id"] == "t-crash-1";
    assert result["status"] == "error";
    assert result["output"] is None;
    assert result["error"] is not None;
    assert result["execution"]["exit_code"] != 0;
}


test "unknown job_type -> error immediately, no execution attempted" {
    envelope = load_envelope("unknown_workload.json");
    result = sandbox_run(envelope);

    assert result["task_id"] == "t-unknown-1";
    assert result["status"] == "error";
    assert result["output"] is None;
    assert result["error"] is not None;
    assert result["execution"]["runtime"] == "sandbox-harness:v1";
    assert result["execution"]["exit_code"] == -1;
}


test "sandbox_run never raises: malformed envelope still returns an envelope" {
    result = sandbox_run({});

    assert result["status"] == "error";
    assert result["error"] is not None;
    assert result["execution"] is not None;
}


test "Seatbelt (JACGRID_SEATBELT=1): workload still runs but network is denied" {
    if shutil.which("sandbox-exec") is None {
        assert True, "sandbox-exec not available on this machine — skipping";
    } else {
        envelope = load_envelope("network_seatbelt.json");
        os.environ["JACGRID_SEATBELT"] = "1";
        try {
            result = sandbox_run(envelope);
        } finally {
            del os.environ["JACGRID_SEATBELT"];
        }

        assert result["task_id"] == "t-net-1";
        assert result["status"] == "ok";
        assert not result["output"]["echo"]["network_reached"];
    }
}
