"""Client-safe JSON serialization over the released Stage 1 DemoApp façade."""

import from src.contracts.models {
    Actor,
    InterestDecision,
    InterestResult,
    MatchRecord,
    MessageRecord,
    ProfileRevision,
    Suggestion,
    ThreadRecord,
    ThreadView
}
import from src.core.demo_app {
    DemoApp,
    get_profile as core_get_profile,
    load_thread as core_load_thread,
    new_demo_app,
    record_interest as core_record_interest,
    request_next_suggestion as core_request_next_suggestion,
    reset_demo as core_reset_demo,
    select_fixture_actor as core_select_fixture_actor,
    send_message as core_send_message
}


obj FixtureRuntime {
    has app: DemoApp;
}


glob _runtime: FixtureRuntime = FixtureRuntime(app=new_demo_app());


def _actor(actor_wire: dict) -> Actor {
    actor_id = actor_wire.get("actor_id");
    if not isinstance(actor_id, str) {
        raise ValueError("fixture_actor_not_found");
    }
    return core_select_fixture_actor(_runtime.app, actor_id);
}


def _actor_wire(actor: Actor) -> dict {
    return {
        "actor_id": actor.actor_id,
        "display_name": actor.display_name,
        "fixture": actor.fixture,

    };
}


def _profile_wire(profile: ProfileRevision) -> dict {
    return {
        "actor_id": profile.actor_id,
        "display_name": profile.display_name,
        "revision_id": profile.revision_id,
        "markdown": profile.markdown,
        "eligible": profile.eligible,
        "blocked_actor_ids": profile.blocked_actor_ids,

    };
}


def _suggestion_wire(suggestion: Suggestion) -> dict {
    evidence: dict | None = None;
    if suggestion.embedding_evidence is not None {
        evidence = {
            "embedding_states": suggestion.embedding_evidence.embedding_states,
            "submitted_item_count": suggestion.embedding_evidence.submitted_item_count,
            "recombined_result_count": suggestion.embedding_evidence.recombined_result_count,
            "eligible_candidate_count": suggestion.embedding_evidence.eligible_candidate_count,

        };
    }
    return {
        "suggestion_id": suggestion.suggestion_id,
        "pair_id": suggestion.pair_id,
        "viewer_id": suggestion.viewer_id,
        "subject_id": suggestion.subject_id,
        "card": {
            "card_id": suggestion.card.card_id,
            "pair_id": suggestion.card.pair_id,
            "viewer_id": suggestion.card.viewer_id,
            "subject_id": suggestion.card.subject_id,
            "subject_revision_id": suggestion.card.subject_revision_id,
            "headline": suggestion.card.headline,
            "reasons": suggestion.card.reasons,

        },
        "state": suggestion.state,
        "embedding_evidence": evidence,

    };
}


def _decision_wire(decision: InterestDecision) -> dict {
    return {
        "decision_id": decision.decision_id,
        "pair_id": decision.pair_id,
        "viewer_id": decision.viewer_id,
        "subject_id": decision.subject_id,
        "kind": decision.kind,
        "idempotency_key": decision.idempotency_key,

    };
}


def _match_wire(match_record: MatchRecord | None) -> dict | None {
    if match_record is None {
        return None;
    }
    return {
        "match_id": match_record.match_id,
        "pair_id": match_record.pair_id,
        "left_actor_id": match_record.left_actor_id,
        "right_actor_id": match_record.right_actor_id,
        "thread_id": match_record.thread_id,

    };
}


def _interest_wire(result: InterestResult) -> dict {
    return {
        "decision": _decision_wire(result.decision),
        "match": _match_wire(result.match),

    };
}


def _thread_wire(thread: ThreadRecord) -> dict {
    return {
        "thread_id": thread.thread_id,
        "match_id": thread.match_id,
        "participant_ids": thread.participant_ids,

    };
}


def _message_wire(message: MessageRecord) -> dict {
    return {
        "message_id": message.message_id,
        "thread_id": message.thread_id,
        "sender_id": message.sender_id,
        "body": message.body,
        "idempotency_key": message.idempotency_key,

    };
}


def _thread_view_wire(view: ThreadView) -> dict {
    return {
        "thread": _thread_wire(view.thread),
        "messages": [_message_wire(message) for message in view.messages],

    };
}


def:pub reset_demo -> dict {
    _runtime.app = core_reset_demo(_runtime.app);
    return {"ok": True};
}


def:pub select_fixture_actor(actor_id: str) -> dict {
    return _actor_wire(core_select_fixture_actor(_runtime.app, actor_id));
}


def:pub get_profile(actor: dict) -> dict {
    return _profile_wire(core_get_profile(_runtime.app, _actor(actor)));
}


def:pub request_next_suggestion(
    actor: dict, current_request: str | None, idempotency_key: str
) -> dict {
    suggestion = core_request_next_suggestion(
        _runtime.app, _actor(actor), current_request, idempotency_key
    );
    return _suggestion_wire(suggestion);
}


def:pub record_interest(
    actor: dict, suggestion_id: str, kind: str, idempotency_key: str
) -> dict {
    result = core_record_interest(
        _runtime.app, _actor(actor), suggestion_id, kind, idempotency_key
    );
    return _interest_wire(result);
}


def:pub load_thread(actor: dict, thread_id: str) -> dict {
    return _thread_view_wire(core_load_thread(_runtime.app, _actor(actor), thread_id));
}


def:pub send_message(
    actor: dict, thread_id: str, body: str, idempotency_key: str
) -> dict {
    message = core_send_message(
        _runtime.app, _actor(actor), thread_id, body, idempotency_key
    );
    return _message_wire(message);
}
