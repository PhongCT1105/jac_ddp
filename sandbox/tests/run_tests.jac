"""Sandbox harness proof — hand-written task envelopes, no coordinator needed.

Run with:  .venv/bin/jac test sandbox/tests/run_tests.jac -v

Covers docs/luke-sandbox/spec.md §3's failure-mapping table end to end,
driven entirely through the generic invocation path (registry + noop
fixture workload) — nothing here is workload-specific.
"""

import json;
import os;
import shutil;

import from sandbox.runner.harness { sandbox_run }

glob HERE = os.path.dirname(os.path.abspath(__file__));
glob ENVELOPES_DIR = os.path.join(HERE, "envelopes");


def load_envelope(name: str) -> dict[str, any] {
    path = os.path.join(ENVELOPES_DIR, name);
    f = open(path, "r");
    data = json.load(f) as dict[str, any];
    f.close();
    return data;
}


test "happy path: noop echo returns ok with matching output" {
    envelope = load_envelope("happy_path.json");
    result = sandbox_run(envelope);

    assert result["task_id"] == "t-happy-1";
    assert result["status"] == "ok";
    assert result["error"] is None;
    assert result["output"]["echo"]["value"] == 42;

    execution = result["execution"];
    assert execution["runtime"] == "noop-runner:1.0.0";
    assert execution["exit_code"] == 0;
    assert execution["started_at"] is not None;
    assert execution["finished_at"] is not None;
    assert (execution["peak_memory_mb"] as float) >= 0.0;
    assert (execution["cpu_seconds"] as float) >= 0.0;
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
