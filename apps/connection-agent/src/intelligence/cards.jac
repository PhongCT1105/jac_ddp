"""Grounded reciprocal assessments and isolated viewer-specific card snapshots."""

import hashlib;
import from src.contracts.models {
    CardSnapshot,
    PairAssessment,
    ProfileRevision,
    Suggestion
}

glob THEMES: list[str] = [
         "distributed systems",
         "software builder",
         "thoughtful collaboration",
         "climbing",
         "mentoring",
         "creative tools",
         "community events",
         "education",
         "community",
         "local arts",

     ];


obj EvidenceProvenance {
    has theme: str,
        left_revision_id: str,
        right_revision_id: str;
}


obj CardProvenance {
    has viewer_revision_id: str,
        subject_revision_id: str,
        workload_version: str,
        artifact_sha256: str,
        result_sha256: str,
        request_item_id: str | None = None,
        request_result_sha256: str | None = None;
}


obj GroundedAssessment {
    has assessment: PairAssessment,
        evidence_provenance: list[EvidenceProvenance],
        left_revision_id: str,
        right_revision_id: str,
        workload_version: str,
        artifact_sha256: str,
        result_sha256: str;
}


obj GroundedSuggestion {
    has suggestion: Suggestion,
        provenance: CardProvenance;
}


def unordered_pair_id(left_actor_id: str, right_actor_id: str) -> str {
    if left_actor_id < right_actor_id {
        return left_actor_id + "__" + right_actor_id;
    }
    return right_actor_id + "__" + left_actor_id;
}


def supported_themes(text: str) -> list[str] {
    normalized: str = text.lower();
    return [
        theme
        for theme in THEMES
        if theme in normalized
    ];
}


def evidence_for_theme(theme: str) -> str {
    return "Both profiles mention " + theme + ".";
}


def theme_from_evidence(evidence: str) -> str | None {
    for theme in THEMES {
        if evidence == evidence_for_theme(theme) {
            return theme;
        }
    }
    return None;
}


def grounded_assessment(
    left: ProfileRevision,
    right: ProfileRevision,
    workload_version: str = "0.1.0",
    artifact_sha256: str = "",
    result_sha256: str = "",
) -> GroundedAssessment {
    canonical_left: ProfileRevision = left if left.actor_id < right.actor_id else right;
    canonical_right: ProfileRevision = right
        if left.actor_id < right.actor_id
        else left;
    left_themes: list[str] = supported_themes(canonical_left.markdown);
    right_themes: list[str] = supported_themes(canonical_right.markdown);
    shared_themes: list[str] = [
        theme
        for theme in left_themes
        if theme in right_themes
    ];
    if len(shared_themes) == 0 {
        raise ValueError("no_grounded_evidence");
    }
    evidence: list[str] = [evidence_for_theme(theme) for theme in shared_themes[:2]];
    provenance: list[EvidenceProvenance] = [];
    for theme in shared_themes[:2] {
        provenance.append(
            EvidenceProvenance(
                theme=theme,
                left_revision_id=canonical_left.revision_id,
                right_revision_id=canonical_right.revision_id,
            )
        );
    }
    assessment = PairAssessment(
        pair_id=unordered_pair_id(canonical_left.actor_id, canonical_right.actor_id),
        left_actor_id=canonical_left.actor_id,
        right_actor_id=canonical_right.actor_id,
        reciprocal_score=min(0.99, 0.70 + 0.10 * len(shared_themes)),
        evidence=evidence,
    );
    grounded = GroundedAssessment(
        assessment=assessment,
        evidence_provenance=provenance,
        left_revision_id=canonical_left.revision_id,
        right_revision_id=canonical_right.revision_id,
        workload_version=workload_version,
        artifact_sha256=artifact_sha256,
        result_sha256=result_sha256,
    );
    validate_grounding(canonical_left, canonical_right, grounded);
    return grounded;
}


def validate_grounding(
    left: ProfileRevision, right: ProfileRevision, grounded: GroundedAssessment,
) -> None {
    revisions_match: bool = (
        grounded.left_revision_id == left.revision_id
        and grounded.right_revision_id == right.revision_id
    )
    or (
        grounded.left_revision_id == right.revision_id
        and grounded.right_revision_id == left.revision_id
    );
    actors_match: bool = (
        grounded.assessment.left_actor_id == left.actor_id
        and grounded.assessment.right_actor_id == right.actor_id
    )
    or (
        grounded.assessment.left_actor_id == right.actor_id
        and grounded.assessment.right_actor_id == left.actor_id
    );
    if not revisions_match
    or not actors_match
    or grounded.assessment.pair_id != unordered_pair_id(
        left.actor_id, right.actor_id
    ) {
        raise ValueError("ungrounded_evidence");
    }
    if len(grounded.assessment.evidence) == 0
    or len(grounded.assessment.evidence) != len(grounded.evidence_provenance) {
        raise ValueError("no_grounded_evidence");
    }
    for index in range(len(grounded.assessment.evidence)) {
        theme: str | None = theme_from_evidence(grounded.assessment.evidence[index]);
        proof: EvidenceProvenance = grounded.evidence_provenance[index];
        proof_revisions_match: bool = (
            proof.left_revision_id == left.revision_id
            and proof.right_revision_id == right.revision_id
        )
        or (
            proof.left_revision_id == right.revision_id
            and proof.right_revision_id == left.revision_id
        );
        if theme is None
        or proof.theme != theme
        or not proof_revisions_match
        or theme not in supported_themes(left.markdown)
        or theme not in supported_themes(right.markdown) {
            raise ValueError("ungrounded_evidence");
        }
    }
    return None;
}


