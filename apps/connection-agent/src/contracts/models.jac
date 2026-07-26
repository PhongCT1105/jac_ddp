"""Released Connection Agent internal contract V1."""

enum EmbeddingState: str {
    QUEUED = "queued",
    RUNNING = "running",
    VERIFYING = "verifying",
    COMPLETE = "complete",
    FAILED = "failed",
}

enum SuggestionState: str {
    QUEUED = "queued",
    ACTIVE = "active",
    OPEN = "open",
    PASSED = "passed",
    SKIPPED = "skipped",
    EXPIRED = "expired",
    INVALIDATED = "invalidated",
}

enum InterestKind: str { OPEN = "open", PASS = "pass", }

obj Actor {
    has actor_id: str,
        display_name: str,
        fixture: bool;
}

obj ProfileRevision {
    has actor_id: str,
        display_name: str,
        revision_id: str,
        markdown: str,
        eligible: bool = True,
        blocked_actor_ids: list[str] = [];
}

obj EmbeddingItem {
    has item_id: str,
        text: str;
}

obj EmbeddingBatchResult {
    has job_id: str,
        workload_version: str,
        artifact_sha256: str,
        states: list[str],
        vectors: dict[str, list[float]],
        item_count: int,
        result_sha256: str;
}

obj CandidateReference {
    has actor_id: str,
        profile_revision_id: str,
        score: float;
}

obj PairAssessment {
    has pair_id: str,
        left_actor_id: str,
        right_actor_id: str,
        reciprocal_score: float,
        evidence: list[str];
}

obj CardSnapshot {
    has card_id: str,
        pair_id: str,
        viewer_id: str,
        subject_id: str,
        subject_revision_id: str,
        headline: str,
        reasons: list[str];
}

obj Suggestion {
    has suggestion_id: str,
        pair_id: str,
        viewer_id: str,
        subject_id: str,
        card: CardSnapshot,
        state: str;
}

obj InterestDecision {
    has decision_id: str,
        pair_id: str,
        viewer_id: str,
        subject_id: str,
        kind: str,
        idempotency_key: str;
}

obj MatchRecord {
    has match_id: str,
        pair_id: str,
        left_actor_id: str,
        right_actor_id: str,
        thread_id: str;
}

obj ThreadRecord {
    has thread_id: str,
        match_id: str,
        participant_ids: list[str];
}

obj MessageRecord {
    has message_id: str,
        thread_id: str,
        sender_id: str,
        body: str,
        idempotency_key: str;
}

obj AppError {
    has code: str,
        message: str,
        retryable: bool;
}

obj DemoSummary {
    has profile_count: int,
        candidate_count: int,
        embedding_job_id: str,
        embedding_states: list[str],
        selected_actor_id: str,
        first_open_created_match: bool,
        match_id: str,
        thread_id: str,
        message_id: str,
        visible_message_count: int;
}
