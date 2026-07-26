"""Provider adapter that invokes the real workload package locally."""

import hashlib;
import json;
import os;
import subprocess;
import from src.contracts.models { EmbeddingBatchResult, EmbeddingItem }


obj MockJacGrid {
    has workload_dir: str,
        chunk_size: int = 10,
        invocation_count: int = 0,
        jobs_by_key: dict[str, EmbeddingBatchResult] = {},
        request_hashes_by_key: dict[str, str] = {};
}


def invoke_workload(workload_dir: str, items: list[EmbeddingItem]) -> dict[str, any] {
    payload: dict[str, any] = {
        "contract_version": 1,
        "items": [{"id": item.item_id, "text": item.text} for item in items],

    };
    completed = subprocess.run(
        ["jac", "run", "src/main.jac"],
        cwd=workload_dir,
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=False,
    );
    if completed.returncode != 0 {
        raise RuntimeError("workload_failed:" + completed.stderr.strip());
    }
    return json.loads(completed.stdout) as dict[str, any];
}


def submit_embeddings(
    mock: MockJacGrid, items: list[EmbeddingItem], idempotency_key: str,
) -> EmbeddingBatchResult {
    canonical_items: list[dict[str, str]] = [
        {"id": item.item_id, "text": item.text} for item in items
    ];
    request_hash: str = hashlib.sha256(
        json.dumps(canonical_items, sort_keys=True).encode()
    ).hexdigest();
    if idempotency_key in mock.jobs_by_key {
        if mock.request_hashes_by_key[idempotency_key] != request_hash {
            raise ValueError("idempotency_conflict");
        }
        return mock.jobs_by_key[idempotency_key];
    }
    if len(items) == 0 {
        raise ValueError("invalid_items");
    }

    expected_ids: list[str] = [item.item_id for item in items];
    if len(set(expected_ids)) != len(expected_ids) {
        raise ValueError("duplicate_item_id");
    }

    vectors: dict[str, list[float]] = {};
    raw_outputs: list[str] = [];
    start: int = 0;
    while start < len(items) {
        stop: int = min(start + mock.chunk_size, len(items));
        mock.invocation_count += 1;
        output: dict[str, any] = invoke_workload(mock.workload_dir, items[start:stop]);
        if output.get("contract_version") != 1
        or output.get("dimensions") != 16
        or output.get("normalized") is not True {
            raise ValueError("malformed_workload_result");
        }
        raw_results = output.get("results");
        if not isinstance(raw_results, list) {
            raise ValueError("malformed_workload_result");
        }
        raw_outputs.append(json.dumps(output, sort_keys=True));
        for raw_result in raw_results {
            if not isinstance(raw_result, dict) {
                raise ValueError("malformed_workload_result");
            }
            item_id_value = raw_result.get("id");
            embedding_value = raw_result.get("embedding");
            if not isinstance(item_id_value, str)
            or not isinstance(embedding_value, list) {
                raise ValueError("malformed_workload_result");
            }
            item_id: str = item_id_value as str;
            if item_id in vectors {
                raise ValueError("duplicate_result_id");
            }
            vector: list[float] = embedding_value as list[float];
            if len(vector) != 16 {
                raise ValueError("wrong_vector_dimension");
            }
            vectors[item_id] = vector;
        }
        start = stop;
    }

    if set(vectors.keys()) != set(expected_ids) {
        raise ValueError("partial_embedding_result");
    }

    key_hash: str = hashlib.sha256(idempotency_key.encode()).hexdigest();
    result_hash: str = hashlib.sha256("".join(raw_outputs).encode()).hexdigest();
    result = EmbeddingBatchResult(
        job_id="mock_job_" + key_hash[:12],
        workload_version="0.1.0",
        artifact_sha256="sha256:d681e8a394df13cc28fb809dc5a1f66f4b66310bb42e259adb9a344d87fcc070",
        states=["queued", "running", "verifying", "complete"],
        vectors=vectors,
        item_count=len(items),
        result_sha256="sha256:" + result_hash,
    );
    mock.jobs_by_key[idempotency_key] = result;
    mock.request_hashes_by_key[idempotency_key] = request_hash;
    return result;
}
