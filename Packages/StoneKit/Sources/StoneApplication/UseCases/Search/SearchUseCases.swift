import StoneDomain

public final class SearchUseCases: ISearchUseCases {
    private let searchNotes: SearchNotesUseCase

    init(searchNotes: SearchNotesUseCase) {
        self.searchNotes = searchNotes
    }

    public func search(_ query: String, limit: Int) async throws -> [SearchHit] {
        try await searchNotes.execute(query, limit: limit)
    }
}
