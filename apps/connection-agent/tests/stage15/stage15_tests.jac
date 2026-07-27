import json;
import math;
import os;
import tempfile;
import from src.contracts.models { EmbeddingItem }
import from src.stage15.corpus { DemoCorpus, load_demo_corpus }
import from src.stage15.profile_match {
    ProfileMatchResponse,
    VISITOR_ITEM_ID,
    match_profile_with
}
import from src.stage15.provider {
    EmbeddingProvider,
    MockWorkloadProvider,
    ProviderEmbeddingResult,
    default_embedding_provider,
    default_workload_dir
}


def profile_id(index: int) -> str {
    return f"person-{index:03d}";
}


def profile_body(index: int) -> str {
    return f"Fictional profile {index:03d} explores community project {index:03d}, careful conversation, and local creative work.";
}


def write_corpus(path: str, line_ending: str = "\n", count: int = 100) {
    for index in range(count) {
        body: str = profile_body(index);
        content: str = line_ending.join(
            [
                "---",
                "id: " + profile_id(index),
                f"name: Fictional Person {index:03d}",
                "---",
                body,

            ]
        );
        file_name: str = f"profile-{count - 1 - index:03d}.md";
        with open(
            os.path.join(path, file_name), "w", encoding="utf-8"
        ) as profile_file {
            profile_file.write(content);
        }
    }
}


def known_vectors(items: list[EmbeddingItem]) -> dict[str, list[float]] {
    vectors: dict[str, list[float]] = {};
    for item in items {
        vector: list[float] = [0.0, 1.0];
        if item.item_id == VISITOR_ITEM_ID or item.item_id == "person-099" {
            vector = [1.0, 0.0];
        } elif item.item_id in ["person-001", "person-002"] {
            vector = [0.8, 0.6];
        } elif item.item_id == "person-050" {
            vector = [0.7, math.sqrt(0.51)];
        }
        vectors[item.item_id] = vector;
    }
    return vectors;
}


def known_result(items: list[EmbeddingItem]) -> ProviderEmbeddingResult {
    vectors: dict[str, list[float]] = known_vectors(items);
    return ProviderEmbeddingResult(
        provider_mode="mock",
        workload_version="1.0.0",
        runtime_tag="connection-embedding-fallback:1.0.0",
        result_identity="sha256:known-vector-result",
        terminal_states=["queued", "running", "verifying", "complete"],
        result_item_ids=[item.item_id for item in items],
        vectors=vectors,
        submitted_item_count=len(items),
        recombined_item_count=len(items),
        dimensions=2,
    );
}


obj KnownVectorProvider(EmbeddingProvider) {
    override def embed(
        items: list[EmbeddingItem], _request_key: str,
    ) -> ProviderEmbeddingResult {
        return known_result(items);
    }
}


obj FailingProvider(EmbeddingProvider) {
    override def embed(
        _items: list[EmbeddingItem], _request_key: str,
    ) -> ProviderEmbeddingResult {
        raise RuntimeError("SECRET provider traceback must not escape");
    }
}


obj InvalidResultProvider(EmbeddingProvider) {
    has failure_mode: str;

    override def embed(
        items: list[EmbeddingItem], _request_key: str,
    ) -> ProviderEmbeddingResult {
        result: ProviderEmbeddingResult = known_result(items);
        if self.failure_mode == "missing" {
            result.result_item_ids = result.result_item_ids[:-1];
            del result.vectors[items[-1].item_id];
            result.recombined_item_count -= 1;
        } elif self.failure_mode == "duplicate" {
            result.result_item_ids[-1] = result.result_item_ids[0];
        } elif self.failure_mode == "nonfinite" {
            result.vectors[items[-1].item_id] = [float("nan"), 0.0];
        } elif self.failure_mode == "dimension" {
            result.vectors[items[-1].item_id] = [1.0];
        }
        return result;
    }
}


test "strict corpus loader normalizes sorts and revisions deterministically" {
    with tempfile.TemporaryDirectory(prefix="stage15-corpus-") as corpus_path {
        write_corpus(corpus_path, "\r\n");
        first: DemoCorpus = load_demo_corpus(corpus_path);
        second: DemoCorpus = load_demo_corpus(corpus_path);
        assert len(first.profiles) == 100;
        assert first.profiles[0].profile_id == "person-000";
        assert first.profiles[-1].profile_id == "person-099";
        assert first.revision == second.revision;
        assert first.revision.startswith("sha256:");
        assert "\r" not in first.profiles[0].body;
    }
}


