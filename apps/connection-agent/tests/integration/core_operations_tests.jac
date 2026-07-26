import from src.contracts.models { InterestResult, MessageRecord, Suggestion }
import from src.core.demo_app {
    get_profile,
    load_thread,
    new_demo_app,
    record_interest,
    request_next_suggestion,
    reset_demo,
    select_fixture_actor,
    send_message
}


def expect_value_error(callable: Callable, code: str) {
    try {
        callable();
        assert False , "expected safe operation error";
    } except ValueError as error {
        assert str(error) == code;
    }
}


test "frozen facade operations complete the private fixture journey" {
    app = new_demo_app();
    alice = select_fixture_actor(app, "alice_builder");
    bob = select_fixture_actor(app, "bob_researcher");
    carol = select_fixture_actor(app, "carol_designer");
    profile = get_profile(app, alice);
    assert profile.actor_id == alice.actor_id;
    alice_card: Suggestion = request_next_suggestion(
        app, alice, "technical collaborators", "a-suggest"
    );
    assert alice_card.viewer_id == alice.actor_id;
    assert alice_card.subject_id == bob.actor_id;
    assert alice_card.card.viewer_id == alice.actor_id;
    first: InterestResult = record_interest(
        app, alice, alice_card.suggestion_id, "open", "a-open"
    );
    assert first.match is None;
    bob_card: Suggestion = request_next_suggestion(app, bob, None, "b-suggest");
    assert bob_card.subject_id == alice.actor_id;
    assert bob_card.card.card_id != alice_card.card.card_id;
    second: InterestResult = record_interest(
        app, bob, bob_card.suggestion_id, "open", "b-open"
    );
    assert second.match is not None;
    matched_record = second.match;
    message: MessageRecord = send_message(
        app, alice, matched_record.thread_id, "Hello Bob", "a-message"
    );
    thread_view = load_thread(app, bob, matched_record.thread_id);
    assert thread_view.thread.thread_id == matched_record.thread_id;
    assert len(thread_view.messages) == 1;
    assert thread_view.messages[0].message_id == message.message_id;
    try {
        _ = load_thread(app, carol, matched_record.thread_id);
        assert False , "Carol must not read the private thread";
    } except PermissionError as error {
        assert str(error) == "thread_forbidden";
    }
    try {
        _ = send_message(
            app, carol, matched_record.thread_id, "I should not be here", "c-message"
        );
        assert False , "Carol must not write the private thread";
    } except PermissionError as error {
        assert str(error) == "thread_forbidden";
    }
}


test "facade retries preserve original results and scope keys" {
    app = new_demo_app();
    alice = select_fixture_actor(app, "alice_builder");
    bob = select_fixture_actor(app, "bob_researcher");
    alice_card = request_next_suggestion(app, alice, None, "shared-key");
    assert request_next_suggestion(app, alice, None, "shared-key").suggestion_id == alice_card.suggestion_id;
    bob_card = request_next_suggestion(app, bob, None, "shared-key");
    assert bob_card.viewer_id == bob.actor_id;
    first = record_interest(
        app, alice, alice_card.suggestion_id, "open", "shared-open"
    );
    assert first.match is None;
    second = record_interest(app, bob, bob_card.suggestion_id, "open", "shared-open");
    assert second.match is not None;
    assert record_interest(
        app, alice, alice_card.suggestion_id, "open", "shared-open"
    ).match is None;
    matched_record = second.match;
    first_message = send_message(
        app, alice, matched_record.thread_id, "Hello", "shared-message"
    );
    assert send_message(
        app, alice, matched_record.thread_id, "Hello", "shared-message"
    ).message_id == first_message.message_id;
    _ = send_message(app, bob, matched_record.thread_id, "Hi", "shared-message");
    assert len(load_thread(app, alice, matched_record.thread_id).messages) == 2;
    expect_value_error(
        lambda { request_next_suggestion(app, alice, "changed", "shared-key"); },
        "idempotency_conflict",
    );
    expect_value_error(
        lambda { record_interest(
            app, alice, alice_card.suggestion_id, "pass", "shared-open"
        ); },
        "idempotency_conflict",
    );
    expect_value_error(
        lambda { send_message(
            app, alice, matched_record.thread_id, "Changed", "shared-message"
        ); },
        "idempotency_conflict",
    );
}


test "facade rejects forged inactive and non-disclosing resources" {
    app = new_demo_app();
    alice = select_fixture_actor(app, "alice_builder");
    bob = select_fixture_actor(app, "bob_researcher");
    expect_value_error(
        lambda { request_next_suggestion(app, alice, None, ""); }, "invalid_request"
    );
    alice_card = request_next_suggestion(app, alice, None, "a-suggest");
    expect_value_error(
        lambda { record_interest(
            app, bob, alice_card.suggestion_id, "open", "b-forged"
        ); },
        "suggestion_not_active",
    );
    expect_value_error(
        lambda { record_interest(app, alice, "unknown", "open", "a-unknown"); },
        "suggestion_not_active",
    );
    _ = record_interest(app, alice, alice_card.suggestion_id, "pass", "a-pass");
    expect_value_error(
        lambda { record_interest(
            app, alice, alice_card.suggestion_id, "open", "a-second"
        ); },
        "interest_already_recorded",
    );
    for actor in [alice, bob] {
        try {
            _ = load_thread(app, actor, "thread_does_not_exist");
            assert False , "missing threads must not disclose existence";
        } except PermissionError as error {
            assert str(error) == "thread_forbidden";
        }
    }
    try {
        _ = send_message(
            app, alice, "thread_does_not_exist", "No leak", "missing-thread"
        );
        assert False , "missing threads must not disclose existence on write";
    } except PermissionError as error {
        assert str(error) == "thread_forbidden";
    }
}


test "reset creates clean deterministic state" {
    app = new_demo_app();
    alice = select_fixture_actor(app, "alice_builder");
    first = request_next_suggestion(app, alice, None, "suggest");
    _ = record_interest(app, alice, first.suggestion_id, "open", "open");
    reset = reset_demo(app);
    reset_alice = select_fixture_actor(reset, "alice_builder");
    again = request_next_suggestion(reset, reset_alice, None, "suggest");
    assert again.suggestion_id == first.suggestion_id;
    assert len(reset.lifecycle.decisions_by_viewer_pair) == 0;
    assert len(reset.lifecycle.threads_by_id) == 0;
}
