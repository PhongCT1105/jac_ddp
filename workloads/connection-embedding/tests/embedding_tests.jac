import math;
import from src.embed { EMBED_DIM, _hash_embed, run_task }


test "fallback embedding is deterministic and normalized" {
    first: list[float] = _hash_embed(
        "builder climbing distributed systems collaboration"
    );
    second: list[float] = _hash_embed(
        "builder climbing distributed systems collaboration"
    );
    assert first == second;
    assert len(first) == EMBED_DIM;
    norm: float = math.sqrt(sum([value * value for value in first]));
    assert abs(norm - 1.0) < 0.000001;
}


test "workload preserves every input identifier" {
    result: dict[str, any] = run_task(
        {
            "task_id": "preserve-identifiers",
            "job_type": "embedding",
            "payload": {
                "items": [
                    {"id": "revision_01", "text": "builder climbing"},
                    {"id": "revision_02", "text": "designer community"},

                ]
            },

        }
    );
    results = result["output"]["results"] as list[dict[str, any]];
    assert len(results) == 2;
    assert results[0]["id"] == "revision_01";
    assert results[1]["id"] == "revision_02";
}
