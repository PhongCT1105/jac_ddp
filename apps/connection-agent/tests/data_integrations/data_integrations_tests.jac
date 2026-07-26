import from src.adapters.fixtures { FixtureSource }
import from src.adapters.mock_jacgrid {
    MockJacGrid,
    invoke_workload,
    load_workload_descriptor,
    submit_embeddings,
    validate_workload_result,
}
import from src.contracts.models { Actor, EmbeddingItem }


def workload_dir -> str {
    return "../../workloads/connection-embedding";
}


def valid_output(item_ids: list[str]) -> dict[str, any] {
    return {
        "contract_version": 1,
        "model": {
            "id": "fixture-token-hash",
            "revision": "fixture-token-hash-v1",
            "artifact_sha256": "sha256:d681e8a394df13cc28fb809dc5a1f66f4b66310bb42e259adb9a344d87fcc070",

        },
        "dimensions": 16,
        "normalized": True,
        "results": [
            {"id": item_id, "embedding": [1.0] + [0.0 for _index in range(15)]}
            for item_id in item_ids
        ],

    };
}


test "fixture selection only returns the selected approved actor profile" {
    source = FixtureSource();
    alice = source.select_fixture_actor("alice_builder");
    profile = source.get_selected_profile(alice);
    assert alice.fixture;
    assert profile.actor_id == "alice_builder";
    try {
        _ = source.get_selected_profile(
            Actor(
                actor_id="bob_researcher", display_name="Bob Researcher", fixture=True,
            )
        );
        assert False , "another fixture must not be available through Alice selection";
    } except ValueError as error {
        assert str(error) == "fixture_actor_not_found";
    }
}


test "unknown and nonfixture actors fail safely" {
    source = FixtureSource();
    try {
        _ = source.select_fixture_actor("not_a_fixture");
        assert False , "unknown fixture must fail";
    } except ValueError as error {
        assert str(error) == "fixture_actor_not_found";
    }
    _ = source.select_fixture_actor("alice_builder");
    try {
        _ = source.get_selected_profile(
            Actor(
                actor_id="alice_builder", display_name="Alice Builder", fixture=False,
            )
        );
        assert False , "nonfixture actor must fail";
    } except ValueError as error {
        assert str(error) == "fixture_actor_not_found";
    }
}


test "fixture profile reads isolate same and separate sources" {
    source = FixtureSource();
    alice = source.select_fixture_actor("alice_builder");
    first = source.get_selected_profile(alice);
    first.markdown = "mutated";
    first.blocked_actor_ids.append("someone");
    second = source.get_selected_profile(alice);
    other_source = FixtureSource();
    other_alice = other_source.select_fixture_actor("alice_builder");
    third = other_source.get_selected_profile(other_alice);
    assert second.markdown != "mutated";
    assert len(second.blocked_actor_ids) == 0;
    assert third.markdown == second.markdown;
    assert len(third.blocked_actor_ids) == 0;
}


test "mock jacgrid invokes every chunk and returns complete manifest-pinned result" {
    mock = MockJacGrid(workload_dir=workload_dir(), chunk_size=2);
    items: list[EmbeddingItem] = [
        EmbeddingItem(item_id="revision_a", text="builder climbing"),
        EmbeddingItem(item_id="revision_b", text="researcher mentoring"),
        EmbeddingItem(item_id="revision_c", text="designer tools"),

    ];
    result = submit_embeddings(mock, items, "data-integrations-complete-v1");
    assert mock.invocation_count == 2;
    assert result.states == ["queued", "running", "verifying", "complete"];
    assert list(result.vectors.keys()) == ["revision_a", "revision_b", "revision_c"];
    assert result.workload_version == "0.1.0";
    assert result.artifact_sha256 == "sha256:d681e8a394df13cc28fb809dc5a1f66f4b66310bb42e259adb9a344d87fcc070";
    assert result.result_sha256.startswith("sha256:");
}


test "validator rejects ordered identity and numeric boundary violations" {
    descriptor = load_workload_descriptor(workload_dir());
    output = valid_output(["revision_a"]);
    output["results"] = [];
    try {
        _ = validate_workload_result(output, ["revision_a"], descriptor);
        assert False , "partial output must fail";
    } except ValueError as error {
        assert str(error) == "partial_embedding_result";
    }
    output = valid_output(["revision_a", "revision_b"]);
    try {
        _ = validate_workload_result(output, ["revision_a"], descriptor);
        assert False , "extra output must fail";
    } except ValueError as error {
        assert str(error) == "partial_embedding_result";
    }
    output = valid_output(["revision_a", "revision_b"]);
    output["results"] = output["results"][::-1];
    try {
        _ = validate_workload_result(output, ["revision_a", "revision_b"], descriptor);
        assert False , "reordered output must fail";
    } except ValueError as error {
        assert str(error) == "invalid_result_order";
    }
    output = valid_output(["revision_a"]);
    output["model"]["revision"] = "wrong";
    try {
        _ = validate_workload_result(output, ["revision_a"], descriptor);
        assert False , "model mismatch must fail";
    } except ValueError as error {
        assert str(error) == "workload_identity_mismatch";
    }
    output = valid_output(["revision_a"]);
    output["results"][0]["embedding"] = [1.0];
    try {
        _ = validate_workload_result(output, ["revision_a"], descriptor);
        assert False , "wrong vector dimensions must fail";
    } except ValueError as error {
        assert str(error) == "wrong_vector_dimension";
    }
    output = valid_output(["revision_a"]);
    output["results"][0]["embedding"][0] = True;
    try {
        _ = validate_workload_result(output, ["revision_a"], descriptor);
        assert False , "boolean embedding component must fail";
    } except ValueError as error {
        assert str(error) == "invalid_vector_value";
    }
    output = valid_output(["revision_a"]);
    output["results"][0]["embedding"][0] = float("nan");
    try {
        _ = validate_workload_result(output, ["revision_a"], descriptor);
        assert False , "nonfinite embedding component must fail";
    } except ValueError as error {
        assert str(error) == "invalid_vector_value";
    }
    output = valid_output(["revision_a"]);
    output["results"][0]["embedding"][0] = 2.0;
    try {
        _ = validate_workload_result(output, ["revision_a"], descriptor);
        assert False , "unnormalized vector must fail";
    } except ValueError as error {
        assert str(error) == "invalid_vector_normalization";
    }
}


test "invalid chunk configuration and workload process failures are safe" {
    mock = MockJacGrid(workload_dir=workload_dir(), chunk_size=0);
    try {
        _ = submit_embeddings(
            mock, [EmbeddingItem(item_id="revision_a", text="text")], "bad-chunk-v1"
        );
        assert False , "zero chunk size must fail";
    } except ValueError as error {
        assert str(error) == "invalid_chunk_size";
    }
    mock = MockJacGrid(workload_dir=workload_dir());
    try {
        _ = submit_embeddings(
            mock, [EmbeddingItem(item_id="revision_a", text="text")], ""
        );
        assert False , "blank idempotency key must fail";
    } except ValueError as error {
        assert str(error) == "invalid_request";
    }
    try {
        _ = invoke_workload(
            "/not-a-connection-agent-workload",
            [EmbeddingItem(item_id="safe_id", text="safe text"), ]
        );
        assert False , "missing workload must fail";
    } except RuntimeError as error {
        assert str(error) == "embedding_failed";
    }
}
