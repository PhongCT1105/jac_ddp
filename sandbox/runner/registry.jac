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
import hashlib;

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
    has manifest_path: str;
    has manifest_sha256: str;
    has package_sha256: str;
    has runtime_tags: list[str] = [];
    has resource_defaults: dict[str, any] = {};
    has verification: dict[str, any] = {};
}


def load_allowlist() -> dict[str, any] {
    f = open(ALLOWLIST_PATH, "r");
    data = json.load(f) as dict[str, any];
    f.close();
    return data;
}


def _digest_file(hasher: any, label: str, path: str) {
    f = open(path, "rb");
    data = f.read();
    f.close();
    label_bytes = label.encode("utf-8");
    hasher.update(len(label_bytes).to_bytes(8, "big"));
    hasher.update(label_bytes);
    hasher.update(len(data).to_bytes(8, "big"));
    hasher.update(data);
}


"""Hash the immutable executable package without touching external model caches.

The digest covers raw manifest bytes, resolved entrypoint bytes, and any
manifest-declared `local_artifacts` in their deterministic sorted order.
"""
def compute_package_sha256(
    manifest_path: str,
    entrypoint_path: str,
    artifact_paths: list[str],
) -> str {
    hasher = hashlib.sha256();
    hasher.update("jacgrid-package-v1".encode("utf-8"));
    _digest_file(hasher, "manifest", manifest_path);
    _digest_file(hasher, "entrypoint", entrypoint_path);
    for i in range(len(artifact_paths)) {
        _digest_file(hasher, "artifact-" + str(i), artifact_paths[i]);
    }
    return "sha256:" + hasher.hexdigest();
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
        digest_file = open(manifest_path, "rb");
        manifest_sha256 = "sha256:" + hashlib.sha256(digest_file.read()).hexdigest();
        digest_file.close();
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

    artifact_paths: list[str] = [];
    artifacts_raw = manifest.get("local_artifacts", []);
    if not isinstance(artifacts_raw, list) {
        return None;
    }
    artifact_rels: list[str] = [];
    for artifact in artifacts_raw {
        if not isinstance(artifact, str) or str(artifact) == "" {
            return None;
        }
        artifact_rels.append(str(artifact));
    }
    artifact_rels.sort();
    workload_root_real = os.path.realpath(workload_root);
    for artifact_rel in artifact_rels {
        artifact_path = os.path.realpath(os.path.join(workload_root, artifact_rel));
        if (artifact_path != workload_root_real
            and not artifact_path.startswith(workload_root_real + os.sep)) {
            return None;
        }
        if not os.path.isfile(artifact_path) {
            return None;
        }
        artifact_paths.append(artifact_path);
    }
    package_sha256 = compute_package_sha256(
        manifest_path, entrypoint_path, artifact_paths
    );

    resource_defaults: dict[str, any] = {};
    rd = manifest.get("resource_requirements", {});
    if isinstance(rd, dict) {
        resource_defaults = rd as dict[str, any];
    }

    runtime_tag = f"{name}:{version}";
    runtime_tags: list[str] = [runtime_tag];
    tags_raw = manifest.get("runtime_tags", None);
    if tags_raw is not None {
        if not isinstance(tags_raw, list) {
            return None;
        }
        runtime_tags = [];
        for tag in tags_raw {
            if not isinstance(tag, str) or str(tag) == "" {
                return None;
            }
            runtime_tags.append(str(tag));
        }
        if runtime_tag not in runtime_tags {
            return None;
        }
    }

    verification: dict[str, any] = {};
    verification_raw = manifest.get("verification", {});
    if isinstance(verification_raw, dict) {
        verification = verification_raw as dict[str, any];
    }

    return ResolvedWorkload(
        job_type=job_type,
        workload_id=name,
        version=version,
        runtime_tag=runtime_tag,
        runtime_tags=runtime_tags,
        entrypoint_path=entrypoint_path,
        workload_root=workload_root,
        manifest_path=manifest_path,
        manifest_sha256=manifest_sha256,
        package_sha256=package_sha256,
        resource_defaults=resource_defaults,
        verification=verification,
    );
}
