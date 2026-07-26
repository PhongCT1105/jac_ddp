"""Stateful in-process façade for the frozen Stage 1 operations."""

import hashlib;
import json;
import os;
import from src.adapters.fixtures { fixture_profiles }
import from src.adapters.mock_jacgrid { MockJacGrid, submit_embeddings }
import from src.contracts.models {
    Actor,
    CandidateReference,
    CardSnapshot,
    EmbeddingRetrievalEvidence,
    EmbeddingBatchResult,
    EmbeddingItem,
    InterestDecision,
    InterestResult,
    MatchRecord,
    MessageRecord,
    PairAssessment,
    ProfileRevision,
    Suggestion,
    ThreadRecord,
    ThreadView
}
import from src.core.lifecycle {
    InMemoryLifecycle,
    list_messages,
    record_interest as lifecycle_record_interest,
    send_message as lifecycle_send_message
}
import from src.intelligence.cards {
    fixture_assessment,
    fixture_suggestion,
    unordered_pair_id
}
import from src.intelligence.retrieval { rank_candidates }


obj FixtureProfileBoundary {
    has profiles: list[ProfileRevision];

    def all_profiles -> list[ProfileRevision] {
        return [profile for profile in self.profiles];
    }
}


obj FixtureComputeBoundary {
    has mock: MockJacGrid;

    def embed(
        items: list[EmbeddingItem], idempotency_key: str
    ) -> EmbeddingBatchResult {
        return submit_embeddings(self.mock, items, idempotency_key);
    }
}


obj FixtureIntelligenceBoundary {
    def next_suggestion(
        viewer: ProfileRevision,
        profiles: list[ProfileRevision],
        vectors: dict[str, list[float]],
        current_request: str | None,
    ) -> Suggestion {
        candidates: list[CandidateReference] = rank_candidates(
            viewer, profiles, vectors
        );
        if len(candidates) == 0 {
            raise ValueError("no_eligible_candidate");
        }
        subject: ProfileRevision = profile_by_id(profiles, candidates[0].actor_id);
        assessment: PairAssessment = fixture_assessment(viewer, subject);
        suggestion: Suggestion = fixture_suggestion(viewer, subject, assessment);
        if current_request is None {
            return suggestion;
        }
        card = CardSnapshot(
            card_id=suggestion.card.card_id,
            pair_id=suggestion.card.pair_id,
            viewer_id=suggestion.card.viewer_id,
            subject_id=suggestion.card.subject_id,
            subject_revision_id=suggestion.card.subject_revision_id,
            headline=suggestion.card.headline,
            reasons=suggestion.card.reasons + ["Current request: " + current_request],
        );
        return Suggestion(
            suggestion_id=suggestion.suggestion_id,
            pair_id=suggestion.pair_id,
            viewer_id=suggestion.viewer_id,
            subject_id=suggestion.subject_id,
            card=card,
            state=suggestion.state,
        );
    }
}


obj DemoDependencies {
    has profiles: FixtureProfileBoundary,
        compute: FixtureComputeBoundary,
        intelligence: FixtureIntelligenceBoundary;
}


obj DemoApp {
    has dependencies: DemoDependencies,
        lifecycle: InMemoryLifecycle = InMemoryLifecycle(),
        suggestions_by_id: dict[str, Suggestion] = {},
        active_suggestion_by_viewer: dict[str, str] = {},
        request_fingerprints: dict[str, str] = {},
        request_results: dict[str, Suggestion] = {},
        interest_fingerprints: dict[str, str] = {},
        interest_results: dict[str, InterestResult] = {},
        message_fingerprints: dict[str, str] = {},
        message_results: dict[str, MessageRecord] = {};
}


def default_workload_dir -> str {
    return os.path.abspath(
        os.path.join(
            os.path.dirname(__file__), "../../../../workloads/connection-embedding"
        )
    );
}


