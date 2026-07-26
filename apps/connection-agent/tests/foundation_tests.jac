import from src.adapters.fixtures { find_profile, fixture_profiles }
import from src.adapters.mock_jacgrid { MockJacGrid, submit_embeddings }
import from src.contracts.models { EmbeddingItem, MatchRecord }
import from src.core.lifecycle {
    InMemoryLifecycle,
    list_messages,
    record_interest,
    send_message,
}
import from src.demo { run_walking_skeleton }
import from src.intelligence.cards { fixture_assessment, fixture_suggestion }


test "walking skeleton completes the full private flow" {
    summary = run_walking_skeleton();
    assert summary.profile_count == 31;
    assert summary.candidate_count == 30;
    assert summary.selected_actor_id == "bob_researcher";
    assert not summary.first_open_created_match;
    assert summary.visible_message_count == 1;
}


test "one open remains private and creates no match" {
    profiles = fixture_profiles();
    alice = find_profile(profiles, "alice_builder");
    bob = find_profile(profiles, "bob_researcher");
    assessment = fixture_assessment(alice, bob);
    alice_suggestion = fixture_suggestion(alice, bob, assessment);
    lifecycle = InMemoryLifecycle();
    created_match = record_interest(
        lifecycle, alice_suggestion, "open", "one-sided-open"
    );
    assert created_match is None;
    assert len(lifecycle.matches_by_pair) == 0;
    assert len(lifecycle.threads_by_id) == 0;
}


test "a pass does not create a match" {
    profiles = fixture_profiles();
    alice = find_profile(profiles, "alice_builder");
    bob = find_profile(profiles, "bob_researcher");
    assessment = fixture_assessment(alice, bob);
    alice_suggestion = fixture_suggestion(alice, bob, assessment);
    bob_suggestion = fixture_suggestion(bob, alice, assessment);
    lifecycle = InMemoryLifecycle();
    assert record_interest(lifecycle, alice_suggestion, "open", "alice-opens") is None;
    assert record_interest(lifecycle, bob_suggestion, "pass", "bob-passes") is None;
    assert len(lifecycle.matches_by_pair) == 0;
}


test "third actor cannot read a private thread" {
    profiles = fixture_profiles();
    alice = find_profile(profiles, "alice_builder");
    bob = find_profile(profiles, "bob_researcher");
    assessment = fixture_assessment(alice, bob);
    alice_suggestion = fixture_suggestion(alice, bob, assessment);
    bob_suggestion = fixture_suggestion(bob, alice, assessment);
    lifecycle = InMemoryLifecycle();
    _ = record_interest(lifecycle, alice_suggestion, "open", "alice-open");
    created_match = record_interest(lifecycle, bob_suggestion, "open", "bob-open");
    assert created_match is not None;
    accepted_match: MatchRecord = created_match as MatchRecord;
    try {
        _ = list_messages(lifecycle, accepted_match.thread_id, "carol_designer");
        assert False , "third actor should not read the thread";
    } except PermissionError as error {
        assert str(error) == "thread_forbidden";
    }
}


test "compute idempotency key rejects changed input" {
    mock = MockJacGrid(workload_dir="../../workloads/connection-embedding");
    first_items: list[EmbeddingItem] = [
        EmbeddingItem(item_id="revision_01", text="builder climbing")
    ];
    changed_items: list[EmbeddingItem] = [
        EmbeddingItem(item_id="revision_01", text="different approved profile")
    ];
    _ = submit_embeddings(mock, first_items, "same-compute-key");
    try {
        _ = submit_embeddings(mock, changed_items, "same-compute-key");
        assert False , "changed input must conflict";
    } except ValueError as error {
        assert str(error) == "idempotency_conflict";
    }
}


test "message idempotency key rejects changed input" {
    profiles = fixture_profiles();
    alice = find_profile(profiles, "alice_builder");
    bob = find_profile(profiles, "bob_researcher");
    assessment = fixture_assessment(alice, bob);
    lifecycle = InMemoryLifecycle();
    _ = record_interest(
        lifecycle,
        fixture_suggestion(alice, bob, assessment),
        "open",
        "alice-message-setup-open",
    );
    created_match = record_interest(
        lifecycle,
        fixture_suggestion(bob, alice, assessment),
        "open",
        "bob-message-setup-open",
    );
    accepted_match: MatchRecord = created_match as MatchRecord;
    _ = send_message(
        lifecycle,
        accepted_match.thread_id,
        alice.actor_id,
        "Original body",
        "same-message-key",
    );
    try {
        _ = send_message(
            lifecycle,
            accepted_match.thread_id,
            alice.actor_id,
            "Changed body",
            "same-message-key",
        );
        assert False , "changed message must conflict";
    } except ValueError as error {
        assert str(error) == "idempotency_conflict";
    }
}
