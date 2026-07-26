"""The sandbox harness — Contract B implementation (Task Execution API).

Public surface, imported by the worker runtime:

    sandbox_run(task_envelope: dict[str, any]) -> dict[str, any]

Given a task envelope (docs/architecture.md §5), runs the approved
workload for its job_type in an isolated workdir under resource limits and
always returns a well-formed result envelope. This function must never
raise and must never hang — every failure mode maps to a status per
docs/luke-sandbox/spec.md §3's table (ok | error | timeout |
limit_exceeded), and the mandatory `execution` metadata block is always
present, even when the workload never ran at all (unknown job_type).

The sandbox owns NO workload-specific logic — job_type -> workload
resolution lives entirely in runner/registry.jac + runner/allowlist.json,
and process execution + limit enforcement lives in runner/execute.jac.
This file only orchestrates: workdir lifecycle, calling those two, and
shaping the final envelope.
"""

import json;
import os;
import shutil;
import sys;
import uuid;

import from .registry { resolve_workload }
import from .execute { iso_now, run_subprocess }

glob HERE = os.path.dirname(os.path.abspath(__file__));
glob SANDBOX_ROOT = os.path.dirname(HERE);
glob REPO_ROOT = os.path.dirname(SANDBOX_ROOT);
glob WORK_ROOT = os.path.join(SANDBOX_ROOT, "work");
glob SEATBELT_PROFILE = os.path.join(SANDBOX_ROOT, "profiles", "seatbelt.sb");

glob DEFAULT_CPU_SECONDS: int = 60;
glob DEFAULT_MEMORY_MB: int = 512;
glob DEFAULT_WALL_SECONDS: int = 60;


def eprint(msg: str) {
    err = sys.stderr as any;
    err.write(msg + "\n");
}


"""Build a well-formed result envelope. `execution` is always populated."""
def make_envelope(
    task_id: str,
    status: str,
    output: dict[str, any] | None,
    error: str | None,
    runtime: str,
    started_at: str,
    finished_at: str,
    peak_memory_mb: float,
    cpu_seconds: float,
    exit_code: int,
) -> dict[str, any] {
    return {
        "task_id": task_id,
        "status": status,
        "output": output,
        "execution": {
            "runtime": runtime,
            "started_at": started_at,
            "finished_at": finished_at,
            "peak_memory_mb": peak_memory_mb,
            "cpu_seconds": cpu_seconds,
            "exit_code": exit_code,
        },
        "error": error,
    };
}


def resolve_jac_bin() -> str {
    candidate = os.path.join(REPO_ROOT, ".venv", "bin", "jac");
    if os.path.isfile(candidate) {
        return candidate;
    }
    found = shutil.which("jac");
    if found is not None {
        return found;
    }
    return "jac";
}


"""Public entrypoint. Never raises; always returns a Contract B envelope."""
def sandbox_run(task_envelope: dict[str, any]) -> dict[str, any] {
    started_at = iso_now();
    task_id = str(task_envelope.get("task_id", "unknown"));

    try {
        return _sandbox_run_inner(task_envelope, task_id, started_at);
    } except Exception as e {
        finished_at = iso_now();
        return make_envelope(
            task_id, "error", None, f"sandbox harness crashed: {str(e)}",
            "sandbox-harness:v1", started_at, finished_at, 0.0, 0.0, -1,
        );
    }
}


