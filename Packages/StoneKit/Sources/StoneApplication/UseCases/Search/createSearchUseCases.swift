import StoneDomain

public func createSearchUseCases(
    repository: any INoteRepository, policy: LocationPolicy,
    index: (any INoteSearchIndex)? = nil, indexer: NoteSearchIndexer? = nil,
    embedder: (any ITextEmbedder)? = nil, reranker: (any ITextReranker)? = nil
) -> any ISearchUseCases {
    SearchUseCases(searchNotes: SearchNotesUseCase(
        repository: repository, policy: policy, index: index, indexer: indexer, embedder: embedder, reranker: reranker))
}
