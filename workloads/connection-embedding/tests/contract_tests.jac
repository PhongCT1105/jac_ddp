import json;
import from src.embedding { embed_payload }


test "manifest and schemas are valid JSON" {
    with open("workload.json", "r") as manifest_file {
        manifest = json.load(manifest_file) as dict[str, any];
    }
    assert manifest["contract_version"] == 1;
    assert manifest["id"] == "connection-embedding";
    assert manifest["version"] == "0.1.0";
    assert manifest["model"]["revision"] == "fixture-token-hash-v1";

    with open("schemas/input.schema.json", "r") as input_schema_file {
        input_schema = json.load(input_schema_file) as dict[str, any];
    }
    with open("schemas/output.schema.json", "r") as output_schema_file {
        output_schema = json.load(output_schema_file) as dict[str, any];
    }
    assert input_schema["properties"]["contract_version"]["const"] == 1;
    assert output_schema["properties"]["dimensions"]["const"] == 16;
}


test "valid fixture executes through workload contract" {
    with open("fixtures/valid/two-items.json", "r") as fixture_file {
        payload = json.load(fixture_file) as dict[str, any];
    }
    output: dict[str, any] = embed_payload(payload);
    results = output["results"] as list[dict[str, any]];
    assert len(results) == 2;
    assert len(results[0]["embedding"] as list[float]) == 16;
    assert len(results[1]["embedding"] as list[float]) == 16;
}


test "invalid fixture fails with declared code" {
    with open("fixtures/invalid/duplicate-id.json", "r") as fixture_file {
        fixture = json.load(fixture_file) as dict[str, any];
    }
    expected_error: str = fixture["expected_error"] as str;
    payload = fixture["input"] as dict[str, any];
    try {
        _ = embed_payload(payload);
        assert False , "invalid fixture must fail";
    } except ValueError as error {
        assert str(error) == expected_error;
    }
}
