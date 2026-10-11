import StoneDomain

/// Hybrid shared-index search, with filesystem search available if the database fails.
public final class SearchNotesUseCase: Sendable {
    private let repository: any INoteRepository
    private let policy: LocationPolicy
    private let index: (any INoteSearchIndex)?
    private let indexer: NoteSearchIndexer?
    private let embedder: (any ITextEmbedder)?
    private let reranker: (any ITextReranker)?

    public init(
        repository: any INoteRepository, policy: LocationPolicy,
        index: (any INoteSearchIndex)? = nil, indexer: NoteSearchIndexer? = nil,
        embedder: (any ITextEmbedder)? = nil, reranker: (any ITextReranker)? = nil
    ) {
        self.repository = repository
        self.policy = policy
        self.index = index
        self.indexer = indexer
        self.embedder = embedder
        self.reranker = reranker
    }

    public func execute(_ query: String, limit: Int) async throws -> [SearchHit] {
        guard limit > 0, !NoteSearchScorer.terms(of: query).isEmpty else { return [] }
        try Task.checkCancellation()
        if let index {
            do {
                try await indexer?.prepareForSearch()
                var embedding: TextEmbedding?
                do { embedding = try await embedder?.embed(query) }
                catch is CancellationError { throw CancellationError() }
                catch { embedding = nil }
                try Task.checkCancellation()
                let candidates = try await index.candidates(
                    query: query, embedding: embedding, limit: max(60, min(limit, 34) * 6))
                try Task.checkCancellation()
                return try await rerankedHits(query: query, candidates: candidates, limit: limit)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                // Note lookup still works when the shared index cannot be queried.
            }
        }
        let notes = try await loadAllNotes(from: repository, policy: policy)
        try Task.checkCancellation()
        let hits = notes.compactMap { note -> SearchHit? in
            guard let match = NoteSearchScorer.score(query: query, title: note.title, body: note.body)
            else { return nil }
            return SearchHit(note: note.summary, snippet: match.snippet, score: match.score)
        }
        // `notes` is newest-first and the sort is stable, so equal scores stay by recency.
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    private func rerankedHits(query: String, candidates: [SearchCandidate], limit: Int) async throws -> [SearchHit] {
        let hits = HybridSearchReranker.rerank(query: query, candidates: candidates, limit: candidates.count)
        guard let reranker, hits.count > 1 else { return Array(hits.prefix(limit)) }
        let shortlist = Array(hits.prefix(30))
        let texts = shortlist.map { hit in
            let chunks = candidates.filter { $0.note.path == hit.note.path }
            // Keep the full best chunk for the cross-encoder, rather than shortening it to a UI snippet.
            let best = chunks.max {
                let left = HybridSearchReranker.rerank(query: query, candidates: [$0], limit: 1).first?.score ?? 0
                let right = HybridSearchReranker.rerank(query: query, candidates: [$1], limit: 1).first?.score ?? 0
                return left < right
            }
            return hit.note.title + "\n\n" + (best?.text ?? hit.snippet)
        }
        do {
            let scores = try await reranker.rerank(query: query, texts: texts)
            try Task.checkCancellation()
            guard scores.count == shortlist.count, scores.allSatisfy(\.isFinite) else {
                return Array(hits.prefix(limit))
            }
            let order = shortlist.indices.sorted {
                scores[$0] == scores[$1] ? $0 < $1 : scores[$0] > scores[$1]
            }
            let ordered = order.map { shortlist[$0] } + hits.dropFirst(shortlist.count)
            // A neural shortlist and lexical tail use different scales; expose their final ordinal rank.
            return ordered.prefix(limit).enumerated().map { position, hit in
                SearchHit(note: hit.note, snippet: hit.snippet, score: Double(ordered.count - position))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return Array(hits.prefix(limit))
        }
    }
}
