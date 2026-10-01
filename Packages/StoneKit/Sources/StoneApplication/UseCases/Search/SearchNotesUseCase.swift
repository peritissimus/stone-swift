import StoneDomain

/// Full-text search over titles and bodies; ties go to the more recently edited note.
public final class SearchNotesUseCase: Sendable {
    private let repository: any INoteRepository
    private let policy: LocationPolicy

    public init(repository: any INoteRepository, policy: LocationPolicy) {
        self.repository = repository
        self.policy = policy
    }

    public func execute(_ query: String, limit: Int) async throws -> [SearchHit] {
        guard !NoteSearchScorer.terms(of: query).isEmpty else { return [] }
        let notes = try await loadAllNotes(from: repository, policy: policy)
        let hits = notes.compactMap { note -> SearchHit? in
            guard let match = NoteSearchScorer.score(query: query, title: note.title, body: note.body)
            else { return nil }
            return SearchHit(note: note.summary, snippet: match.snippet, score: match.score)
        }
        // `notes` is newest-first and the sort is stable, so equal scores stay by recency.
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }
}
