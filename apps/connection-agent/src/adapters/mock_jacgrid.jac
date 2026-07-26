"""Local provider adapter for the pinned connection-embedding workload."""

import hashlib;
import json;
import math;
import os;
import subprocess;
import from src.contracts.models { EmbeddingBatchResult, EmbeddingItem }


obj WorkloadDescriptor {
    has workload_id: str,
        workload_version: str,
        model_id: str,
        model_revision: str,
        artifact_sha256: str,
        tolerance: float;
}


obj MockJacGrid {
    has workload_dir: str,
        chunk_size: int = 10,
        invocation_count: int = 0,
        jobs_by_key: dict[str, EmbeddingBatchResult] = {},
        request_hashes_by_key: dict[str, str] = {};
}


def load_workload_descriptor(workload_dir: str) -> WorkloadDescriptor {
    try {
        manifest = json.loads(open(os.path.join(workload_dir, "workload.json")).read());
        model = manifest.get("model");
        verification = manifest.get("verification");
        if manifest.get("contract_version") != 1
        or manifest.get("id") != "connection-embedding"
        or manifest.get("version") != "0.1.0"
        or manifest.get("entrypoint") != ["jac", "run", "src/main.jac"]
        or not isinstance(model, dict)
        or not isinstance(verification, dict) {
            raise ValueError("invalid_workload_descriptor");
        }
        model_id = model.get("id");
        model_revision = model.get("revision");
        artifact_sha256 = model.get("artifact_sha256");
        tolerance = verification.get("numeric_tolerance");
        if not isinstance(model_id, str)
        or not isinstance(model_revision, str)
        or not isinstance(artifact_sha256, str)
        or verification.get("normalized") is not True
        or isinstance(tolerance, bool)
        or not isinstance(tolerance, (int, float))
        or not math.isfinite(float(tolerance))
        or float(tolerance) < 0.0
        or float(tolerance) > 0.01 {
            raise ValueError("invalid_workload_descriptor");
        }
        return WorkloadDescriptor(
            workload_id="connection-embedding",
            workload_version=manifest.get("version") as str,
            model_id=model_id,
            model_revision=model_revision,
            artifact_sha256=artifact_sha256,
            tolerance=float(tolerance),
        );
    } except ValueError as error {
        if str(error) == "invalid_workload_descriptor" {
            raise error;
        }
        raise ValueError("invalid_workload_descriptor");
    } except Exception {
        raise ValueError("invalid_workload_descriptor");
    }
}


def validate_workload_result(
    output: dict[str, any], expected_ids: list[str], descriptor: WorkloadDescriptor,
) -> dict[str, list[float]] {
    if output.get("contract_version") != 1
    or output.get("dimensions") != 16
    or output.get("normalized") is not True {
        raise ValueError("malformed_workload_result");
    }
    model = output.get("model");
    if not isinstance(model, dict)
    or model.get("id") != descriptor.model_id
    or model.get("revision") != descriptor.model_revision
    or model.get("artifact_sha256") != descriptor.artifact_sha256 {
        raise ValueError("workload_identity_mismatch");
    }
    raw_results = output.get("results");
    if not isinstance(raw_results, list) or len(raw_results) != len(expected_ids) {
        raise ValueError("partial_embedding_result");
    }
    vectors: dict[str, list[float]] = {};
    for (index, raw_result) in enumerate(raw_results) {
        if not isinstance(raw_result, dict) {
            raise ValueError("invalid_result_order");
        }
        result: dict[str, any] = raw_result as dict[str, any];
        if result.get("id") != expected_ids[index] {
            raise ValueError("invalid_result_order");
        }
        embedding = result.get("embedding");
        if not isinstance(embedding, list) {
            raise ValueError("malformed_workload_result");
        }
        if len(embedding) != 16 {
            raise ValueError("wrong_vector_dimension");
        }
        vector: list[float] = [];
        for component in embedding {
            if isinstance(component, bool) or not isinstance(component, (int, float)) {
                raise ValueError("invalid_vector_value");
            }
            value: float = float(component);
            if not math.isfinite(value) {
                raise ValueError("invalid_vector_value");
            }
            vector.append(value);
        }
        norm_squared: float = sum([value * value for value in vector]);
        if abs(norm_squared - 1.0) > descriptor.tolerance {
            raise ValueError("invalid_vector_normalization");
        }
        vectors[expected_ids[index]] = vector;
    }
    return vectors;
}


