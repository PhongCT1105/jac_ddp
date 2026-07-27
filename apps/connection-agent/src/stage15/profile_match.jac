"""Typed Stage 1.5 server operation for matching one ephemeral visitor profile."""

import hashlib;
import math;
import os;
import from src.contracts.models { EmbeddingItem }
import from src.stage15.corpus { DemoCorpus, DemoProfile, load_demo_corpus }
import from src.stage15.explainer {
    ExplanationCandidate,
    MatchExplainer,
    MatchExplanationResult,
    default_match_explainer,
    validate_explanation_result
}
import from src.stage15.provider {
    EmbeddingProvider,
    ProviderEmbeddingResult,
    default_embedding_provider
}


glob VISITOR_ITEM_ID: str = "__stage15_visitor__",
     PY_ROUND: any = round;


obj ProfileMatchError {
    has code: str,
        message: str,
        retryable: bool,
        field: str | None = None;
}


obj ProfileMatchCard {
    has profile_id: str,
        name: str,
        score: float,
        excerpt: str,
        explanation: str,
        reasons: list[str];
}


obj ProfileMatchResponse {
    has ok: bool,
        error_code: str,
        error_message: str,
        error_retryable: bool,
        error_field: str | None,
        provider_mode: str,
        runtime_tag: str,
        workload_version: str,
        corpus_revision: str,
        result_sha256: str,
        submitted_item_count: int,
        recombined_item_count: int,
        candidate_count: int,
        terminal_states: list[str],
        explanation_mode: str,
        explanation_model: str,
        matches: list[ProfileMatchCard];
}


obj RankedDemoProfile {
    has profile: DemoProfile,
        canonical_score: float;
}


def error_response(
    code: str, message: str, retryable: bool, field: str | None = None,
) -> ProfileMatchResponse {
    return ProfileMatchResponse(
        ok=False,
        error_code=code,
        error_message=message,
        error_retryable=retryable,
        error_field=field,
        provider_mode="",
        runtime_tag="",
        workload_version="",
        corpus_revision="",
        result_sha256="",
        submitted_item_count=0,
        recombined_item_count=0,
        candidate_count=0,
        terminal_states=[],
        explanation_mode="",
        explanation_model="",
        matches=[],
    );
}


def validate_visitor_input(
    name: str, profile_markdown: str
) -> ProfileMatchError | None {
    if len(name) > 100 {
        return ProfileMatchError(
            code="name_too_long",
            message="Name must be 100 characters or fewer.",
            retryable=False,
            field="name",
        );
    }
    if len(name.strip()) == 0 {
        return ProfileMatchError(
            code="name_required",
            message="Enter a name.",
            retryable=False,
            field="name",
        );
    }
    if len(profile_markdown) > 12000 {
        return ProfileMatchError(
            code="profile_too_long",
            message="Profile must be 12,000 characters or fewer.",
            retryable=False,
            field="profile_markdown",
        );
    }
    if len(profile_markdown.strip()) == 0 {
        return ProfileMatchError(
            code="profile_required",
            message="Write a short profile before finding connections.",
            retryable=False,
            field="profile_markdown",
        );
    }
    return None;
}


def default_corpus_path -> str {
    return os.path.abspath(
        os.path.join(os.path.dirname(__file__), "../../data/demo-profiles")
    );
}


def embedding_items(
    visitor_markdown: str, profiles: list[DemoProfile],
) -> list[EmbeddingItem] {
    items: list[EmbeddingItem] = [
        EmbeddingItem(item_id=VISITOR_ITEM_ID, text=visitor_markdown)
    ];
    for profile in profiles {
        items.append(EmbeddingItem(item_id=profile.profile_id, text=profile.body));
    }
    return items;
}


def validate_provider_result(
    result: ProviderEmbeddingResult, expected_ids: list[str],
) {
    if result.submitted_item_count != len(expected_ids)
    or result.recombined_item_count != len(expected_ids)
    or len(result.result_item_ids) != len(expected_ids)
    or len(set(result.result_item_ids)) != len(expected_ids)
    or set(result.result_item_ids) != set(expected_ids)
    or len(result.vectors) != len(expected_ids)
    or set(result.vectors.keys()) != set(expected_ids)
    or result.dimensions <= 0 {
        raise ValueError("provider_result_invalid");
    }
    if len(result.terminal_states) == 0
    or result.terminal_states[-1] != "complete"
    or "failed" in result.terminal_states
    or len(result.provider_mode.strip()) == 0
    or len(result.workload_version.strip()) == 0
    or len(result.runtime_tag.strip()) == 0
    or not result.result_identity.startswith("sha256:") {
        raise ValueError("provider_result_invalid");
    }
    for item_id in expected_ids {
        vector: list[float] = result.vectors[item_id];
        if len(vector) != result.dimensions {
            raise ValueError("provider_result_invalid");
        }
        norm_squared: float = 0.0;
        for component in vector {
            if isinstance(component, bool) or not math.isfinite(component) {
                raise ValueError("provider_result_invalid");
            }
            norm_squared += component * component;
        }
        if norm_squared <= 0.0 or not math.isfinite(norm_squared) {
            raise ValueError("provider_result_invalid");
        }
    }
}


def cosine_similarity(left: list[float], right: list[float]) -> float {
    dot: float = 0.0;
    left_norm: float = 0.0;
    right_norm: float = 0.0;
    for index in range(len(left)) {
        dot += left[index] * right[index];
        left_norm += left[index] * left[index];
        right_norm += right[index] * right[index];
    }
    denominator: float = math.sqrt(left_norm) * math.sqrt(right_norm);
    if denominator <= 0.0 {
        raise ValueError("provider_result_invalid");
    }
    score: float = dot / denominator;
    if not math.isfinite(score) {
        raise ValueError("provider_result_invalid");
    }
    return PY_ROUND(score, 12) as float;
}


