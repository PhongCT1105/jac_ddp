"""Generic subprocess execution + resource-limit enforcement.

Knows nothing about any specific workload — only how to launch an
entrypoint script as a subprocess, enforce wall-clock / CPU / memory
limits by polling, and map every outcome onto Contract B's result-envelope
shape (docs/architecture.md §5, contracts/task-execution/v1). This module
never raises and never hangs: every code path below returns a partial
envelope dict (status/output/error + the mandatory execution fields minus
task_id, which the harness adds).
"""

import json;
import os;
import signal as signal_mod;
import subprocess;
import sys;
import time;

import from datetime { datetime, timezone }

glob POLL_INTERVAL_SECONDS: float = 0.1;
glob KILL_REAP_TIMEOUT_SECONDS: float = 5.0;
glob STDERR_TAIL_CHARS: int = 4000;
glob RESERVED_EXECUTION_METADATA_FIELD: str = "__jacgrid_execution";
glob RESULT_JSON_MAX_BYTES: int = 50 * 1024 * 1024;  # 50MB — a workload's result.json
                                                       # has no business being bigger than this;
                                                       # refuse to read it into memory if it is.


def eprint(msg: str) {
    err = sys.stderr as any;
    err.write(msg + "\n");
}


"""Whether psutil imports cleanly in this environment (checked once)."""
def psutil_available() -> bool {
    try {
        import psutil;
        return True;
    } except Exception {
        return False;
    }
}


glob HAVE_PSUTIL: bool = psutil_available();

with entry {
    if not HAVE_PSUTIL {
        eprint(
            "JacGrid sandbox WARNING: psutil is not installed in this environment. "
            "CPU-time limit enforcement is DISABLED (cpu_seconds always reports 0.0; "
            "a runaway task is only caught by wall_seconds, and will be misreported "
            "as `timeout` rather than `limit_exceeded`), and RSS tracking falls back "
            "to a single-process `ps` sample (child processes are not counted). "
            "Run sandbox/setup.sh to install psutil into .venv. See sandbox/README.md "
            "\"Resource enforcement\" for the full caveat."
        );
    }
}


"""Current UTC time formatted per Contract B (`2026-07-26T14:03:21Z`)."""
def iso_now() -> str {
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ");
}


"""Best-effort SIGKILL of the whole process group; never raises."""
def kill_process_group(pid: int) {
    try {
        pgid = os.getpgid(pid);
        sigkill: int = signal_mod.SIGKILL as int;
        os.killpg(pgid, sigkill);
    } except Exception { }
}


"""Sum RSS (MB) of a pid + all its children via psutil. 0.0 if unavailable."""
def rss_mb_psutil(pid: int) -> float {
    total: float = 0.0;
    try {
        import psutil;
        proc = psutil.Process(pid) as any;
        procs: list[any] = [proc];
        try {
            children = proc.children(recursive=True) as list[any];
            procs.extend(children);
        } except Exception { }
        for p in procs {
            try {
                rss_bytes: float = p.memory_info().rss as float;
                total += rss_bytes;
            } except Exception { }
        }
    } except Exception {
        return 0.0;
    }
    return total / (1024.0 * 1024.0);
}


"""Sum cumulative CPU seconds (user+sys) of a pid + children via psutil."""
def cpu_seconds_psutil(pid: int) -> float {
    total: float = 0.0;
    try {
        import psutil;
        proc = psutil.Process(pid) as any;
        procs: list[any] = [proc];
        try {
            children = proc.children(recursive=True) as list[any];
            procs.extend(children);
        } except Exception { }
        for p in procs {
            try {
                ct = p.cpu_times() as any;
                user_s: float = ct.user as float;
                sys_s: float = ct.system as float;
                total += user_s + sys_s;
            } except Exception { }
        }
    } except Exception {
        return 0.0;
    }
    return total;
}