def new_demo_app -> DemoApp {
    return DemoApp(
        dependencies=DemoDependencies(
            profiles=FixtureProfileBoundary(profiles=fixture_profiles()),
            compute=FixtureComputeBoundary(
                mock=MockJacGrid(workload_dir=default_workload_dir(), chunk_size=10)
            ),
            intelligence=FixtureIntelligenceBoundary(),
        )
    );
}


def reset_demo(_: DemoApp) -> DemoApp {
    return new_demo_app();
}


def operation_key(operation: str, actor_id: str, idempotency_key: str) -> str {
    return operation + "|" + actor_id + "|" + idempotency_key;
}


def fingerprint(values: dict[str, str | None]) -> str {
    encoded: str = json.dumps(values, sort_keys=True, separators=(",", ":"));
    return hashlib.sha256(encoded.encode()).hexdigest();
}


def profile_by_id(profiles: list[ProfileRevision], actor_id: str) -> ProfileRevision {
    for profile in profiles {
        if profile.actor_id == actor_id {
            return profile;
        }
    }
    raise ValueError("profile_not_found");
}


def authorized_profile(app: DemoApp, actor: Actor) -> ProfileRevision {
    try {
        return profile_by_id(app.dependencies.profiles.all_profiles(), actor.actor_id);
    } except ValueError {
        raise ValueError("profile_not_found");
    }
}


def clone_actor(profile: ProfileRevision) -> Actor {
    return Actor(
        actor_id=profile.actor_id, display_name=profile.display_name, fixture=True
    );
}


def clone_profile(profile: ProfileRevision) -> ProfileRevision {
    return ProfileRevision(
        actor_id=profile.actor_id,
        display_name=profile.display_name,
        revision_id=profile.revision_id,
        markdown=profile.markdown,
        eligible=profile.eligible,
        blocked_actor_ids=[item for item in profile.blocked_actor_ids],
    );
}


def clone_suggestion(suggestion: Suggestion) -> Suggestion {
    card = CardSnapshot(
        card_id=suggestion.card.card_id,
        pair_id=suggestion.card.pair_id,
        viewer_id=suggestion.card.viewer_id,
        subject_id=suggestion.card.subject_id,
        subject_revision_id=suggestion.card.subject_revision_id,
        headline=suggestion.card.headline,
        reasons=[reason for reason in suggestion.card.reasons],
    );
    evidence: EmbeddingRetrievalEvidence | None = None;
    if suggestion.embedding_evidence is not None {
        evidence = EmbeddingRetrievalEvidence(
            embedding_states=[
                state for state in suggestion.embedding_evidence.embedding_states
            ],
            submitted_item_count=suggestion.embedding_evidence.submitted_item_count,
            recombined_result_count=suggestion.embedding_evidence.recombined_result_count,
            eligible_candidate_count=suggestion.embedding_evidence.eligible_candidate_count,
        );
    }
    return Suggestion(
        suggestion_id=suggestion.suggestion_id,
        pair_id=suggestion.pair_id,
        viewer_id=suggestion.viewer_id,
        subject_id=suggestion.subject_id,
        card=card,
        state=suggestion.state,
        embedding_evidence=evidence,
    );
}


def clone_match(match_record: MatchRecord | None) -> MatchRecord | None {
    if match_record is None {
        return None;
    }
    return MatchRecord(
        match_id=match_record.match_id,
        pair_id=match_record.pair_id,
        left_actor_id=match_record.left_actor_id,
        right_actor_id=match_record.right_actor_id,
        thread_id=match_record.thread_id,
    );
}


def clone_decision(decision: InterestDecision) -> InterestDecision {
    return InterestDecision(
        decision_id=decision.decision_id,
        pair_id=decision.pair_id,
        viewer_id=decision.viewer_id,
        subject_id=decision.subject_id,
        kind=decision.kind,
        idempotency_key=decision.idempotency_key,
    );
}


def clone_interest_result(result: InterestResult) -> InterestResult {
    return InterestResult(
        decision=clone_decision(result.decision), match=clone_match(result.match)
    );
}