def deterministic_excerpt(body: str, maximum_length: int = 220) -> str {
    if len(body) <= maximum_length {
        return body;
    }
    return body[:maximum_length].strip();
}


def neutral_reason(runtime_tag: str) -> str {
    if "fallback" in runtime_tag {
        return "Deterministic demo ranking placed this fictional profile near your text.";
    }
    return "The embedding model placed this fictional profile near your text.";
}


def rank_profiles(
    profiles: list[DemoProfile], result: ProviderEmbeddingResult,
) -> list[ProfileMatchCard] {
    visitor_vector: list[float] = result.vectors[VISITOR_ITEM_ID];
    ranked: list[RankedDemoProfile] = [];
    for profile in profiles {
        ranked.append(
            RankedDemoProfile(
                profile=profile,
                canonical_score=cosine_similarity(
                    visitor_vector, result.vectors[profile.profile_id]
                ),
            )
        );
    }
    ranked = sorted(
        ranked,
        key=lambda (candidate: RankedDemoProfile) { (
            -candidate.canonical_score,
            candidate.profile.profile_id
        ); },
    );
    cards: list[ProfileMatchCard] = [];
    for candidate in ranked[:3] {
        cards.append(
            ProfileMatchCard(
                profile_id=candidate.profile.profile_id,
                name=candidate.profile.name,
                score=PY_ROUND(candidate.canonical_score, 4) as float,
                excerpt=deterministic_excerpt(candidate.profile.body),
                explanation="",
                reasons=[neutral_reason(result.runtime_tag)],
            )
        );
    }
    return cards;
}


def match_profile_with(
    name: str,
    profile_markdown: str,
    corpus_path: str,
    provider: EmbeddingProvider,
    explainer: MatchExplainer,
) -> ProfileMatchResponse {
    input_error: ProfileMatchError | None = validate_visitor_input(
        name, profile_markdown
    );
    if input_error is not None {
        return error_response(
            input_error.code,
            input_error.message,
            input_error.retryable,
            input_error.field,
        );
    }
    try {
        corpus: DemoCorpus = load_demo_corpus(corpus_path);
    } except Exception {
        return error_response(
            "corpus_unavailable", "The fictional demo pool is unavailable.", False,
        );
    }
    items: list[EmbeddingItem] = embedding_items(
        profile_markdown.strip(), corpus.profiles
    );
    if len(items) != len(corpus.profiles) + 1 {
        return error_response(
            "corpus_unavailable", "The fictional demo pool is unavailable.", False,
        );
    }
    request_key: str = "stage15-" + hashlib.sha256(
        (
            corpus.revision + "\n" + name.strip() + "\n" + profile_markdown.strip()
        ).encode(
            "utf-8"
        )
    ).hexdigest();
    try {
        provider_result: ProviderEmbeddingResult = provider.embed(items, request_key);
        expected_ids: list[str] = [item.item_id for item in items];
        validate_provider_result(provider_result, expected_ids);
        cards: list[ProfileMatchCard] = rank_profiles(corpus.profiles, provider_result);
        if len(cards) != 3 {
            raise ValueError("provider_result_invalid");
        }
    } except ValueError {
        return error_response(
            "provider_result_invalid",
            "The matching service returned an invalid result. Try again.",
            True,
        );
    } except Exception {
        return error_response(
            "provider_failed",
            "The matching service is temporarily unavailable. Try again.",
            True,
        );
    }
    candidates_by_id: dict[str, DemoProfile] = {
        profile.profile_id: profile for profile in corpus.profiles
    };
    candidates: list[ExplanationCandidate] = [];
    for card in cards {
        selected: DemoProfile = candidates_by_id[card.profile_id];
        candidates.append(
            ExplanationCandidate(
                profile_id=selected.profile_id, name=selected.name, body=selected.body,
            )
        );
    }
    try {
        explanation_result: MatchExplanationResult = explainer.explain(
            name.strip(), profile_markdown.strip(), candidates
        );
        validate_explanation_result(explanation_result, candidates);
        for index in range(len(cards)) {
            explanation: str = explanation_result.explanations[index].explanation;
            cards[index].explanation = explanation;
            cards[index].reasons = [explanation];
        }
        return ProfileMatchResponse(
            ok=True,
            error_code="",
            error_message="",
            error_retryable=False,
            error_field=None,
            provider_mode=provider_result.provider_mode,
            runtime_tag=provider_result.runtime_tag,
            workload_version=provider_result.workload_version,
            corpus_revision=corpus.revision,
            result_sha256=provider_result.result_identity,
            submitted_item_count=provider_result.submitted_item_count,
            recombined_item_count=provider_result.recombined_item_count,
            candidate_count=len(corpus.profiles),
            terminal_states=[state for state in provider_result.terminal_states],
            explanation_mode=explanation_result.mode,
            explanation_model=explanation_result.model,
            matches=cards,
        );
    } except ValueError {
        return error_response(
            "explanation_result_invalid",
            "The explanation service returned an invalid result. Try again.",
            True,
        );
    } except Exception {
        return error_response(
            "explanation_failed",
            "The explanation service is temporarily unavailable. Try again.",
            True,
        );
    }
}


def:pub find_profile_matches(
    name: str, profile_markdown: str,
) -> ProfileMatchResponse {
    return match_profile_with(
        name,
        profile_markdown,
        default_corpus_path(),
        default_embedding_provider(),
        default_match_explainer(),
    );
}
