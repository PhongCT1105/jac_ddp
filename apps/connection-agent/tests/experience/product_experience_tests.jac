import from web.fixture {
    get_profile,
    load_thread,
    record_interest,
    request_next_suggestion,
    reset_demo,
    select_fixture_actor,
    send_message
}

test "client wire preserves typed shapes and Core operation semantics" {
    reset_demo();
    alice = select_fixture_actor("alice_builder");
    bob = select_fixture_actor("bob_researcher");
    assert get_profile(alice)["revision_id"] == "profile_revision_alice_01";
    assert get_profile(alice)["markdown"].startswith("Software builder");
    alice_card = request_next_suggestion(alice, None, "suggest-alice_builder");
    assert request_next_suggestion(alice, None, "suggest-alice_builder")[
        "suggestion_id"
    ] == alice_card["suggestion_id"];
    try {
        request_next_suggestion(alice, "changed request", "suggest-alice_builder");
        assert False;
    } except ValueError as e {
        assert str(e) == "idempotency_conflict";
    }
    bob_card = request_next_suggestion(bob, None, "suggest-bob_researcher");
    assert alice_card["card"]["card_id"] != bob_card["card"]["card_id"];
    assert alice_card["viewer_id"] == "alice_builder";
    assert alice_card["card"]["subject_revision_id"] == "profile_revision_bob_01";
    first = record_interest(
        alice, alice_card["suggestion_id"], "open", "decision-alice_builder"
    );
    assert first["match"] is None;
    assert record_interest(
        alice, alice_card["suggestion_id"], "open", "decision-alice_builder"
    )["match"] is None;
    second = record_interest(
        bob, bob_card["suggestion_id"], "open", "decision-bob_researcher"
    );
    thread_id = "thread_alice_builder__bob_researcher";
    assert second["match"]["thread_id"] == thread_id;
    assert record_interest(
        alice, alice_card["suggestion_id"], "open", "decision-alice_builder"
    )["match"] is None;
    message = send_message(alice, thread_id, "Hi Bob", "message-alice_builder-1");
    assert message["message_id"] == "message_1";
    assert send_message(alice, thread_id, "Hi Bob", "message-alice_builder-1")[
        "message_id"
    ] == message["message_id"];
    assert load_thread(alice, thread_id)["thread"]["participant_ids"] == [
        "alice_builder",
        "bob_researcher"
    ];
    try {
        load_thread(select_fixture_actor("carol_designer"), thread_id);
        assert False;
    } except PermissionError as e {
        assert str(e) == "thread_forbidden";
    }
    reset_demo();
    try {
        load_thread(alice, "thread_unknown");
        assert False;
    } except PermissionError as e {
        assert str(e) == "thread_forbidden";
    }
    reset_bob = select_fixture_actor("bob_researcher");
    reset_card = request_next_suggestion(reset_bob, None, "suggest-reset-bob");
    assert record_interest(
        reset_bob, reset_card["suggestion_id"], "open", "decision-reset-bob"
    )["match"] is None;
}
