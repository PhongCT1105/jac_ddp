import json;
import from src.embed { EMBED_DIM, RUNTIME_FALLBACK, RUNTIME_PRIMARY, run_task }


test "manifest and schemas describe the released 384-dimensional workload" {
    with open("workload.json", "r") as manifest_file {
        manifest = json.load(manifest_file) as dict[str, any];
    }
    assert manifest["name"] == "connection-embedding";
    assert manifest["version"] == "1.0.0";
    assert manifest["entrypoint"] == "src/embed.jac";
    assert manifest["model"]["embedding_dim"] == EMBED_DIM;
    assert manifest["runtime_tags"] == [RUNTIME_PRIMARY, RUNTIME_FALLBACK];

    with open("schemas/input.schema.json", "r") as input_schema_file {
        input_schema = json.load(input_schema_file) as dict[str, any];
    }
    with open("schemas/output.schema.json", "r") as output_schema_file {
        output_schema = json.load(output_schema_file) as dict[str, any];
    }
    required_fields = input_schema["required"] as list[str];
    assert "payload" in required_fields;
    assert output_schema["properties"]["results"]["items"]["properties"]["embedding"][
        "minItems"
    ] == EMBED_DIM;
}


test "released fixture executes through the workload contract" {
    with open("tests/fixtures/task-embedding.json", "r") as fixture_file {
        task = json.load(fixture_file) as dict[str, any];
    }
    result: dict[str, any] = run_task(task);
    assert result["status"] == "ok";
    assert result["error"] is None;
    results = result["output"]["results"] as list[dict[str, any]];
    assert len(results) == 3;
    assert len(results[0]["embedding"] as list[float]) == EMBED_DIM;
    assert result["execution"]["runtime"] in [RUNTIME_PRIMARY, RUNTIME_FALLBACK];
}


test "invalid item fails with a safe workload error" {
    result: dict[str, any] = run_task(
        {
            "task_id": "invalid-item",
            "job_type": "embedding",
            "payload": {"items": [{"id": "missing-text"}]},

        }
    );
    assert result["status"] == "error";
    assert result["error"]["code"] == "invalid_item";
}
