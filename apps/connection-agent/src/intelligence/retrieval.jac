"""Deterministic whole-pool retrieval over verified embedding projections."""

import hashlib;
import from src.contracts.models {
    CandidateReference,
    EmbeddingBatchResult,
    EmbeddingItem,
    ProfileRevision
}

glob WORKLOAD_VERSION: str = "0.1.0";
glob WORKLOAD_ARTIFACT_SHA256: str = (
         "sha256:d681e8a394df13cc28fb809dc5a1f66f4b66310bb42e259adb9a344d87fcc070"
     );


def cosine_similarity(left: list[float], right: list[float]) -> float {
    if len(left) != len(right) or len(left) == 0 {
        raise ValueError("incompatible_vectors");
    }
    return sum([left[index] * right[index] for index in range(len(left))]);
}


def actor_is_blocked(viewer: ProfileRevision, subject: ProfileRevision) -> bool {
    for blocked_id in viewer.blocked_actor_ids {
        if blocked_id == subject.actor_id {
            return True;
        }
    }
    for blocked_id in subject.blocked_actor_ids {
        if blocked_id == viewer.actor_id {
            return True;
        }
    }
    return False;
}


def eligible_profiles(
    viewer: ProfileRevision, profiles: list[ProfileRevision],
) -> list[ProfileRevision] {
    return [
        profile
        for profile in profiles
        if profile.actor_id != viewer.actor_id
        and profile.eligible
        and not actor_is_blocked(viewer, profile)
    ];
}


def request_embedding_item(
    viewer: ProfileRevision, current_request: str | None,
) -> EmbeddingItem | None {
    if current_request is None or len(current_request.strip()) == 0 {
        return None;
    }
    digest: str = hashlib.sha256(
        (viewer.revision_id + "\n" + current_request.strip()).encode()
    ).hexdigest();
    return EmbeddingItem(
        item_id="request_" + digest[:24], text=current_request.strip(),
    );
}


def rank_candidates(
    viewer: ProfileRevision,
    profiles: list[ProfileRevision],
    vectors: dict[str, list[float]],
    request_vector: list[float] | None = None,
) -> list[CandidateReference] {
    candidates_to_rank: list[ProfileRevision] = eligible_profiles(viewer, profiles);
    if len(candidates_to_rank) == 0 {
        raise ValueError("no_eligible_candidate");
    }
    if viewer.revision_id not in vectors {
        raise ValueError("embedding_not_ready");
    }
    viewer_vector: list[float] = vectors[viewer.revision_id];
    candidates: list[CandidateReference] = [];

    for profile in candidates_to_rank {
        if profile.revision_id not in vectors {
            raise ValueError("embedding_not_ready");
        }
        score: float = cosine_similarity(viewer_vector, vectors[profile.revision_id]);
        if request_vector is not None {
            request_score: float = cosine_similarity(
                request_vector, vectors[profile.revision_id]
            );
            score += 0.20 * max(0.0, request_score);
        }
        candidates.append(
            CandidateReference(
                actor_id=profile.actor_id,
                profile_revision_id=profile.revision_id,
                score=score,
            )
        );
    }

    return sorted(
        candidates,
        key=lambda (candidate: CandidateReference) { (
            -candidate.score,
            candidate.actor_id,
            candidate.profile_revision_id
        ); },
    );
}


def rank_candidates_from_result(
    viewer: ProfileRevision,
    profiles: list[ProfileRevision],
    result: EmbeddingBatchResult,
    request_result: EmbeddingBatchResult | None = None,
    request_item: EmbeddingItem | None = None,
) -> list[CandidateReference] {
    if len(result.states) == 0 or result.states[-1] != "complete" {
        raise ValueError("embedding_not_ready");
    }
    if result.workload_version != WORKLOAD_VERSION
    or result.artifact_sha256 != WORKLOAD_ARTIFACT_SHA256 {
        raise ValueError("embedding_failed");
    }
    if request_result is None and request_item is None {
        return rank_candidates(viewer, profiles, result.vectors);
    }
    if request_result is None or request_item is None {
        raise ValueError("invalid_request");
    }
    if len(request_result.states) == 0 or request_result.states[-1] != "complete" {
        raise ValueError("embedding_not_ready");
    }
    if request_result.workload_version != WORKLOAD_VERSION
    or request_result.artifact_sha256 != WORKLOAD_ARTIFACT_SHA256 {
        raise ValueError("embedding_failed");
    }
    if request_item.item_id not in request_result.vectors {
        raise ValueError("embedding_not_ready");
    }
    return rank_candidates(
        viewer, profiles, result.vectors, request_result.vectors[request_item.item_id],
    );
}
