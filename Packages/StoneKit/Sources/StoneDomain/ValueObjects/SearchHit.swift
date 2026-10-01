/// One ranked search result with the excerpt that matched.
public struct SearchHit: Hashable, Sendable, Identifiable {
    public let note: NoteSummary
    public let snippet: String
    public let score: Double

    public var id: NotePath { note.path }

    public init(note: NoteSummary, snippet: String, score: Double) {
        self.note = note
        self.snippet = snippet
        self.score = score
    }
}