def clone_message(message: MessageRecord) -> MessageRecord {
    return MessageRecord(
        message_id=message.message_id,
        thread_id=message.thread_id,
        sender_id=message.sender_id,
        body=message.body,
        idempotency_key=message.idempotency_key,
    );
}


def select_fixture_actor(app: DemoApp, actor_id: str) -> Actor {
    try {
        return clone_actor(
            profile_by_id(app.dependencies.profiles.all_profiles(), actor_id)
        );
    } except ValueError {
        raise ValueError("fixture_actor_not_found");
    }
}


def get_profile(app: DemoApp, actor: Actor) -> ProfileRevision {
    return clone_profile(authorized_profile(app, actor));
}


def eligible_profiles_for(
    app: DemoApp, viewer: ProfileRevision,
) -> list[ProfileRevision] {
    profiles: list[ProfileRevision] = [];
    for profile in app.dependencies.profiles.all_profiles() {
        if not profile.eligible or profile.actor_id == viewer.actor_id {
            continue;
        }
        if profile.actor_id in viewer.blocked_actor_ids
        or viewer.actor_id in profile.blocked_actor_ids {
            continue;
        }
        profiles.append(profile);
    }
    return [viewer] + profiles;
}


def request_next_suggestion(
    app: DemoApp, actor: Actor, current_request: str | None, idempotency_key: str,
) -> Suggestion {
    viewer: ProfileRevision = authorized_profile(app, actor);
    if len(idempotency_key) == 0 {
        raise ValueError("invalid_request");
    }
    key: str = operation_key("suggestion", viewer.actor_id, idempotency_key);
    request_fingerprint: str = fingerprint(
        {"actor_id": viewer.actor_id, "current_request": current_request}
    );
    if key in app.request_fingerprints {
        if app.request_fingerprints[key] != request_fingerprint {
            raise ValueError("idempotency_conflict");
        }
        return clone_suggestion(app.request_results[key]);
    }
    if viewer.actor_id in app.active_suggestion_by_viewer {
        raise ValueError("suggestion_not_active");
    }
    pool: list[ProfileRevision] = eligible_profiles_for(app, viewer);
    items: list[EmbeddingItem] = [
        EmbeddingItem(item_id=profile.revision_id, text=profile.markdown)
        for profile in pool
    ];
    embedding: EmbeddingBatchResult = app.dependencies.compute.embed(
        items, key + "|embedding",
    );
    suggestion: Suggestion = app.dependencies.intelligence.next_suggestion(
        viewer, pool, embedding.vectors, current_request,
    );
    subject: ProfileRevision = profile_by_id(pool, suggestion.subject_id);
    if suggestion.viewer_id != viewer.actor_id
    or suggestion.subject_id == viewer.actor_id
    or not subject.eligible
    or suggestion.pair_id != unordered_pair_id(viewer.actor_id, subject.actor_id)
    or suggestion.card.viewer_id != viewer.actor_id
    or suggestion.card.subject_id != subject.actor_id
    or suggestion.card.subject_revision_id != subject.revision_id
    or suggestion.card.pair_id != suggestion.pair_id {
        raise ValueError("internal_error");
    }
    evidence = EmbeddingRetrievalEvidence(
        embedding_states=[state for state in embedding.states],
        submitted_item_count=len(items),
        recombined_result_count=embedding.item_count,
        eligible_candidate_count=len(pool) - 1,
    );
    suggestion.embedding_evidence = evidence;
    stored: Suggestion = clone_suggestion(suggestion);
    app.suggestions_by_id[stored.suggestion_id] = stored;
    app.active_suggestion_by_viewer[viewer.actor_id] = stored.suggestion_id;
    app.request_fingerprints[key] = request_fingerprint;
    app.request_results[key] = stored;
    return clone_suggestion(stored);
}


