import from src.adapters.fixtures { find_profile, fixture_profiles }
import from src.adapters.mock_jacgrid { MockJacGrid, submit_embeddings }
import from src.contracts.models {
    EmbeddingBatchResult,
    EmbeddingItem,
    PairAssessment,
    ProfileRevision
}
import from src.intelligence.cards {
    EvidenceProvenance,
    GroundedAssessment,
    fixture_assessment,
    grounded_assessment,
    grounded_suggestion,
    validate_grounding
}
import from src.intelligence.retrieval {
    rank_candidates,
    rank_candidates_from_result,
    request_embedding_item
}


def workload_dir -> str {
    return "../../workloads/connection-embedding";
}


def complete_result(
    profiles: list[ProfileRevision], key: str,
) -> EmbeddingBatchResult {
    items: list[EmbeddingItem] = [
        EmbeddingItem(item_id=profile.revision_id, text=profile.markdown)
        for profile in profiles
    ];
    mock = MockJacGrid(workload_dir=workload_dir(), chunk_size=10);
    result = submit_embeddings(mock, items, key);
    assert mock.invocation_count == 4;
    assert len(result.vectors) == 31;
    return result;
}


test "whole pool retrieval consumes all recombined workload projections" {
    profiles = fixture_profiles();
    result = complete_result(profiles, "intelligence-whole-pool");
    alice = find_profile(profiles, "alice_builder");
    candidates = rank_candidates_from_result(alice, profiles, result);
    assert len(candidates) == 30;
    assert candidates[0].actor_id == "bob_researcher";
    assert result.workload_version == "0.1.0";
    assert result.states[-1] == "complete";
}


test "retrieval total order does not depend on input profile order" {
    viewer = ProfileRevision(
        actor_id="viewer",
        display_name="Viewer",
        revision_id="viewer_rev",
        markdown="community",
    );
    alpha = ProfileRevision(
        actor_id="alpha",
        display_name="Alpha",
        revision_id="alpha_rev",
        markdown="community",
    );
    beta = ProfileRevision(
        actor_id="beta",
        display_name="Beta",
        revision_id="beta_rev",
        markdown="community",
    );
    vectors: dict[str, list[float]] = {
        "viewer_rev": [1.0, 0.0],
        "alpha_rev": [1.0, 0.0],
        "beta_rev": [1.0, 0.0],

    };
    first = rank_candidates(viewer, [viewer, beta, alpha], vectors);
    second = rank_candidates(viewer, [alpha, viewer, beta], vectors);
    assert [candidate.actor_id for candidate in first] == ["alpha", "beta"];
    assert [candidate.actor_id for candidate in second] == ["alpha", "beta"];
}


test "retrieval excludes self both block directions and ineligible profiles" {
    viewer = ProfileRevision(
        actor_id="viewer",
        display_name="Viewer",
        revision_id="viewer_rev",
        markdown="community",
        blocked_actor_ids=["viewer_blocks"],
    );
    viewer_blocks = ProfileRevision(
        actor_id="viewer_blocks",
        display_name="Blocked",
        revision_id="blocked_rev",
        markdown="community",
    );
    subject_blocks = ProfileRevision(
        actor_id="subject_blocks",
        display_name="Blocks Viewer",
        revision_id="subject_blocks_rev",
        markdown="community",
        blocked_actor_ids=["viewer"],
    );
    ineligible = ProfileRevision(
        actor_id="ineligible",
        display_name="Ineligible",
        revision_id="ineligible_rev",
        markdown="community",
        eligible=False,
    );
    allowed = ProfileRevision(
        actor_id="allowed",
        display_name="Allowed",
        revision_id="allowed_rev",
        markdown="community",
    );
    vectors: dict[str, list[float]] = {"viewer_rev": [1.0], "allowed_rev": [1.0],};
    candidates = rank_candidates(
        viewer, [viewer, viewer_blocks, subject_blocks, ineligible, allowed], vectors,
    );
    assert [candidate.actor_id for candidate in candidates] == ["allowed"];
}