def invoke_workload(workload_dir: str, items: list[EmbeddingItem]) -> dict[str, any] {
    payload: dict[str, any] = {
        "contract_version": 1,
        "items": [{"id": item.item_id, "text": item.text} for item in items],

    };
    try {
        completed = subprocess.run(
            ["jac", "run", "src/main.jac"],
            cwd=workload_dir,
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            check=False,
        );
        if completed.returncode != 0 {
            raise RuntimeError("embedding_failed");
        }
        return json.loads(completed.stdout) as dict[str, any];
    } except RuntimeError as error {
        if str(error) == "embedding_failed" {
            raise error;
        }
        raise RuntimeError("embedding_failed");
    } except Exception {
        raise RuntimeError("embedding_failed");
    }
}


def canonical_result_hash(
    expected_ids: list[str],
    vectors: dict[str, list[float]],
    descriptor: WorkloadDescriptor,
) -> str {
    canonical = {
        "workload_id": descriptor.workload_id,
        "workload_version": descriptor.workload_version,
        "artifact_sha256": descriptor.artifact_sha256,
        "results": [
            {"id": item_id, "embedding": vectors[item_id]} for item_id in expected_ids
        ],

    };
    return "sha256:" + hashlib.sha256(
        json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest();
}


def submit_embeddings(
    mock: MockJacGrid, items: list[EmbeddingItem], idempotency_key: str,
) -> EmbeddingBatchResult {
    if len(idempotency_key.strip()) == 0 {
        raise ValueError("invalid_request");
    }
    if mock.chunk_size <= 0 {
        raise ValueError("invalid_chunk_size");
    }
    if len(items) == 0 {
        raise ValueError("invalid_items");
    }
    expected_ids: list[str] = [];
    canonical_items: list[dict[str, str]] = [];
    for item in items {
        if len(item.item_id.strip()) == 0 or len(item.text.strip()) == 0 {
            raise ValueError("invalid_items");
        }
        expected_ids.append(item.item_id);
        canonical_items.append({"id": item.item_id, "text": item.text});
    }
    if len(set(expected_ids)) != len(expected_ids) {
        raise ValueError("duplicate_item_id");
    }
    request_hash: str = hashlib.sha256(
        json.dumps(canonical_items, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest();
    if idempotency_key in mock.jobs_by_key {
        if mock.request_hashes_by_key[idempotency_key] != request_hash {
            raise ValueError("idempotency_conflict");
        }
        return mock.jobs_by_key[idempotency_key];
    }

    descriptor: WorkloadDescriptor = load_workload_descriptor(mock.workload_dir);
    vectors: dict[str, list[float]] = {};
    start: int = 0;
    while start < len(items) {
        stop: int = min(start + mock.chunk_size, len(items));
        chunk: list[EmbeddingItem] = items[start:stop];
        mock.invocation_count += 1;
        output: dict[str, any] = invoke_workload(mock.workload_dir, chunk);
        chunk_ids: list[str] = [item.item_id for item in chunk];
        chunk_vectors: dict[str, list[float]] = validate_workload_result(
            output, chunk_ids, descriptor,
        );
        for item_id in chunk_ids {
            vectors[item_id] = chunk_vectors[item_id];
        }
        start = stop;
    }
    if list(vectors.keys()) != expected_ids {
        raise ValueError("partial_embedding_result");
    }
    key_hash: str = hashlib.sha256(idempotency_key.encode()).hexdigest();
    result = EmbeddingBatchResult(
        job_id="mock_job_" + key_hash[:12],
        workload_version=descriptor.workload_version,
        artifact_sha256=descriptor.artifact_sha256,
        states=["queued", "running", "verifying", "complete"],
        vectors=vectors,
        item_count=len(items),
        result_sha256=canonical_result_hash(expected_ids, vectors, descriptor),
    );
    mock.jobs_by_key[idempotency_key] = result;
    mock.request_hashes_by_key[idempotency_key] = request_hash;
    return result;
}
