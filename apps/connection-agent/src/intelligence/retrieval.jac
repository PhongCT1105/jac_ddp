"""Provider-neutral candidate retrieval over a complete embedding set."""

import from src.contracts.models { CandidateReference, ProfileRevision }


def cosine_similarity(left: list[float], right: list[float]) -> float {
    if len(left) != len(right) or len(left) == 0 {
        raise ValueError("incompatible_vectors");
    }
    return sum([left[index] * right[index] for index in range(len(left))]);
}


def rank_candidates(
    viewer: ProfileRevision,
    profiles: list[ProfileRevision],
    vectors: dict[str, list[float]],
) -> list[CandidateReference] {
    if viewer.revision_id not in vectors {
        raise ValueError("viewer_embedding_not_ready");
    }
    viewer_vector: list[float] = vectors[viewer.revision_id];
    candidates: list[CandidateReference] = [];

    for profile in profiles {
        if profile.actor_id == viewer.actor_id or not profile.eligible {
            continue;
        }
        if profile.actor_id in viewer.blocked_actor_ids {
            continue;
        }
        if profile.revision_id not in vectors {
            raise ValueError("candidate_embedding_not_ready");
        }
        candidates.append(
            CandidateReference(
                actor_id=profile.actor_id,
                profile_revision_id=profile.revision_id,
                score=cosine_similarity(viewer_vector, vectors[profile.revision_id]),
            )
        );
    }

    return sorted(
        candidates,
        key=lambda (candidate: CandidateReference) { candidate.score; },
        reverse=True,
    );
}