test "missing required vector and empty eligible pool have released failures" {
    viewer = ProfileRevision(
        actor_id="viewer",
        display_name="Viewer",
        revision_id="viewer_rev",
        markdown="community",
    );
    candidate = ProfileRevision(
        actor_id="candidate",
        display_name="Candidate",
        revision_id="candidate_rev",
        markdown="community",
    );
    try {
        _ = rank_candidates(viewer, [viewer, candidate], {"viewer_rev": [1.0]});
        assert False , "required candidate vector must fail";
    } except ValueError as error {
        assert str(error) == "embedding_not_ready";
    }
    try {
        _ = rank_candidates(viewer, [viewer], {"viewer_rev": [1.0]});
        assert False , "empty eligible pool must fail";
    } except ValueError as error {
        assert str(error) == "no_eligible_candidate";
    }
}


test "result-aware retrieval rejects incomplete and wrong workload results" {
    profiles = fixture_profiles();
    alice = find_profile(profiles, "alice_builder");
    result = complete_result(profiles, "intelligence-result-identity");
    result.states = ["queued", "running"];
    try {
        _ = rank_candidates_from_result(alice, profiles, result);
        assert False , "incomplete result must fail";
    } except ValueError as error {
        assert str(error) == "embedding_not_ready";
    }
    result.states = ["queued", "running", "verifying", "complete"];
    result.workload_version = "unexpected";
    try {
        _ = rank_candidates_from_result(alice, profiles, result);
        assert False , "wrong workload must fail";
    } except ValueError as error {
        assert str(error) == "embedding_failed";
    }
}


test "explicit request is a separate workload item and remains viewer private" {
    profiles = fixture_profiles();
    alice = find_profile(profiles, "alice_builder");
    bob = find_profile(profiles, "bob_researcher");
    result = complete_result(profiles, "intelligence-request-pool");
    request = request_embedding_item(alice, "distributed systems and mentoring");
    assert request is not None;
    request_item = request as EmbeddingItem;
    assert request_item.item_id not in result.vectors;
    request_result = submit_embeddings(
        MockJacGrid(workload_dir=workload_dir()),
        [request_item],
        "intelligence-request-vector",
    );
    candidates = rank_candidates_from_result(
        alice, profiles, result, request_result, request_item,
    );
    assert candidates[0].actor_id == "bob_researcher";
    grounded = grounded_assessment(
        alice,
        bob,
        result.workload_version,
        result.artifact_sha256,
        result.result_sha256,
    );
    alice_card = grounded_suggestion(
        alice,
        bob,
        grounded,
        request_item.text,
        request_item.item_id,
        request_result.result_sha256,
    );
    bob_card = grounded_suggestion(bob, alice, grounded);
    assert "matching your request" in alice_card.suggestion.card.reasons[0];
    assert all(
        [
            "matching your request" not in reason
            for reason in bob_card.suggestion.card.reasons
        ]
    );
}


test "reciprocal cards have provenance and independently owned reasons" {
    profiles = fixture_profiles();
    alice = find_profile(profiles, "alice_builder");
    bob = find_profile(profiles, "bob_researcher");
    result = complete_result(profiles, "intelligence-cards");
    grounded = grounded_assessment(
        alice,
        bob,
        result.workload_version,
        result.artifact_sha256,
        result.result_sha256,
    );
    alice_card = grounded_suggestion(alice, bob, grounded);
    bob_card = grounded_suggestion(bob, alice, grounded);
    assert alice_card.suggestion.pair_id == bob_card.suggestion.pair_id;
    assert alice_card.suggestion.card.card_id != bob_card.suggestion.card.card_id;
    assert alice_card.suggestion.card.subject_revision_id == bob.revision_id;
    assert bob_card.suggestion.card.subject_revision_id == alice.revision_id;
    assert alice_card.provenance.viewer_revision_id == alice.revision_id;
    assert alice_card.provenance.result_sha256 == result.result_sha256;
    assert alice_card.provenance.request_result_sha256 is None;
    assert len(alice_card.suggestion.card.headline) <= 88;
    assert all([len(reason) <= 120 for reason in alice_card.suggestion.card.reasons]);
    bob_reason_count: int = len(bob_card.suggestion.card.reasons);
    alice_card.suggestion.card.reasons.append("local mutation");
    assert len(bob_card.suggestion.card.reasons) == bob_reason_count;
}


