import from src.embedding { DIMENSIONS, embed_payload, embed_text }


test "embedding is deterministic and normalized" {
    first: list[float] = embed_text("builder climbing distributed systems");
    second: list[float] = embed_text("builder climbing distributed systems");
    assert first == second;
    assert len(first) == DIMENSIONS;
    norm: float = sum([value * value for value in first]) ** 0.5;
    assert abs(norm - 1.0) < 0.000001;
}


test "shared tokens are more similar than unrelated text" {
    alice: list[float] = embed_text(
        "builder climbing distributed systems collaboration"
    );
    bob: list[float] = embed_text(
        "researcher climbing distributed systems collaboration builder"
    );
    unrelated: list[float] = embed_text("ceramics poetry gardening culinary history");
    alice_bob: float = sum([alice[index] * bob[index] for index in range(DIMENSIONS)]);
    alice_unrelated: float = sum(
        [alice[index] * unrelated[index] for index in range(DIMENSIONS)]
    );
    assert alice_bob > alice_unrelated;
}


test "payload preserves every input identifier" {
    output: dict[str, any] = embed_payload(
        {
            "contract_version": 1,
            "items": [
                {"id": "revision_01", "text": "builder climbing"},
                {"id": "revision_02", "text": "designer community"},

            ],

        }
    );
    results = output["results"] as list[dict[str, any]];
    assert len(results) == 2;
    assert results[0]["id"] == "revision_01";
    assert results[1]["id"] == "revision_02";
}


test "duplicate identifiers fail" {
    try {
        _ = embed_payload(
            {
                "contract_version": 1,
                "items": [
                    {"id": "duplicate", "text": "one"},
                    {"id": "duplicate", "text": "two"},

                ],

            }
        );
        assert False , "duplicate identifiers must fail";
    } except ValueError as error {
        assert str(error) == "duplicate_item_id";
    }
}
