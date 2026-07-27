"""Application-owned Stage 1.5 embedding provider boundary."""

import os;
import from src.adapters.mock_jacgrid { MockJacGrid, submit_embeddings }
import from src.contracts.models { EmbeddingBatchResult, EmbeddingItem }


obj ProviderEmbeddingResult {
    has provider_mode: str,
        workload_version: str,
        runtime_tag: str,
        result_identity: str,
        terminal_states: list[str],
        result_item_ids: list[str],
        vectors: dict[str, list[float]],
        submitted_item_count: int,
        recombined_item_count: int,
        dimensions: int;
}


obj EmbeddingProvider {
    def embed(
        _items: list[EmbeddingItem], _request_key: str,
    ) -> ProviderEmbeddingResult {
        raise RuntimeError("provider_failed");
    }
}


obj UnavailableEmbeddingProvider(EmbeddingProvider) {
    override def embed(
        _items: list[EmbeddingItem], _request_key: str,
    ) -> ProviderEmbeddingResult {
        raise RuntimeError("provider_failed");
    }
}


obj MockWorkloadProvider(EmbeddingProvider) {
    has workload_dir: str,
        chunk_size: int = 25;

    override def embed(
        items: list[EmbeddingItem], request_key: str,
    ) -> ProviderEmbeddingResult {
        mock = MockJacGrid(workload_dir=self.workload_dir, chunk_size=self.chunk_size);
        result: EmbeddingBatchResult = submit_embeddings(mock, items, request_key);
        dimensions: int = 0;
        if len(result.vectors) > 0 {
            first_id: str = list(result.vectors.keys())[0];
            dimensions = len(result.vectors[first_id]);
        }
        return ProviderEmbeddingResult(
            provider_mode="mock",
            workload_version=result.workload_version,
            runtime_tag=result.runtime_tag,
            result_identity=result.result_sha256,
            terminal_states=[state for state in result.states],
            result_item_ids=[item_id for item_id in result.vectors.keys()],
            vectors={item_id: vector for (item_id, vector) in result.vectors.items()},
            submitted_item_count=len(items),
            recombined_item_count=result.item_count,
            dimensions=dimensions,
        );
    }
}


def default_workload_dir -> str {
    return os.path.abspath(
        os.path.join(
            os.path.dirname(__file__), "../../../../workloads/connection-embedding"
        )
    );
}


def default_embedding_provider -> EmbeddingProvider {
    if os.environ.get("CONNECTION_PROFILE_FORCE_FAILURE", "0") == "1" {
        return UnavailableEmbeddingProvider();
    }
    return MockWorkloadProvider(workload_dir=default_workload_dir());
}
