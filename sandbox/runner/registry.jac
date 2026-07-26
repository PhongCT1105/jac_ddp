"""Approved-workload registry.

Loads the job_type -> workload allowlist (allowlist.json) and the approved
workload's manifest (workload.json — Contract C shape, see
contracts/workload/v1/workload.json and its README), and resolves a task
envelope's job_type into everything the harness needs to invoke that
workload as a subprocess.

The sandbox owns NO workload-specific logic: this module only reads JSON
data and resolves file paths declared in it. Registering a new workload
(e.g. the real connection-embedding package once it ships) means adding one
entry to allowlist.json — nothing here changes.
"""

import json;
import os;

glob HERE = os.path.dirname(os.path.abspath(__file__));
glob SANDBOX_ROOT = os.path.dirname(HERE);
glob REPO_ROOT = os.path.dirname(SANDBOX_ROOT);
glob ALLOWLIST_PATH = os.path.join(HERE, "allowlist.json");


obj ResolvedWorkload {
    has job_type: str;
    has workload_id: str;
    has version: str;
    has runtime_tag: str;
    has entrypoint_path: str;
    has workload_root: str;
    has resource_defaults: dict[str, any] = {};
}


def load_allowlist() -> dict[str, any] {
    f = open(ALLOWLIST_PATH, "r");
    data = json.load(f) as dict[str, any];
    f.close();
    return data;
}


"""Resolve an approved job_type to its workload manifest + entrypoint.

Returns None if job_type is not allowlisted, the manifest is missing, or
the manifest is malformed — the caller treats None as an unknown workload
and returns an `error` result envelope. Never raises.
"""
def resolve_workload(job_type: str) -> ResolvedWorkload | None {
    try {
        allowlist = load_allowlist();
    } except Exception {
        return None;
    }

    entry = allowlist.get(job_type, None);
    if entry is None {
        return None;
    }
    if not isinstance(entry, dict) {
        return None;
    }

    manifest_rel = str(entry.get("manifest", ""));
    if manifest_rel == "" {
        return None;
    }

    manifest_path = os.path.join(REPO_ROOT, manifest_rel);
    if not os.path.isfile(manifest_path) {
        return None;
    }

    try {
        mf = open(manifest_path, "r");
        manifest = json.load(mf) as dict[str, any];
        mf.close();
    } except Exception {
        return None;
    }

    name = str(manifest.get("name", entry.get("workload_id", job_type)));
    version = str(manifest.get("version", entry.get("version", "0")));
    entrypoint_rel = str(manifest.get("entrypoint", ""));
    if entrypoint_rel == "" {
        return None;
    }

    workload_root = os.path.dirname(manifest_path);
    entrypoint_path = os.path.join(workload_root, entrypoint_rel);
    if not os.path.isfile(entrypoint_path) {
        return None;
    }

    resource_defaults: dict[str, any] = {};
    rd = manifest.get("resource_requirements", {});
    if isinstance(rd, dict) {
        resource_defaults = rd as dict[str, any];
    }

    return ResolvedWorkload(
        job_type=job_type,
        workload_id=name,
        version=version,
        runtime_tag=f"{name}:{version}",
        entrypoint_path=entrypoint_path,
        workload_root=workload_root,
        resource_defaults=resource_defaults,
    );
}
