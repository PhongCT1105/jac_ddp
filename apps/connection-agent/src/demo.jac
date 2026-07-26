"""Foundation walking skeleton composed through released operations."""

import os;
import from src.adapters.fixtures { find_profile, fixture_profiles }
import from src.adapters.mock_jacgrid { MockJacGrid, submit_embeddings }
import from src.contracts.models {
    CandidateReference,
    DemoSummary,
    EmbeddingBatchResult,
    EmbeddingItem,
    MatchRecord,
    MessageRecord,
    ProfileRevision,
}
import from src.core.lifecycle {
    InMemoryLifecycle,
    list_messages,
    record_interest,
    send_message
}
import from src.intelligence.cards { fixture_assessment, fixture_suggestion }
import from src.intelligence.retrieval { rank_candidates }


def default_workload_dir() -> str {
    return os.path.abspath(
        os.path.join(
            os.path.dirname(__file__), "../../../workloads/connection-embedding"
        )
    );
}


def run_walking_skeleton(verbose: bool = False) -> DemoSummary {
    profiles: list[ProfileRevision] = fixture_profiles();
    assert len(profiles) == 31;

    items: list[EmbeddingItem] = [
        EmbeddingItem(item_id=profile.revision_id, text=profile.markdown)
        for profile in profiles
    ];
    mock = MockJacGrid(workload_dir=default_workload_dir(), chunk_size=10);
    embedding_result: EmbeddingBatchResult = submit_embeddings(
        mock, items, "foundation-embedding-job-v1",
    );
    duplicate_result: EmbeddingBatchResult = submit_embeddings(
        mock, items, "foundation-embedding-job-v1",
    );
    assert duplicate_result.job_id == embedding_result.job_id;
    assert embedding_result.item_count == 31;
    assert mock.invocation_count == 4;

    alice: ProfileRevision = find_profile(profiles, "alice_builder");
    candidates: list[CandidateReference] = rank_candidates(
        alice, profiles, embedding_result.vectors
    );
    assert len(candidates) == 30;
    assert candidates[0].actor_id == "bob_researcher";
    bob: ProfileRevision = find_profile(profiles, candidates[0].actor_id);

    assessment = fixture_assessment(alice, bob);
    alice_suggestion = fixture_suggestion(alice, bob, assessment);
    bob_suggestion = fixture_suggestion(bob, alice, assessment);
    assert alice_suggestion.card.card_id != bob_suggestion.card.card_id;

    lifecycle = InMemoryLifecycle();
    first_match = record_interest(lifecycle, alice_suggestion, "open", "alice-open-v1");
    assert first_match is None;
    created_match = record_interest(lifecycle, bob_suggestion, "open", "bob-open-v1");
    assert created_match is not None;
    accepted_match: MatchRecord = created_match as MatchRecord;
    duplicate_match = record_interest(lifecycle, bob_suggestion, "open", "bob-open-v1");
    assert duplicate_match is not None;
    assert (duplicate_match as MatchRecord).match_id == accepted_match.match_id;
    assert len(lifecycle.matches_by_pair) == 1;
    assert len(lifecycle.threads_by_id) == 1;

    message: MessageRecord = send_message(
        lifecycle,
        accepted_match.thread_id,
        alice.actor_id,
        "Hi Bob — I would enjoy comparing distributed systems notes.",
        "alice-message-v1",
    );
    duplicate_message: MessageRecord = send_message(
        lifecycle,
        accepted_match.thread_id,
        alice.actor_id,
        "Hi Bob — I would enjoy comparing distributed systems notes.",
        "alice-message-v1",
    );
    assert duplicate_message.message_id == message.message_id;
    visible_messages = list_messages(lifecycle, accepted_match.thread_id, bob.actor_id);
    assert len(visible_messages) == 1;

    try {
        _ = list_messages(lifecycle, accepted_match.thread_id, "carol_designer");
        assert False , "third-party thread access must fail";
    } except PermissionError as error {
        assert str(error) == "thread_forbidden";
    }

    summary = DemoSummary(
        profile_count=len(profiles),
        candidate_count=len(candidates),
        embedding_job_id=embedding_result.job_id,
        embedding_states=embedding_result.states,
        selected_actor_id=bob.actor_id,
        first_open_created_match=False,
        match_id=accepted_match.match_id,
        thread_id=accepted_match.thread_id,
        message_id=message.message_id,
        visible_message_count=len(visible_messages),
    );

    if verbose {
        print("Connection Agent mock walking skeleton");
        print(f"Profiles embedded: {summary.profile_count} in chunks of 10");
        print(f"Job lifecycle: {' -> '.join(summary.embedding_states)}");
        print(f"Candidates ranked across complete pool: {summary.candidate_count}");
        print(f"Selected fixture: {summary.selected_actor_id}");
        print("Alice opened privately: no match yet");
        print(f"Bob opened independently: {summary.match_id}");
        print(f"Private thread: {summary.thread_id}");
        print(f"One idempotent message: {summary.message_id}");
    }
    return summary;
}
