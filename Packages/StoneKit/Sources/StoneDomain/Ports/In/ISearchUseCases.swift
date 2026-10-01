/// What the app can do to find notes.
public protocol ISearchUseCases: Sendable {
    func search(_ query: String, limit: Int) async throws -> [SearchHit]
}
