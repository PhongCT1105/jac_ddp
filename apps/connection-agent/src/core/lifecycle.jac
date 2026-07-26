"""Transport-independent consent, match, thread, and message lifecycle."""

import from src.contracts.models {
    InterestDecision,
    MatchRecord,
    MessageRecord,
    Suggestion,
    ThreadRecord
}


obj InMemoryLifecycle {
    has decisions_by_key: dict[str, InterestDecision] = {},
        decisions_by_viewer_pair: dict[str, InterestDecision] = {},
        matches_by_pair: dict[str, MatchRecord] = {},
        threads_by_id: dict[str, ThreadRecord] = {},
        messages_by_thread: dict[str, list[MessageRecord]] = {},
        messages_by_key: dict[str, MessageRecord] = {};
}


def decision_lookup_key(viewer_id: str, pair_id: str) -> str {
    return viewer_id + "|" + pair_id;
}


def record_interest(
    state: InMemoryLifecycle,
    suggestion: Suggestion,
    kind: str,
    idempotency_key: str,
    idempotency_scope: str = "",
) -> MatchRecord | None {
    if kind not in ["open", "pass"] {
        raise ValueError("invalid_interest_kind");
    }
    storage_key: str = idempotency_scope + idempotency_key;
    if storage_key in state.decisions_by_key {
        prior_decision: InterestDecision = state.decisions_by_key[storage_key];
        if prior_decision.pair_id != suggestion.pair_id
        or prior_decision.viewer_id != suggestion.viewer_id
        or prior_decision.subject_id != suggestion.subject_id
        or prior_decision.kind != kind {
            raise ValueError("idempotency_conflict");
        }
        return state.matches_by_pair.get(suggestion.pair_id);
    }

    viewer_pair_key: str = decision_lookup_key(
        suggestion.viewer_id, suggestion.pair_id
    );
    if viewer_pair_key in state.decisions_by_viewer_pair {
        raise ValueError("interest_already_recorded");
    }

    decision = InterestDecision(
        decision_id="decision_" + suggestion.viewer_id + "__" + suggestion.subject_id,
        pair_id=suggestion.pair_id,
        viewer_id=suggestion.viewer_id,
        subject_id=suggestion.subject_id,
        kind=kind,
        idempotency_key=idempotency_key,
    );
    state.decisions_by_key[storage_key] = decision;
    state.decisions_by_viewer_pair[viewer_pair_key] = decision;

    if kind != "open" {
        return None;
    }

    reverse_key: str = decision_lookup_key(suggestion.subject_id, suggestion.pair_id);
    reverse = state.decisions_by_viewer_pair.get(reverse_key);
    if reverse is None or reverse.kind != "open" {
        return None;
    }
    if suggestion.pair_id in state.matches_by_pair {
        return state.matches_by_pair[suggestion.pair_id];
    }

    participant_ids: list[str] = sorted([suggestion.viewer_id, suggestion.subject_id]);
    match_id: str = "match_" + suggestion.pair_id;
    thread_id: str = "thread_" + suggestion.pair_id;
    match_record = MatchRecord(
        match_id=match_id,
        pair_id=suggestion.pair_id,
        left_actor_id=participant_ids[0],
        right_actor_id=participant_ids[1],
        thread_id=thread_id,
    );
    thread = ThreadRecord(
        thread_id=thread_id, match_id=match_id, participant_ids=participant_ids,
    );
    state.matches_by_pair[suggestion.pair_id] = match_record;
    state.threads_by_id[thread_id] = thread;
    state.messages_by_thread[thread_id] = [];
    return match_record;
}


def send_message(
    state: InMemoryLifecycle,
    thread_id: str,
    sender_id: str,
    body: str,
    idempotency_key: str,
    idempotency_scope: str = "",
) -> MessageRecord {
    storage_key: str = idempotency_scope + idempotency_key;
    if storage_key in state.messages_by_key {
        prior_message: MessageRecord = state.messages_by_key[storage_key];
        if prior_message.thread_id != thread_id
        or prior_message.sender_id != sender_id
        or prior_message.body != body {
            raise ValueError("idempotency_conflict");
        }
        return prior_message;
    }
    thread = state.threads_by_id.get(thread_id);
    if thread is None {
        raise ValueError("thread_not_found");
    }
    if sender_id not in thread.participant_ids {
        raise PermissionError("thread_forbidden");
    }
    if len(body.strip()) == 0 {
        raise ValueError("empty_message");
    }
    message = MessageRecord(
        message_id=f"message_{len(state.messages_by_thread[thread_id]) + 1}",
        thread_id=thread_id,
        sender_id=sender_id,
        body=body,
        idempotency_key=idempotency_key,
    );
    state.messages_by_thread[thread_id].append(message);
    state.messages_by_key[storage_key] = message;
    return message;
}


def list_messages(
    state: InMemoryLifecycle, thread_id: str, actor_id: str,
) -> list[MessageRecord] {
    thread = state.threads_by_id.get(thread_id);
    if thread is None {
        raise ValueError("thread_not_found");
    }
    if actor_id not in thread.participant_ids {
        raise PermissionError("thread_forbidden");
    }
    return state.messages_by_thread[thread_id];
}
