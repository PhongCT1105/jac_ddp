"""Deterministic black-box evaluation for the Stage 1 product journey."""

import sys;
import from src.contracts.models {
    EmbeddingRetrievalEvidence,
    InterestResult,
    MatchRecord,
    MessageRecord,
    Suggestion,
    ThreadView
}
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


glob SCENARIO_ID: str = "stage1-reciprocal-private-v1",
     FIXTURE_IDS: str = "alice_builder,bob_researcher,carol_designer";


obj EvaluationReport {
    has scenario_id: str,
        passed: bool,
        passed_invariants: list[str],
        failed_invariant: str | None;

    def render -> str {
        lines: list[str] = [];
        for invariant in self.passed_invariants {
            lines.append("PASS " + invariant);
        }
        if self.failed_invariant is not None {
            lines.append("FAIL " + self.failed_invariant);
        }
        status: str = "passed" if self.passed else "failed";
        lines.append(
            "SUMMARY scenario=" + self.scenario_id + " status=" + status + " fixtures=" + FIXTURE_IDS
        );
        return "\n".join(lines);
    }
}


def require_invariant(condition: bool, invariant: str) {
    if not condition {
        raise AssertionError(invariant);
    }
}


def expect_value_error(callable: Callable, code: str) -> bool {
    try {
        callable();
    } except ValueError as error {
        return str(error) == code;
    } except Exception {
        return False;
    }
    return False;
}


def expect_thread_forbidden(callable: Callable) -> bool {
    try {
        callable();
    } except PermissionError as error {
        return str(error) == "thread_forbidden";
    } except Exception {
        return False;
    }
    return False;
}