test "corpus loader accepts three through one hundred and retains strict release count" {
    for count in [3, 17, 100] {
        with tempfile.TemporaryDirectory(
            prefix="stage15-valid-count-"
        ) as corpus_path {
            write_corpus(corpus_path, count=count);
            corpus: DemoCorpus = load_demo_corpus(corpus_path);
            assert len(corpus.profiles) == count;
        }
    }
    with tempfile.TemporaryDirectory(prefix="stage15-count-") as corpus_path {
        write_corpus(corpus_path, count=99);
        try {
            _ = load_demo_corpus(corpus_path, expected_count=100);
            assert False , "strict release validation must require 100 profiles";
        } except ValueError as error {
            assert str(error) == "corpus_count_invalid";
        }
    }
    for count in [2, 101] {
        with tempfile.TemporaryDirectory(
            prefix="stage15-invalid-count-"
        ) as corpus_path {
            write_corpus(corpus_path, count=count);
            try {
                _ = load_demo_corpus(corpus_path);
                assert False , "runtime corpus bounds must be enforced";
            } except ValueError as error {
                assert str(error) == "corpus_count_invalid";
            }
        }
    }
}


test "strict corpus loader rejects frontmatter and duplicate content" {
    with tempfile.TemporaryDirectory(prefix="stage15-frontmatter-") as corpus_path {
        write_corpus(corpus_path);
        with open(
            os.path.join(corpus_path, "profile-099.md"), "w", encoding="utf-8"
        ) as profile_file {
            profile_file.write(
                "---\nid: person-000\nname: Fictional Person 000\ntag: extra\n---\nBody"
            );
        }
        try {
            _ = load_demo_corpus(corpus_path);
            assert False , "extra frontmatter must fail";
        } except ValueError as error {
            assert str(error) == "corpus_malformed_frontmatter";
        }
    }
    with tempfile.TemporaryDirectory(prefix="stage15-duplicate-") as corpus_path {
        write_corpus(corpus_path);
        duplicate_body: str = profile_body(0);
        with open(
            os.path.join(corpus_path, "profile-098.md"), "w", encoding="utf-8"
        ) as profile_file {
            profile_file.write(
                "---\nid: person-001\nname: Fictional Person 001\n---\n" + duplicate_body
            );
        }
        try {
            _ = load_demo_corpus(corpus_path);
            assert False , "duplicate bodies must fail";
        } except ValueError as error {
            assert str(error) == "corpus_duplicate_body";
        }
    }
}


test "known vectors rank the complete pool with stable ties and grounded cards" {
    with tempfile.TemporaryDirectory(prefix="stage15-ranking-") as corpus_path {
        write_corpus(corpus_path);
        response: ProfileMatchResponse = match_profile_with(
            "Visitor",
            "I enjoy careful conversation and creative work.",
            corpus_path,
            KnownVectorProvider(),
        );
        assert response.ok;
        assert response.error_code == "";
        assert response.submitted_item_count == 101;
        assert response.recombined_item_count == 101;
        assert response.candidate_count == 100;
        assert response.runtime_tag == "connection-embedding-fallback:1.0.0";
        assert len(response.matches) == 3;
        assert [card.profile_id for card in response.matches] == [
            "person-099",
            "person-001",
            "person-002",

        ];
        assert response.matches[1].score == response.matches[2].score;
        for card in response.matches {
            assert card.excerpt in profile_body(int(card.profile_id[-3:]));
            assert card.reasons == [
                "Deterministic demo ranking placed this fictional profile near your text."
            ];
        }
    }
}


test "matching submits dynamic corpus size plus visitor and ranks every candidate" {
    with tempfile.TemporaryDirectory(
        prefix="stage15-dynamic-ranking-"
    ) as corpus_path {
        write_corpus(corpus_path, count=3);
        response: ProfileMatchResponse = match_profile_with(
            "Visitor",
            "I enjoy careful conversation and creative work.",
            corpus_path,
            KnownVectorProvider(),
        );
        assert response.ok;
        assert response.submitted_item_count == 4;
        assert response.recombined_item_count == 4;
        assert response.candidate_count == 3;
        assert len(response.matches) == 3;
        assert [card.profile_id for card in response.matches] == [
            "person-001",
            "person-002",
            "person-000",

        ];
    }
}