def _sandbox_run_inner(
    task_envelope: dict[str, any],
    task_id: str,
    started_at: str,
) -> dict[str, any] {
    job_type_raw = task_envelope.get("job_type", None);
    if job_type_raw is None or str(job_type_raw) == "" {
        finished_at = iso_now();
        return make_envelope(
            task_id, "error", None, "task envelope missing job_type",
            "sandbox-harness:v1", started_at, finished_at, 0.0, 0.0, -1,
        );
    }
    job_type = str(job_type_raw);

    workload = resolve_workload(job_type);
    if workload is None {
        finished_at = iso_now();
        return make_envelope(
            task_id, "error", None,
            f"unknown or unapproved job_type: '{job_type}'",
            "sandbox-harness:v1", started_at, finished_at, 0.0, 0.0, -1,
        );
    }

    pinned_raw = task_envelope.get("workload", None);
    if not isinstance(pinned_raw, dict) {
        finished_at = iso_now();
        return make_envelope(
            task_id, "error", None,
            "task envelope missing pinned workload identity",
            workload.runtime_tag, started_at, finished_at, 0.0, 0.0, -1,
        );
    }
    pinned = pinned_raw as dict[str, any];
    pinned_id = str(pinned.get("id", ""));
    pinned_version = str(pinned.get("version", ""));
    pinned_digest = str(pinned.get("manifest_sha256", ""));
    pinned_package_digest = str(pinned.get("package_sha256", ""));
    if (pinned_id != workload.workload_id
        or pinned_version != workload.version
        or pinned_digest != workload.manifest_sha256
        or pinned_package_digest != workload.package_sha256) {
        finished_at = iso_now();
        return make_envelope(
            task_id, "error", None,
            "pinned workload package does not match the current allowlist/package: "
            + f"pinned={pinned_id}:{pinned_version}"
            + f"@manifest={pinned_digest}@package={pinned_package_digest}, "
            + f"resolved={workload.workload_id}:{workload.version}"
            + f"@manifest={workload.manifest_sha256}@package={workload.package_sha256}",
            workload.runtime_tag, started_at, finished_at, 0.0, 0.0, -1,
        );
    }

    limits_raw = task_envelope.get("limits", {});
    limits: dict[str, any] = {};
    if isinstance(limits_raw, dict) {
        limits = limits_raw as dict[str, any];
    }

    # `as float` (a compile-time-only cast), not `float(... as int)` — limits
    # arriving from JSON may legitimately be floats (e.g. `"wall_seconds":
    # 15.5`); casting through `int` first was a checker-satisfying trick that
    # happened to work at runtime (the erased cast never truncates), but it
    # mis-declared the value's type. Cast straight to float instead.
    wall_seconds: float = limits.get(
        "wall_seconds", workload.resource_defaults.get("wall_seconds", DEFAULT_WALL_SECONDS)
    ) as float;
    cpu_seconds_limit: float = limits.get(
        "cpu_seconds", workload.resource_defaults.get("cpu_seconds", DEFAULT_CPU_SECONDS)
    ) as float;
    memory_mb_limit: float = limits.get(
        "memory_mb", workload.resource_defaults.get("memory_mb", DEFAULT_MEMORY_MB)
    ) as float;

    workdir = os.path.join(WORK_ROOT, f"{task_id}-{uuid.uuid4().hex[:8]}");
    try {
        if os.path.isdir(workdir) {
            shutil.rmtree(workdir, ignore_errors=True);
        }
        os.makedirs(workdir, exist_ok=True);

        task_json_path = os.path.join(workdir, "task.json");
        tf = open(task_json_path, "w");
        json.dump(task_envelope, tf);
        tf.close();
    } except Exception as e {
        finished_at = iso_now();
        _wipe_workdir(workdir);
        return make_envelope(
            task_id, "error", None, f"failed to prepare workdir: {str(e)}",
            workload.runtime_tag, started_at, finished_at, 0.0, 0.0, -1,
        );
    }

    try {
        jac_bin = resolve_jac_bin();
        seatbelt_on = os.environ.get("JACGRID_SEATBELT", "") == "1";

        base_cmd: list[str] = [jac_bin, "run", workload.entrypoint_path];
        command: list[str] = base_cmd;
        if seatbelt_on and os.path.isfile(SEATBELT_PROFILE) {
            real_workdir = os.path.realpath(workdir);
            seatbelt_cmd: list[str] = ["sandbox-exec", "-D", f"WORKDIR={real_workdir}", "-f", SEATBELT_PROFILE];
            command = seatbelt_cmd + base_cmd;  # jac:ignore[W2003] -- false positive: read below by run_subprocess(command, ...)
        }

        run_env: dict[str, str] = dict(os.environ);
        run_env["JACGRID_WORKDIR"] = workdir;
        run_env["JACGRID_TASK_ID"] = task_id;

        result_partial = run_subprocess(
            command, workdir, run_env, workload.runtime_tag, workload.runtime_tags,
            wall_seconds, cpu_seconds_limit, memory_mb_limit,
        );
    } except Exception as e {
        finished_at = iso_now();
        _wipe_workdir(workdir);
        return make_envelope(
            task_id, "error", None, f"sandbox failed to run workload subprocess: {str(e)}",
            workload.runtime_tag, started_at, finished_at, 0.0, 0.0, -1,
        );
    }

    _wipe_workdir(workdir);

    output_val = result_partial.get("output", None);
    output: dict[str, any] | None = None;
    if isinstance(output_val, dict) {
        output = output_val as dict[str, any];
    }

    error_val = result_partial.get("error", None);
    error: str | None = None;
    if error_val is not None {
        error = str(error_val);
    }

    return make_envelope(
        task_id,
        str(result_partial.get("status", "error")),
        output,
        error,
        str(result_partial.get("runtime", workload.runtime_tag)),
        str(result_partial.get("started_at", started_at)),
        str(result_partial.get("finished_at", iso_now())),
        result_partial.get("peak_memory_mb", 0.0) as float,
        result_partial.get("cpu_seconds", 0.0) as float,
        result_partial.get("exit_code", -1) as int,
    );
}


def _wipe_workdir(workdir: str) {
    if os.environ.get("JACGRID_KEEP_WORKDIR", "") == "1" {
        return;
    }
    try {
        shutil.rmtree(workdir, ignore_errors=True);
    } except Exception { }
}