def evaluate_stage1(simulated_failure: str | None = None) -> EvaluationReport {
    passed: list[str] = [];
    current: str = "isolated_reset";
    try {
        if simulated_failure is not None {
            raise RuntimeError(simulated_failure);
        }

        app = reset_demo(new_demo_app());
        alice = select_fixture_actor(app, "alice_builder");
        bob = select_fixture_actor(app, "bob_researcher");
        carol = select_fixture_actor(app, "carol_designer");
        require_invariant(get_profile(app, alice).actor_id == alice.actor_id, current);
        require_invariant(
            expect_value_error(
                lambda { select_fixture_actor(app, "unknown_fixture"); },
                "fixture_actor_not_found",
            ),
            current,
        );
        passed.append(current);

        current = "whole_pool_recombined_before_retrieval";
        shared_key: str = SCENARIO_ID + "-shared";
        alice_card: Suggestion = request_next_suggestion(
            app, alice, "technical collaborators", shared_key
        );
        require_invariant(alice_card.viewer_id == alice.actor_id, current);
        require_invariant(alice_card.subject_id == bob.actor_id, current);
        require_invariant(
            request_next_suggestion(
                app, alice, "technical collaborators", shared_key
            ).suggestion_id == alice_card.suggestion_id,
            current,
        );
        require_invariant(alice_card.embedding_evidence is not None, current);
        evidence = alice_card.embedding_evidence as EmbeddingRetrievalEvidence;
        require_invariant(evidence.submitted_item_count == 31, current);
        require_invariant(evidence.recombined_result_count == 31, current);
        require_invariant(evidence.eligible_candidate_count == 30, current);
        require_invariant(
            evidence.embedding_states == ["queued", "running", "verifying", "complete"],
            current,
        );
        passed.append(current);

        current = "alice_open_remains_private";
        first_open: InterestResult = record_interest(
            app, alice, alice_card.suggestion_id, "open", shared_key
        );
        require_invariant(first_open.match is None, current);
        passed.append(current);

        current = "bob_receives_distinct_viewer_card";
        bob_card: Suggestion = request_next_suggestion(app, bob, None, shared_key);
        control_app = new_demo_app();
        control_bob = select_fixture_actor(control_app, "bob_researcher");
        control_bob_card: Suggestion = request_next_suggestion(
            control_app, control_bob, None, shared_key
        );
        require_invariant(bob_card.viewer_id == bob.actor_id, current);
        require_invariant(bob_card.subject_id == alice.actor_id, current);
        require_invariant(bob_card.card.card_id != alice_card.card.card_id, current);
        require_invariant(bob_card.card.viewer_id == bob.actor_id, current);
        require_invariant(
            bob_card.card.card_id == control_bob_card.card.card_id, current
        );
        require_invariant(
            bob_card.card.headline == control_bob_card.card.headline, current
        );
        require_invariant(
            bob_card.card.reasons == control_bob_card.card.reasons, current
        );
        passed.append(current);

        current = "one_canonical_match_and_thread";
        reciprocal: InterestResult = record_interest(
            app, bob, bob_card.suggestion_id, "open", shared_key
        );
        require_invariant(reciprocal.match is not None, current);
        match_record: MatchRecord = reciprocal.match as MatchRecord;
        require_invariant(match_record.pair_id == alice_card.pair_id, current);
        require_invariant(match_record.pair_id == bob_card.pair_id, current);
        require_invariant(
            set([match_record.left_actor_id, match_record.right_actor_id]) == set(
                [alice.actor_id, bob.actor_id]
            ),
            current,
        );
        repeated_reciprocal: InterestResult = record_interest(
            app, bob, bob_card.suggestion_id, "open", shared_key
        );
        require_invariant(repeated_reciprocal.match is not None, current);
        repeated_match: MatchRecord = repeated_reciprocal.match as MatchRecord;
        require_invariant(repeated_match.match_id == match_record.match_id, current);
        require_invariant(repeated_match.thread_id == match_record.thread_id, current);
        alice_thread: ThreadView = load_thread(app, alice, match_record.thread_id);
        require_invariant(
            alice_thread.thread.match_id == match_record.match_id, current
        );
        require_invariant(
            alice_thread.thread.thread_id == match_record.thread_id, current
        );
        passed.append(current);

        current = "stale_alice_retry_does_not_reveal_match";
        repeated_first: InterestResult = record_interest(
            app, alice, alice_card.suggestion_id, "open", shared_key
        );
        require_invariant(repeated_first.match is None, current);
        require_invariant(
            expect_value_error(
                lambda { record_interest(
                    app, alice, alice_card.suggestion_id, "open", shared_key + "-new",
                ); },
                "interest_already_recorded",
            ),
            current,
        );
        passed.append(current);

        current = "one_idempotent_message_delivered";
        message: MessageRecord = send_message(
            app, alice, match_record.thread_id, "Hello Bob", shared_key
        );
        repeated_message: MessageRecord = send_message(
            app, alice, match_record.thread_id, "Hello Bob", shared_key
        );
        require_invariant(repeated_message.message_id == message.message_id, current);
        bob_thread: ThreadView = load_thread(app, bob, match_record.thread_id);
        require_invariant(len(bob_thread.messages) == 1, current);
        require_invariant(
            bob_thread.messages[0].message_id == message.message_id, current
        );
        passed.append(current);

        current = "idempotency_conflicts_are_scoped_and_safe";
        require_invariant(
            expect_value_error(
                lambda { request_next_suggestion(
                    app, alice, "changed request", shared_key
                ); },
                "idempotency_conflict",
            ),
            current,
        );
        require_invariant(
            expect_value_error(
                lambda { send_message(
                    app, alice, match_record.thread_id, "Changed", shared_key
                ); },
                "idempotency_conflict",
            ),
            current,
        );
        passed.append(current);

        current = "carol_and_missing_threads_are_non_disclosing";
        require_invariant(
            expect_thread_forbidden(
                lambda { load_thread(app, carol, match_record.thread_id); }
            ),
            current,
        );
        require_invariant(
            expect_thread_forbidden(
                lambda { send_message(
                    app, carol, match_record.thread_id, "unauthorized", shared_key,
                ); }
            ),
            current,
        );
        require_invariant(
            expect_thread_forbidden(
                lambda { load_thread(app, alice, "thread_missing"); }
            ),
            current,
        );
        require_invariant(
            expect_thread_forbidden(
                lambda { send_message(
                    app, alice, "thread_missing", "not sent", shared_key
                ); }
            ),
            current,
        );
        require_invariant(
            expect_thread_forbidden(
                lambda { load_thread(app, bob, "thread_missing"); }
            ),
            current,
        );
        require_invariant(
            expect_thread_forbidden(
                lambda { send_message(
                    app, bob, "thread_missing", "not sent", shared_key
                ); }
            ),
            current,
        );
        passed.append(current);

        current = "reset_and_parallel_runs_are_isolated";
        parallel_app = new_demo_app();
        parallel_alice = select_fixture_actor(parallel_app, "alice_builder");
        parallel_card: Suggestion = request_next_suggestion(
            parallel_app, parallel_alice, None, shared_key
        );
        reset_app = reset_demo(app);
        reset_alice = select_fixture_actor(reset_app, "alice_builder");
        _ = request_next_suggestion(reset_app, reset_alice, None, shared_key);
        require_invariant(
            expect_thread_forbidden(
                lambda { load_thread(reset_app, reset_alice, match_record.thread_id); }
            ),
            current,
        );
        require_invariant(
            request_next_suggestion(
                parallel_app, parallel_alice, None, shared_key
            ).suggestion_id == parallel_card.suggestion_id,
            current,
        );
        require_invariant(
            expect_thread_forbidden(
                lambda { load_thread(
                    parallel_app, parallel_alice, match_record.thread_id
                ); }
            ),
            current,
        );
        passed.append(current);
    } except Exception {
        return EvaluationReport(
            scenario_id=SCENARIO_ID,
            passed=False,
            passed_invariants=[name for name in passed],
            failed_invariant=current,
        );
    }
    return EvaluationReport(
        scenario_id=SCENARIO_ID,
        passed=True,
        passed_invariants=[name for name in passed],
        failed_invariant=None,
    );
}


with entry:__main__ {
    evaluation_result: EvaluationReport = evaluate_stage1();
    print(evaluation_result.render());
    if not evaluation_result.passed {
        sys.exit(1);
    }
}