test "matching is deterministic and does not return visitor text" {
    with tempfile.TemporaryDirectory(prefix="stage15-determinism-") as corpus_path {
        write_corpus(corpus_path);
        secret_profile: str = "PRIVATE-VISITOR-TEXT creative communities";
        first: ProfileMatchResponse = match_profile_with(
            "Visitor", secret_profile, corpus_path, KnownVectorProvider()
        );
        second: ProfileMatchResponse = match_profile_with(
            "Visitor", secret_profile, corpus_path, KnownVectorProvider()
        );
        assert first.ok and second.ok;
        assert [card.profile_id for card in first.matches] == [
            card.profile_id for card in second.matches
        ];
        assert [card.score for card in first.matches] == [
            card.score for card in second.matches
        ];
        assert secret_profile not in str(first);
    }
}


test "safe validation and provider failures preserve retry semantics" {
    with tempfile.TemporaryDirectory(prefix="stage15-errors-") as corpus_path {
        write_corpus(corpus_path);
        blank: ProfileMatchResponse = match_profile_with(
            " ", "profile", corpus_path, KnownVectorProvider()
        );
        assert not blank.ok;
        assert blank.error_code == "name_required";
        blank_profile: ProfileMatchResponse = match_profile_with(
            "Visitor", " \n ", corpus_path, KnownVectorProvider()
        );
        assert not blank_profile.ok;
        assert blank_profile.error_code == "profile_required";
        oversized_name: ProfileMatchResponse = match_profile_with(
            "n" * 101, "profile", corpus_path, KnownVectorProvider()
        );
        assert not oversized_name.ok;
        assert oversized_name.error_code == "name_too_long";
        oversized: ProfileMatchResponse = match_profile_with(
            "Visitor", "x" * 12001, corpus_path, KnownVectorProvider()
        );
        assert not oversized.ok;
        assert oversized.error_code == "profile_too_long";
        failure: ProfileMatchResponse = match_profile_with(
            "Visitor", "profile", corpus_path, FailingProvider()
        );
        assert not failure.ok;
        assert failure.error_code == "provider_failed";
        assert failure.error_retryable;
        assert "SECRET" not in str(failure);
    }
}


test "provider result validation rejects missing duplicate nonfinite and dimensions" {
    with tempfile.TemporaryDirectory(
        prefix="stage15-provider-result-"
    ) as corpus_path {
        write_corpus(corpus_path);
        for failure_mode in ["missing", "duplicate", "nonfinite", "dimension"] {
            response: ProfileMatchResponse = match_profile_with(
                "Visitor",
                "profile",
                corpus_path,
                InvalidResultProvider(failure_mode=failure_mode),
            );
            assert not response.ok;
            assert response.error_code == "provider_result_invalid";
            assert response.error_retryable;
        }
    }
}


test "mock workload provider propagates the validated runtime identity" {
    provider = MockWorkloadProvider(workload_dir=default_workload_dir(), chunk_size=10);
    result: ProviderEmbeddingResult = provider.embed(
        [EmbeddingItem(item_id="one", text="deterministic profile")],
        "stage15-runtime-regression",
    );
    assert result.submitted_item_count == 1;
    assert result.recombined_item_count == 1;
    assert result.runtime_tag in [
        "connection-embedding:1.0.0",
        "connection-embedding-fallback:1.0.0",

    ];
    assert result.result_identity.startswith("sha256:");
    assert len(result.vectors["one"]) == 384;
}


test "provider factory exposes a deterministic safe failure switch" {
    with tempfile.TemporaryDirectory(prefix="stage15-forced-failure-") as corpus_path {
        write_corpus(corpus_path);
        prior = os.environ.get("CONNECTION_PROFILE_FORCE_FAILURE");
        try {
            os.environ["CONNECTION_PROFILE_FORCE_FAILURE"] = "1";
            response: ProfileMatchResponse = match_profile_with(
                "Visitor", "profile", corpus_path, default_embedding_provider(),
            );
            assert not response.ok;
            assert response.error_code == "provider_failed";
            assert response.error_retryable;
        } finally {
            if prior is None {
                del os.environ["CONNECTION_PROFILE_FORCE_FAILURE"];
            } else {
                os.environ["CONNECTION_PROFILE_FORCE_FAILURE"] = prior;
            }
        }
    }
}