test "contrasting request produces a grounded directional evidence path" {
    profiles = fixture_profiles();
    diego = find_profile(profiles, "diego_organizer");
    carol = find_profile(profiles, "carol_designer");
    grounded = grounded_assessment(diego, carol);
    request = request_embedding_item(diego, "creative tools and community events");
    assert request is not None;
    request_item = request as EmbeddingItem;
    request_result = submit_embeddings(
        MockJacGrid(workload_dir=workload_dir()),
        [request_item],
        "contrast-request-vector",
    );
    card = grounded_suggestion(
        diego,
        carol,
        grounded,
        request_item.text,
        request_item.item_id,
        request_result.result_sha256,
    );
    no_request_card = grounded_suggestion(diego, carol, grounded);
    assert "matching your request" in card.suggestion.card.reasons[0];
    assert all(
        [
            "matching your request" not in reason
            for reason in no_request_card.suggestion.card.reasons
        ]
    );
    assert "creative tools and community events" not in card.suggestion.card.reasons[0];
}


test "mobile card headline truncates a long synthetic display name" {
    profiles = fixture_profiles();
    alice = find_profile(profiles, "alice_builder");
    bob = find_profile(profiles, "bob_researcher");
    bob.display_name = "B" * 120;
    card = grounded_suggestion(alice, bob, grounded_assessment(alice, bob));
    assert len(card.suggestion.card.headline) == 88;
    assert all([len(reason) <= 120 for reason in card.suggestion.card.reasons]);
}


test "unsupported one-sided and stale evidence fails grounding validation" {
    profiles = fixture_profiles();
    alice = find_profile(profiles, "alice_builder");
    bob = find_profile(profiles, "bob_researcher");
    valid = fixture_assessment(alice, bob);
    unsupported = GroundedAssessment(
        assessment=PairAssessment(
            pair_id=valid.pair_id,
            left_actor_id=alice.actor_id,
            right_actor_id=bob.actor_id,
            reciprocal_score=valid.reciprocal_score,
            evidence=["Both profiles mention imaginary astronomy."],
        ),
        evidence_provenance=[
            EvidenceProvenance(
                theme="imaginary astronomy",
                left_revision_id=alice.revision_id,
                right_revision_id=bob.revision_id,
            )
        ],
        left_revision_id=alice.revision_id,
        right_revision_id=bob.revision_id,
        workload_version="0.1.0",
        artifact_sha256="",
        result_sha256="",
    );
    try {
        validate_grounding(alice, bob, unsupported);
        assert False , "unsupported evidence must fail";
    } except ValueError as error {
        assert str(error) == "ungrounded_evidence";
    }
    stale = grounded_assessment(alice, bob);
    stale.left_revision_id = "stale_revision";
    try {
        validate_grounding(alice, bob, stale);
        assert False , "stale provenance must fail";
    } except ValueError as error {
        assert str(error) == "ungrounded_evidence";
    }
    carol = find_profile(profiles, "carol_designer");
    one_sided = GroundedAssessment(
        assessment=PairAssessment(
            pair_id="alice_builder__carol_designer",
            left_actor_id=alice.actor_id,
            right_actor_id=carol.actor_id,
            reciprocal_score=0.50,
            evidence=["Both profiles mention creative tools."],
        ),
        evidence_provenance=[
            EvidenceProvenance(
                theme="creative tools",
                left_revision_id=alice.revision_id,
                right_revision_id=carol.revision_id,
            )
        ],
        left_revision_id=alice.revision_id,
        right_revision_id=carol.revision_id,
        workload_version="0.1.0",
        artifact_sha256="",
        result_sha256="",
    );
    try {
        validate_grounding(alice, carol, one_sided);
        assert False , "one-sided evidence must fail";
    } except ValueError as error {
        assert str(error) == "ungrounded_evidence";
    }
    forged_actor = grounded_assessment(alice, bob);
    forged_actor.assessment.left_actor_id = carol.actor_id;
    try {
        validate_grounding(alice, bob, forged_actor);
        assert False , "forged assessment actor must fail";
    } except ValueError as error {
        assert str(error) == "ungrounded_evidence";
    }
}


test "reversed assessment construction remains canonical" {
    profiles = fixture_profiles();
    alice = find_profile(profiles, "alice_builder");
    bob = find_profile(profiles, "bob_researcher");
    forward = grounded_assessment(alice, bob);
    reverse = grounded_assessment(bob, alice);
    assert forward.assessment.pair_id == reverse.assessment.pair_id;
    assert forward.assessment.left_actor_id == reverse.assessment.left_actor_id;
    assert forward.assessment.right_actor_id == reverse.assessment.right_actor_id;
    assert forward.assessment.evidence == reverse.assessment.evidence;
    assert forward.left_revision_id == reverse.left_revision_id;
}
