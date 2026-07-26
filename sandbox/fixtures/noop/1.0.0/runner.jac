"""noop-runner:1.0.0 — built-in generic fixture workload.

This is the ONE workload-specific file the sandbox layer is allowed to own:
a platform fixture used to prove the generic invocation mechanism and to
drive the harness's own limit-enforcement tests. It owns no application
logic — it is not connection-embedding, and it never will be.

Entrypoint contract every workload package must follow to be invoked by
this sandbox generically (see sandbox/README.md "Entrypoint contract"):

  - read JACGRID_WORKDIR from the environment
  - read <workdir>/task.json (the task envelope's `payload`)
  - write <workdir>/result.json with the job's `output` object
  - exit 0 on success; any other exit code is mapped to result status
    `error` by the harness

payload.mode selects behavior so hand-written test envelopes can exercise
every failure path (Contract B result statuses) through this one fixture:

  "echo" (default) — echoes the payload back into result.json, exits 0
  "crash"          — exits non-zero, writes no result.json  -> `error`
  "hang"           — spins forever, never exits              -> `timeout`
  "memory_hog"     — grows RSS until killed                   -> `limit_exceeded`
  "network"        — attempts one outbound HTTP request, reports whether
                      it reached the network in result.json (always exits
                      0 either way — the interesting signal is
                      output.echo.network_reached, used to prove Seatbelt's
                      `deny network*` from sandbox/tests/run_tests.jac)
"""

import json;
import os;
import sys;
import time;

import from urllib.request { urlopen }

def eprint(msg: str) {
    err = sys.stderr as any;
    err.write(msg + "\n");
}

with entry {
    workdir = os.environ.get("JACGRID_WORKDIR", "");
    if workdir == "" {
        eprint("noop runner: JACGRID_WORKDIR not set");
        sys.exit(1);
    }

    task_path = os.path.join(workdir, "task.json");
    result_path = os.path.join(workdir, "result.json");

    payload: dict[str, any] = {};
    try {
        f = open(task_path, "r");
        task = json.load(f) as dict[str, any];
        f.close();
        payload = task.get("payload", {}) as dict[str, any];
    } except Exception as e {
        eprint(f"noop runner: failed to read task.json: {str(e)}");
        sys.exit(1);
    }

    mode = str(payload.get("mode", "echo"));

    if mode == "crash" {
        eprint("noop runner: crash mode — exiting non-zero on purpose");
        sys.exit(7);
    } elif mode == "hang" {
        eprint("noop runner: hang mode — spinning forever");
        while True {
            time.sleep(1);
        }
    } elif mode == "memory_hog" {
        eprint("noop runner: memory_hog mode — growing RSS until killed");
        chunks: list[bytearray] = [];
        while True {
            chunk = bytearray(10 * 1024 * 1024);
            i = 0;
            while i < len(chunk) {
                chunk[i] = 1;
                i += 4096;
            }
            chunks.append(chunk);
            time.sleep(0.05);
        }
    } elif mode == "network" {
        eprint("noop runner: network mode — attempting one outbound HTTP request");
        reached = False;
        detail = "";
        try {
            resp = urlopen("https://example.com", timeout=3);
            resp.read();
            reached = True;
            detail = "request succeeded";
        } except Exception as e {
            reached = False;
            detail = str(e);
        }
        try {
            output = {"echo": {"network_reached": reached, "detail": detail}};
            rf = open(result_path, "w");
            json.dump(output, rf);
            rf.close();
        } except Exception as e {
            eprint(f"noop runner: failed to write result.json: {str(e)}");
            sys.exit(1);
        }
    } else {
        try {
            output = {"echo": payload};
            rf = open(result_path, "w");
            json.dump(output, rf);
            rf.close();
        } except Exception as e {
            eprint(f"noop runner: failed to write result.json: {str(e)}");
            sys.exit(1);
        }
    }
}