def record_interest(
    app: DemoApp, actor: Actor, suggestion_id: str, kind: str, idempotency_key: str,
) -> InterestResult {
    viewer: ProfileRevision = authorized_profile(app, actor);
    if len(idempotency_key) == 0 or kind not in ["open", "pass"] {
        raise ValueError("invalid_request");
    }
    key: str = operation_key("interest", viewer.actor_id, idempotency_key);
    input_fingerprint: str = fingerprint(
        {"actor_id": viewer.actor_id, "suggestion_id": suggestion_id, "kind": kind}
    );
    if key in app.interest_fingerprints {
        if app.interest_fingerprints[key] != input_fingerprint {
            raise ValueError("idempotency_conflict");
        }
        return clone_interest_result(app.interest_results[key]);
    }
    suggestion = app.suggestions_by_id.get(suggestion_id);
    if suggestion is None or suggestion.viewer_id != viewer.actor_id {
        raise ValueError("suggestion_not_active");
    }
    if suggestion.state != "active" {
        raise ValueError("interest_already_recorded");
    }
    if app.active_suggestion_by_viewer.get(viewer.actor_id) != suggestion_id {
        raise ValueError("suggestion_not_active");
    }
    match_record: MatchRecord | None = lifecycle_record_interest(
        app.lifecycle,
        suggestion,
        kind,
        idempotency_key,
        idempotency_scope="interest|" + viewer.actor_id + "|",
    );
    decision = app.lifecycle.decisions_by_viewer_pair.get(
        viewer.actor_id + "|" + suggestion.pair_id
    );
    if decision is None {
        raise ValueError("internal_error");
    }
    suggestion.state = "open" if kind == "open" else "passed";
    del app.active_suggestion_by_viewer[viewer.actor_id];
    result = InterestResult(
        decision=clone_decision(decision), match=clone_match(match_record)
    );
    app.interest_fingerprints[key] = input_fingerprint;
    app.interest_results[key] = result;
    return clone_interest_result(result);
}


def safe_thread(app: DemoApp, actor: Actor, thread_id: str) -> ThreadRecord {
    _ = authorized_profile(app, actor);
    thread = app.lifecycle.threads_by_id.get(thread_id);
    if thread is None or actor.actor_id not in thread.participant_ids {
        raise PermissionError("thread_forbidden");
    }
    return thread;
}


def load_thread(app: DemoApp, actor: Actor, thread_id: str) -> ThreadView {
    thread: ThreadRecord = safe_thread(app, actor, thread_id);
    messages: list[MessageRecord] = list_messages(
        app.lifecycle, thread_id, actor.actor_id
    );
    copied_thread = ThreadRecord(
        thread_id=thread.thread_id,
        match_id=thread.match_id,
        participant_ids=[participant for participant in thread.participant_ids],
    );
    return ThreadView(
        thread=copied_thread, messages=[clone_message(message) for message in messages],
    );
}


def send_message(
    app: DemoApp, actor: Actor, thread_id: str, body: str, idempotency_key: str,
) -> MessageRecord {
    _ = safe_thread(app, actor, thread_id);
    if len(idempotency_key) == 0 or len(body.strip()) == 0 {
        raise ValueError("invalid_request");
    }
    key: str = operation_key("message", actor.actor_id, idempotency_key);
    input_fingerprint: str = fingerprint(
        {"actor_id": actor.actor_id, "thread_id": thread_id, "body": body}
    );
    if key in app.message_fingerprints {
        if app.message_fingerprints[key] != input_fingerprint {
            raise ValueError("idempotency_conflict");
        }
        return clone_message(app.message_results[key]);
    }
    message: MessageRecord = lifecycle_send_message(
        app.lifecycle,
        thread_id,
        actor.actor_id,
        body,
        idempotency_key,
        idempotency_scope="message|" + actor.actor_id + "|",
    );
    stored: MessageRecord = clone_message(message);
    app.message_fingerprints[key] = input_fingerprint;
    app.message_results[key] = stored;
    return clone_message(stored);
}
