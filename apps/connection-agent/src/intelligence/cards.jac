"""Deterministic contract-valid assessment and card fixtures."""

import from src.contracts.models {
    CardSnapshot,
    PairAssessment,
    ProfileRevision,
    Suggestion
}


def unordered_pair_id(left_actor_id: str, right_actor_id: str) -> str {
    if left_actor_id < right_actor_id {
        return left_actor_id + "__" + right_actor_id;
    }
    return right_actor_id + "__" + left_actor_id;
}


def fixture_assessment(
    left: ProfileRevision, right: ProfileRevision
) -> PairAssessment {
    pair_id: str = unordered_pair_id(left.actor_id, right.actor_id);
    return PairAssessment(
        pair_id=pair_id,
        left_actor_id=left.actor_id,
        right_actor_id=right.actor_id,
        reciprocal_score=0.92,
        evidence=[
            "Shared interest in thoughtful technical collaboration",
            "Shared interest in climbing and mentoring"
        ],
    );
}


def fixture_suggestion(
    viewer: ProfileRevision, subject: ProfileRevision, assessment: PairAssessment,
) -> Suggestion {
    card = CardSnapshot(
        card_id="card_" + viewer.actor_id + "__" + subject.actor_id,
        pair_id=assessment.pair_id,
        viewer_id=viewer.actor_id,
        subject_id=subject.actor_id,
        subject_revision_id=subject.revision_id,
        headline=f"{subject.display_name} could be a thoughtful connection for {viewer.display_name}",
        reasons=assessment.evidence,
    );
    return Suggestion(
        suggestion_id="suggestion_" + viewer.actor_id + "__" + subject.actor_id,
        pair_id=assessment.pair_id,
        viewer_id=viewer.actor_id,
        subject_id=subject.actor_id,
        card=card,
        state="active",
    );
}