def request_reason(
    viewer_request: str | None, subject: ProfileRevision,
) -> str | None {
    if viewer_request is None {
        return None;
    }
    request_themes: list[str] = supported_themes(viewer_request);
    subject_themes: list[str] = supported_themes(subject.markdown);
    for theme in request_themes {
        if theme in subject_themes {
            return mobile_reason(
                subject.display_name + " mentions " + theme + ", matching your request."
            );
        }
    }
    return None;
}


def opaque_card_id(
    viewer: ProfileRevision, subject: ProfileRevision, provenance: CardProvenance,
) -> str {
    identity: str = "|".join(
        [
            viewer.actor_id,
            viewer.revision_id,
            subject.actor_id,
            subject.revision_id,
            provenance.workload_version,
            provenance.artifact_sha256,
            provenance.result_sha256,
            provenance.request_item_id or "",
            provenance.request_result_sha256 or "",

        ]
    );
    return "card_" + hashlib.sha256(identity.encode()).hexdigest()[:20];
}


def mobile_headline(subject: ProfileRevision) -> str {
    suffix: str = ": a grounded connection";
    return subject.display_name[:88 - len(suffix)] + suffix;
}


def mobile_reason(reason: str) -> str {
    return reason[:120];
}


def grounded_suggestion(
    viewer: ProfileRevision,
    subject: ProfileRevision,
    grounded: GroundedAssessment,
    viewer_request: str | None = None,
    request_item_id: str | None = None,
    request_result_sha256: str | None = None,
) -> GroundedSuggestion {
    validate_grounding(viewer, subject, grounded);
    provenance = CardProvenance(
        viewer_revision_id=viewer.revision_id,
        subject_revision_id=subject.revision_id,
        workload_version=grounded.workload_version,
        artifact_sha256=grounded.artifact_sha256,
        result_sha256=grounded.result_sha256,
        request_item_id=request_item_id,
        request_result_sha256=request_result_sha256,
    );
    reasons: list[str] = [];
    directional_request_reason: str | None = request_reason(viewer_request, subject);
    if directional_request_reason is not None {
        reasons.append(directional_request_reason);
    }
    for proof in grounded.evidence_provenance {
        if len(reasons) == 2 {
            break;
        }
        reasons.append(
            mobile_reason(subject.display_name + " also mentions " + proof.theme + ".")
        );
    }
    card = CardSnapshot(
        card_id=opaque_card_id(viewer, subject, provenance),
        pair_id=grounded.assessment.pair_id,
        viewer_id=viewer.actor_id,
        subject_id=subject.actor_id,
        subject_revision_id=subject.revision_id,
        headline=mobile_headline(subject),
        reasons=reasons[:2],
    );
    suggestion = Suggestion(
        suggestion_id="suggestion_" + viewer.actor_id + "__" + subject.actor_id,
        pair_id=grounded.assessment.pair_id,
        viewer_id=viewer.actor_id,
        subject_id=subject.actor_id,
        card=card,
        state="active",
    );
    return GroundedSuggestion(suggestion=suggestion, provenance=provenance);
}


def fixture_assessment(
    left: ProfileRevision, right: ProfileRevision,
) -> PairAssessment {
    return grounded_assessment(left, right).assessment;
}


def fixture_provenance(
    viewer: ProfileRevision, subject: ProfileRevision, assessment: PairAssessment,
) -> list[EvidenceProvenance] {
    proofs: list[EvidenceProvenance] = [];
    for evidence in assessment.evidence {
        theme: str | None = theme_from_evidence(evidence);
        if theme is None {
            raise ValueError("ungrounded_evidence");
        }
        proofs.append(
            EvidenceProvenance(
                theme=theme,
                left_revision_id=viewer.revision_id,
                right_revision_id=subject.revision_id,
            )
        );
    }
    return proofs;
}


def fixture_suggestion(
    viewer: ProfileRevision, subject: ProfileRevision, assessment: PairAssessment,
) -> Suggestion {
    grounded = GroundedAssessment(
        assessment=assessment,
        evidence_provenance=fixture_provenance(viewer, subject, assessment),
        left_revision_id=viewer.revision_id,
        right_revision_id=subject.revision_id,
        workload_version="0.1.0",
        artifact_sha256="",
        result_sha256="",
    );
    return grounded_suggestion(viewer, subject, grounded).suggestion;
}