"""RSS (MB) of a single pid via the `ps` CLI — fallback when psutil is absent."""
def rss_mb_ps(pid: int) -> float {
    try {
        out = subprocess.run(
            ["ps", "-o", "rss=", "-p", str(pid)],
            capture_output=True,
            text=True,
            timeout=2,
        );
        line = out.stdout.strip();
        if line == "" {
            return 0.0;
        }
        return float(line) / 1024.0;
    } except Exception {
        return 0.0;
    }
}


def current_rss_mb(pid: int) -> float {
    if HAVE_PSUTIL {
        return rss_mb_psutil(pid);
    }
    return rss_mb_ps(pid);
}


def current_cpu_seconds(pid: int) -> float {
    if HAVE_PSUTIL {
        return cpu_seconds_psutil(pid);
    }
    return 0.0;
}


"""One partial result (everything but task_id) — the harness adds that."""
def partial(
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
        "status": status,
        "output": output,
        "error": error,
        "runtime": runtime,
        "started_at": started_at,
        "finished_at": finished_at,
        "peak_memory_mb": peak_memory_mb,
        "cpu_seconds": cpu_seconds,
        "exit_code": exit_code,
    };
}


"""Launch `command` in `workdir`, enforce limits by polling, return a partial envelope.

Never raises: launch failures, timeouts, memory/CPU overruns, non-zero
exits, and missing/invalid result.json all map to a well-formed partial
result dict per docs/luke-sandbox/spec.md §3's failure table. On success
(`ok`), `output` is the parsed contents of `<workdir>/result.json`.
"""
def run_subprocess(
    command: list[str],
    workdir: str,
    env: dict[str, str],
    runtime_tag: str,
    allowed_runtime_tags: list[str],
    wall_seconds: float,
    cpu_seconds_limit: float,
    memory_mb_limit: float,
) -> dict[str, any] {
    started_at = iso_now();
    start_monotonic = time.monotonic();

    if not HAVE_PSUTIL {
        eprint(
            f"JacGrid sandbox WARNING (task runtime {runtime_tag}): psutil unavailable — "
            "this task's cpu_seconds will report 0.0 and its CPU limit is not enforced "
            "(only wall_seconds and single-process RSS are); see sandbox/README.md."
        );
    }

    try {
        proc = subprocess.Popen(
            command,
            cwd=workdir,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        );
    } except Exception as e {
        finished_at = iso_now();
        return partial(
            "error", None, f"failed to launch workload subprocess: {str(e)}",
            runtime_tag, started_at, finished_at, 0.0, 0.0, -1,
        );
    }

    peak_rss: float = 0.0;
    last_cpu: float = 0.0;
    outcome = "completed";  # completed | timeout | limit_exceeded

    while True {
        ret = proc.poll();
        if ret is not None {
            break;
        }

        elapsed = time.monotonic() - start_monotonic;
        if elapsed > wall_seconds {
            outcome = "timeout";
            kill_process_group(proc.pid);
            break;
        }

        rss = current_rss_mb(proc.pid);
        if rss > peak_rss {
            peak_rss = rss;
        }
        if rss > memory_mb_limit {
            outcome = "limit_exceeded";
            kill_process_group(proc.pid);
            break;
        }

        cpu_now = current_cpu_seconds(proc.pid);
        if cpu_now > last_cpu {
            last_cpu = cpu_now;
        }
        if HAVE_PSUTIL and cpu_now > cpu_seconds_limit {
            outcome = "limit_exceeded";
            kill_process_group(proc.pid);
            break;
        }

        time.sleep(POLL_INTERVAL_SECONDS);
    }

    try {
        proc.wait(timeout=KILL_REAP_TIMEOUT_SECONDS);
    } except Exception {
        kill_process_group(proc.pid);
        try {
            proc.wait(timeout=KILL_REAP_TIMEOUT_SECONDS);
        } except Exception { }
    }

    finished_at = iso_now();
    exit_code: int = -1;
    if proc.returncode is not None {
        exit_code = proc.returncode as int;
    }

    stderr_tail = "";
    try {
        comm_result = proc.communicate(timeout=1);
        stderr_data = comm_result[1];
        if stderr_data {
            stderr_tail = (stderr_data[-STDERR_TAIL_CHARS:]) as str;
        }
    } except Exception {
        stderr_tail = "";
    }

    if outcome == "timeout" {
        return partial(
            "timeout", None,
            f"wall_seconds limit ({wall_seconds}) exceeded; process killed. stderr: {stderr_tail}",
            runtime_tag, started_at, finished_at, peak_rss, last_cpu, exit_code,
        );
    }

    if outcome == "limit_exceeded" {
        return partial(
            "limit_exceeded", None,
            f"resource limit exceeded (memory_mb<={memory_mb_limit}, cpu_seconds<={cpu_seconds_limit}); "
            f"peak_memory_mb={peak_rss}, cpu_seconds={last_cpu}. stderr: {stderr_tail}",
            runtime_tag, started_at, finished_at, peak_rss, last_cpu, exit_code,
        );
    }

    if exit_code != 0 {
        return partial(
            "error", None, f"workload exited with code {exit_code}. stderr: {stderr_tail}",
            runtime_tag, started_at, finished_at, peak_rss, last_cpu, exit_code,
        );
    }

    result_path = os.path.join(workdir, "result.json");
    if not os.path.isfile(result_path) {
        return partial(
            "error", None, "workload exited 0 but wrote no result.json",
            runtime_tag, started_at, finished_at, peak_rss, last_cpu, exit_code,
        );
    }

    result_size = os.path.getsize(result_path);
    if result_size > RESULT_JSON_MAX_BYTES {
        return partial(
            "error", None,
            f"result.json is {result_size} bytes, over the {RESULT_JSON_MAX_BYTES}-byte cap — refusing to read it",
            runtime_tag, started_at, finished_at, peak_rss, last_cpu, exit_code,
        );
    }

    try {
        rf = open(result_path, "r");
        output_raw = json.load(rf);
        rf.close();
    } except Exception as e {
        return partial(
            "error", None, f"result.json unreadable/invalid JSON: {str(e)}",
            runtime_tag, started_at, finished_at, peak_rss, last_cpu, exit_code,
        );
    }

    if not isinstance(output_raw, dict) {
        return partial(
            "error", None, "result.json must contain an output object",
            runtime_tag, started_at, finished_at, peak_rss, last_cpu, exit_code,
        );
    }
    output = output_raw as dict[str, any];
    actual_runtime = runtime_tag;
    runtime_metadata = output.pop(RESERVED_EXECUTION_METADATA_FIELD, None);
    if runtime_metadata is not None {
        if not isinstance(runtime_metadata, dict) {
            return partial(
                "error", None,
                f"{RESERVED_EXECUTION_METADATA_FIELD} must be an object",
                runtime_tag, started_at, finished_at, peak_rss, last_cpu, exit_code,
            );
        }
        metadata = runtime_metadata as dict[str, any];
        claimed_runtime = metadata.get("runtime", None);
        if not isinstance(claimed_runtime, str) or str(claimed_runtime) == "" {
            return partial(
                "error", None,
                f"{RESERVED_EXECUTION_METADATA_FIELD}.runtime must be a non-empty string",
                runtime_tag, started_at, finished_at, peak_rss, last_cpu, exit_code,
            );
        }
        actual_runtime = str(claimed_runtime);
        if actual_runtime not in allowed_runtime_tags {
            return partial(
                "error", None,
                f"workload claimed unapproved runtime '{actual_runtime}'; "
                f"manifest allows {allowed_runtime_tags}",
                runtime_tag, started_at, finished_at, peak_rss, last_cpu, exit_code,
            );
        }
    }

    return partial(
        "ok", output, None,
        actual_runtime, started_at, finished_at, peak_rss, last_cpu, exit_code,
    );
}
